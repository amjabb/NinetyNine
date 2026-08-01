//
//  GameKitTransport.swift
//  Online play over GKTurnBasedMatch.
//
//  This is the whole of the online feature. Everything above it — the rules, the
//  coordinator, the table, the redaction boundary — is the same code that runs
//  solo and pass-and-play, and was already tested against `MatchTransport`
//  before any of this existed.
//
//  Why turn-based rather than real-time: Apple hosts the match state, the
//  matchmaking and the invitations, so there is no server to deploy or pay for.
//  A match survives the app being backgrounded or killed, and a player can take
//  their turn hours later. For a game of discrete turns that is the right shape,
//  and it costs nothing to run.
//
//  The authority is whoever holds the turn. GameKit hands the match data to the
//  current player; they apply their own move and pass it on. That is safe here
//  because a player can only ever act on their own turn, and every action is
//  re-validated against the same `Rules` by every device that receives it — a
//  tampered payload would have to survive validation by every other participant.
//

import Foundation
import GameKit

@MainActor
final class GameKitTransport: NSObject, MatchTransport {

    // MARK: MatchTransport

    private(set) var localPlayerID: String = ""
    var onUpdate: ((MatchUpdate) -> Void)?

    // MARK: State

    /// The match GameKit handed us. Nil until matchmaking completes.
    private var match: GKTurnBasedMatch?
    /// Decoded contents of the match's data blob.
    private var payload: MatchPayload?
    private var cardsDealt: Int = 6

    /// Actions we've already surfaced, so re-reading the match data after a turn
    /// change doesn't replay moves the coordinator has already applied.
    private var deliveredCount = 0

    /// Presented for matchmaking; retained so it can be dismissed.
    private weak var presentedMatchmaker: UIViewController?

    // MARK: - The wire format

    /// What actually gets stored in the match's 64KB data blob.
    ///
    /// The *seed and the action log*, not the game state. Two reasons: the log
    /// replays to a byte-identical state on every device (pinned by
    /// `ReplayTests`), and a serialised `GameState` would contain every player's
    /// hand — handing the whole game to anyone who reads the payload.
    struct MatchPayload: Codable {
        /// Bumped whenever a rules change would make the same seed and action
        /// log replay to a *different* state.
        ///
        /// This is the one kind of incompatibility that can't be detected from
        /// the data itself: an old log applies cleanly to new code and simply
        /// produces a different game, so two players would sit looking at
        /// contradictory tables with nothing flagged.
        ///
        ///  - 2: the well stopped being dealt and started being chosen, which
        ///    changes the deal for every match.
        ///  - 3: shuffling the well became an action. This one breaks the *other*
        ///    way — an older client can't decode a case it has never heard of, so
        ///    the whole payload fails and its match quietly stops updating.
        static let currentRules = 3

        var rulesVersion: Int = MatchPayload.currentRules
        var seed: UInt32
        var cardsDealt: Int
        var participantIDs: [String]
        var participantNames: [String]
        var actions: [SubmittedAction]

        /// Absent in payloads written before versioning existed — those are all
        /// version 1 by definition.
        enum CodingKeys: String, CodingKey {
            case rulesVersion, seed, cardsDealt, participantIDs, participantNames, actions
        }

        init(
            rulesVersion: Int = MatchPayload.currentRules,
            seed: UInt32,
            cardsDealt: Int,
            participantIDs: [String],
            participantNames: [String],
            actions: [SubmittedAction]
        ) {
            self.rulesVersion = rulesVersion
            self.seed = seed
            self.cardsDealt = cardsDealt
            self.participantIDs = participantIDs
            self.participantNames = participantNames
            self.actions = actions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rulesVersion = try container.decodeIfPresent(Int.self, forKey: .rulesVersion) ?? 1
            seed = try container.decode(UInt32.self, forKey: .seed)
            cardsDealt = try container.decode(Int.self, forKey: .cardsDealt)
            participantIDs = try container.decode([String].self, forKey: .participantIDs)
            participantNames = try container.decode([String].self, forKey: .participantNames)
            actions = try container.decode([SubmittedAction].self, forKey: .actions)
        }

        /// Whether this build can replay the log and reach the same table the
        /// other players are looking at.
        var isReplayable: Bool { rulesVersion == MatchPayload.currentRules }

        var participants: [MatchParticipant] {
            zip(participantIDs, participantNames).map { id, name in
                MatchParticipant(id: id, name: name, kind: .remoteHuman)
            }
        }
    }

    // MARK: - Authentication

    /// Sign in to Game Center. Must succeed before matchmaking.
    ///
    /// The handler can be called *more than once* over a process's lifetime —
    /// on sign-out, on account switch — so it is written to be re-entrant rather
    /// than assumed to fire once.
    static func authenticate() async throws -> GKLocalPlayer {
        let player = GKLocalPlayer.local
        if player.isAuthenticated { return player }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            player.authenticateHandler = { viewController, error in
                // Guard against the multiple-invocation contract above; resuming
                // a continuation twice is a crash, not a warning.
                guard !hasResumed else { return }

                if let viewController {
                    // Game Center wants to present its sign-in sheet. Handing it
                    // to the key window is the only way to show it from here.
                    Task { @MainActor in
                        Self.topViewController()?.present(viewController, animated: true)
                    }
                    return
                }
                hasResumed = true
                if let error {
                    continuation.resume(throwing: error)
                } else if player.isAuthenticated {
                    continuation.resume(returning: player)
                } else {
                    continuation.resume(throwing: MatchError.notAuthenticated)
                }
            }
        }
    }

    static var isAuthenticated: Bool { GKLocalPlayer.local.isAuthenticated }

    // MARK: - Init

    /// - Parameter match: an existing match (from an invitation or the
    ///   matchmaker). Pass nil and call `findMatch` to start one.
    init(match: GKTurnBasedMatch? = nil) {
        super.init()
        self.match = match
        self.localPlayerID = GKLocalPlayer.local.gamePlayerID
    }

    // MARK: - Matchmaking

    /// Present GameKit's matchmaker and wait for a match.
    func findMatch(minPlayers: Int, maxPlayers: Int, cardsDealt: Int) async throws -> GKTurnBasedMatch {
        guard GKLocalPlayer.local.isAuthenticated else { throw MatchError.notAuthenticated }
        self.cardsDealt = cardsDealt

        let request = GKMatchRequest()
        request.minPlayers = max(2, minPlayers)
        request.maxPlayers = min(6, maxPlayers)
        request.defaultNumberOfPlayers = maxPlayers

        return try await withCheckedThrowingContinuation { continuation in
            let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
            controller.turnBasedMatchmakerDelegate = MatchmakerDelegate(
                onMatch: { [weak self] match in
                    self?.dismissMatchmaker()
                    continuation.resume(returning: match)
                },
                onCancel: { [weak self] in
                    self?.dismissMatchmaker()
                    continuation.resume(throwing: MatchError.matchmakingFailed("cancelled"))
                },
                onError: { [weak self] error in
                    self?.dismissMatchmaker()
                    continuation.resume(throwing: error)
                }
            )
            // The delegate is only weakly held by GameKit, so it has to be kept
            // alive for the lifetime of the presentation.
            self.matchmakerDelegate = controller.turnBasedMatchmakerDelegate
            self.presentedMatchmaker = controller
            Self.topViewController()?.present(controller, animated: true)
        }
    }

    private var matchmakerDelegate: GKTurnBasedMatchmakerViewControllerDelegate?

    private func dismissMatchmaker() {
        presentedMatchmaker?.dismiss(animated: true)
        presentedMatchmaker = nil
        matchmakerDelegate = nil
    }

    // MARK: - MatchTransport conformance

    func start() async throws {
        guard let match else { throw MatchError.matchmakingFailed("no match") }
        GKLocalPlayer.local.register(self)

        if let data = match.matchData, !data.isEmpty,
           let decoded = try? JSONDecoder().decode(MatchPayload.self, from: data) {
            // Joining a match already in progress. Refuse it outright if it was
            // dealt under different rules: the log would apply cleanly and
            // quietly produce a different table from everyone else's.
            guard decoded.isReplayable else { throw MatchError.incompatibleRules }
            payload = decoded
        } else {
            // We're first: establish the seed and seating, and write it so every
            // other device deals the identical game.
            let participants = match.participants
            let seed = UInt32.random(in: 0...UInt32.max)
            let fresh = MatchPayload(
                seed: seed,
                cardsDealt: cardsDealt,
                participantIDs: participants.map { $0.player?.gamePlayerID ?? UUID().uuidString },
                participantNames: participants.map { $0.player?.displayName ?? "Player" },
                actions: []
            )
            payload = fresh
            try await write(fresh, endingTurn: false)
        }

        guard let payload else { throw MatchError.matchmakingFailed("no payload") }
        onUpdate?(.started(
            participants: localised(payload.participants),
            seed: payload.seed,
            cardsDealt: payload.cardsDealt
        ))
        deliverPendingActions()
    }

    func send(_ action: SubmittedAction) async throws {
        guard var payload, let match else { throw MatchError.deliveryFailed }
        payload.actions.append(action)
        self.payload = payload

        // Surface locally first so the table responds immediately rather than
        // waiting on a network round trip.
        deliveredCount = payload.actions.count
        onUpdate?(.action(action))

        // A forfeit ends our participation rather than passing the turn on.
        if case .forfeit = action.action {
            try await match.participantQuitInTurn(
                with: .quit,
                nextParticipants: nextParticipants(after: match),
                turnTimeout: GKTurnTimeoutDefault,
                match: encode(payload)
            )
            return
        }

        try await write(payload, endingTurn: shouldPassTurn(after: action))
    }

    func leave() async {
        guard let match else { return }
        if match.currentParticipant?.player?.gamePlayerID == localPlayerID {
            try? await match.participantQuitInTurn(
                with: .quit,
                nextParticipants: nextParticipants(after: match),
                turnTimeout: GKTurnTimeoutDefault,
                match: match.matchData ?? Data()
            )
        } else {
            try? await match.participantQuitOutOfTurn(with: .quit)
        }
        GKLocalPlayer.local.unregisterAllListeners()
    }

    // MARK: - Writing

    private func encode(_ payload: MatchPayload) throws -> Data {
        let data = try JSONEncoder().encode(payload)
        // GKTurnBasedMatch caps match data at 64KB. `ReplayTests` asserts a whole
        // game's log stays well inside that, but a hard check here turns a silent
        // truncation into a clear error.
        guard data.count < 60_000 else { throw MatchError.deliveryFailed }
        return data
    }

    private func write(_ payload: MatchPayload, endingTurn: Bool) async throws {
        guard let match else { throw MatchError.deliveryFailed }
        let data = try encode(payload)

        if endingTurn {
            try await match.endTurn(
                withNextParticipants: nextParticipants(after: match),
                turnTimeout: GKTurnTimeoutDefault,
                match: data
            )
        } else {
            try await match.saveCurrentTurn(withMatch: data)
        }
    }

    /// Everyone still in the match, ordered so the next seat plays next.
    private func nextParticipants(after match: GKTurnBasedMatch) -> [GKTurnBasedParticipant] {
        let active = match.participants.filter { $0.matchOutcome == .none }
        guard let currentIndex = active.firstIndex(where: {
            $0.player?.gamePlayerID == localPlayerID
        }) else { return active }
        // Rotate so the participant after us is first.
        return Array(active[(currentIndex + 1)...] + active[..<currentIndex])
    }

    /// Snackoo is a free action and forfeit ends participation; everything else
    /// passes the turn on.
    private func shouldPassTurn(after action: SubmittedAction) -> Bool {
        switch action.action {
        case .snackoo, .forfeit: return false
        default: return true
        }
    }

    // MARK: - Reading

    /// Push any actions we haven't surfaced yet up to the coordinator.
    private func deliverPendingActions() {
        guard let payload else { return }
        guard payload.actions.count > deliveredCount else { return }
        for action in payload.actions[deliveredCount...] {
            onUpdate?(.action(action))
        }
        deliveredCount = payload.actions.count
    }

    /// GameKit knows players by `gamePlayerID`; mark whichever is us as local so
    /// the coordinator shows our hand rather than treating every seat as remote.
    private func localised(_ participants: [MatchParticipant]) -> [MatchParticipant] {
        participants.map { participant in
            guard participant.id == localPlayerID else { return participant }
            return MatchParticipant(id: participant.id, name: participant.name, kind: .localHuman)
        }
    }

    private func refresh(from match: GKTurnBasedMatch) {
        guard let data = match.matchData, !data.isEmpty,
              let decoded = try? JSONDecoder().decode(MatchPayload.self, from: data)
        else { return }
        guard decoded.isReplayable else {
            onUpdate?(.disconnected(reason: MatchError.incompatibleRules.localizedDescription))
            return
        }
        self.match = match
        self.payload = decoded
        deliverPendingActions()
    }

    // MARK: - Presentation

    /// GameKit presents UIKit controllers, so it needs a host. Walking the
    /// window hierarchy is unavoidable from a SwiftUI app.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - GameKit events

extension GameKitTransport: GKLocalPlayerListener {

    /// The turn moved — either to us, or past us.
    nonisolated func player(
        _ player: GKPlayer,
        receivedTurnEventFor match: GKTurnBasedMatch,
        didBecomeActive: Bool
    ) {
        // GameKit calls listeners on an arbitrary queue. The transport protocol
        // is @MainActor and its callers rely on synchronous delivery, so hopping
        // here is the adapter's job — not its callers'.
        Task { @MainActor in
            self.refresh(from: match)
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        Task { @MainActor in
            self.refresh(from: match)
        }
    }

    nonisolated func player(
        _ player: GKPlayer,
        wantsToQuitMatch match: GKTurnBasedMatch
    ) {
        Task { @MainActor in
            self.onUpdate?(.participantLeft(playerID: player.gamePlayerID))
        }
    }
}

// MARK: - Matchmaker delegate

/// A small box so the closures can be captured; GameKit holds its delegate
/// weakly, so the transport retains this for the lifetime of the presentation.
private final class MatchmakerDelegate: NSObject, GKTurnBasedMatchmakerViewControllerDelegate {
    private let onMatch: (GKTurnBasedMatch) -> Void
    private let onCancel: () -> Void
    private let onError: (Error) -> Void

    init(
        onMatch: @escaping (GKTurnBasedMatch) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onMatch = onMatch
        self.onCancel = onCancel
        self.onError = onError
    }

    func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
        onCancel()
    }

    func turnBasedMatchmakerViewController(
        _ viewController: GKTurnBasedMatchmakerViewController,
        didFailWithError error: Error
    ) {
        onError(error)
    }
}
