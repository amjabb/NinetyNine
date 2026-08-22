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
    /// Only consulted when this device is the one establishing the match; a
    /// joiner takes it from the payload, because the deal already happened.
    private var autoAssignWells: Bool = false

    /// Actions we've already surfaced, so re-reading the match data after a turn
    /// change doesn't replay moves the coordinator has already applied.
    private var deliveredCount = 0

    /// Presented for matchmaking; retained so it can be dismissed.
    private weak var presentedMatchmaker: UIViewController?

    /// The in-flight re-read for a turn event that arrived without its data.
    /// Cancelled by the next event, so a burst of turns doesn't stack retries.
    private var staleReadRetry: Task<Void, Never>?
    /// Seconds to wait before each successive re-read.
    private static let staleReadBackoff: [Double] = [1, 2, 4]

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
        ///  - 5: the match creator can bank everyone's well automatically. Every
        ///    client has to agree about whether a well is chosen or dealt, or
        ///    half the table sits on a well builder the other half never saw.
        static let currentRules = 5

        var rulesVersion: Int = MatchPayload.currentRules
        var seed: UInt32
        var cardsDealt: Int
        var participantIDs: [String]
        var participantNames: [String]
        /// Set by whoever starts the match: wells are banked at random rather
        /// than chosen. A match-level rule, not a preference — it changes what
        /// every player is asked to do, so it travels with the deal.
        var autoAssignWells: Bool = false
        var actions: [SubmittedAction]

        /// Absent in payloads written before versioning existed — those are all
        /// version 1 by definition.
        enum CodingKeys: String, CodingKey {
            case rulesVersion, seed, cardsDealt, participantIDs, participantNames
            case autoAssignWells, actions
        }

        init(
            rulesVersion: Int = MatchPayload.currentRules,
            seed: UInt32,
            cardsDealt: Int,
            participantIDs: [String],
            participantNames: [String],
            autoAssignWells: Bool = false,
            actions: [SubmittedAction]
        ) {
            self.rulesVersion = rulesVersion
            self.seed = seed
            self.cardsDealt = cardsDealt
            self.participantIDs = participantIDs
            self.participantNames = participantNames
            self.autoAssignWells = autoAssignWells
            self.actions = actions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rulesVersion = try container.decodeIfPresent(Int.self, forKey: .rulesVersion) ?? 1
            seed = try container.decode(UInt32.self, forKey: .seed)
            cardsDealt = try container.decode(Int.self, forKey: .cardsDealt)
            participantIDs = try container.decode([String].self, forKey: .participantIDs)
            participantNames = try container.decode([String].self, forKey: .participantNames)
            autoAssignWells = try container.decodeIfPresent(Bool.self, forKey: .autoAssignWells) ?? false
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
    /// - Parameter cardsDealt: only consulted when *this* device is the one
    ///   establishing the match. Joining an existing match takes the deal size
    ///   from the payload, because the game was already dealt.
    init(match: GKTurnBasedMatch? = nil, cardsDealt: Int = 7, autoAssignWells: Bool = false) {
        super.init()
        self.match = match
        self.cardsDealt = cardsDealt
        self.autoAssignWells = autoAssignWells
        self.localPlayerID = GKLocalPlayer.local.gamePlayerID
    }

    // MARK: - Matchmaking

    /// Present GameKit's matchmaker and wait for a match.
    /// Put Apple's matchmaker on screen. Does **not** return a match.
    ///
    /// It used to, by awaiting a continuation resumed from the matchmaker's
    /// `didFindMatch:` delegate callback — which Apple deprecated in iOS 9 and
    /// replaced with `GKTurnBasedEventListener`. Nothing has called that method
    /// since 2015, so the continuation only ever resumed on *cancel* or *error*:
    /// choosing a match dismissed the sheet and dropped the player back on the
    /// setup screen, every time.
    ///
    /// The match now arrives at `GameCenterSession`, which is listening from
    /// launch, and the root view opens it.
    static func presentMatchmaker(minPlayers: Int, maxPlayers: Int) throws {
        guard GKLocalPlayer.local.isAuthenticated else { throw MatchError.notAuthenticated }

        let request = GKMatchRequest()
        request.minPlayers = max(2, minPlayers)
        request.maxPlayers = min(6, maxPlayers)
        request.defaultNumberOfPlayers = min(6, maxPlayers)

        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = sharedMatchmakerDelegate
        Self.presentedMatchmaker = controller
        Self.topViewController()?.present(controller, animated: true)
    }

    /// Retained for the lifetime of the presentation: GameKit holds its delegate
    /// weakly, and a deallocated one is a matchmaker that can neither be
    /// cancelled nor report an error.
    private static let sharedMatchmakerDelegate = MatchmakerDelegate(
        onCancel: { dismissMatchmaker() },
        onError: { _ in dismissMatchmaker() }
    )

    private static var presentedMatchmaker: UIViewController?

    static func dismissMatchmaker() {
        presentedMatchmaker?.dismiss(animated: true)
        presentedMatchmaker = nil
    }

    // MARK: - MatchTransport conformance

    /// Re-read the match from Game Center.
    ///
    /// Turn events are pushed, and a push is not a guarantee — one can be missed
    /// while the app is backgrounded, or dropped entirely. For a game where the
    /// whole point is coming back to it later, "we'll hear about it" is not a
    /// synchronisation strategy: coming to the foreground re-reads the match.
    func resync() async {
        guard let match else { return }
        guard let refreshed = try? await GKTurnBasedMatch.load(withID: match.matchID) else {
            // Fall back to re-reading the data on the match we already hold.
            if let data = await loadedData(for: match) { refresh(from: match, data: data) }
            return
        }
        self.match = refreshed
        if var current = payload, Self.reconcileParticipants(&current, with: refreshed) {
            payload = current
        }
        if let data = await loadedData(for: refreshed) {
            refresh(from: refreshed, data: data)
        }
    }

    func start() async throws {
        guard let match else { throw MatchError.matchmakingFailed("no match") }
        // The listener belongs to the session and is registered at launch;
        // this transport just claims the events for its own match.
        GameCenterSession.shared.activeObserver = self

        let existing = await loadedData(for: match)
        if let data = existing, !data.isEmpty,
           let decoded = try? JSONDecoder().decode(MatchPayload.self, from: data) {
            // Joining a match already in progress. Refuse it outright if it was
            // dealt under different rules: the log would apply cleanly and
            // quietly produce a different table from everyone else's.
            guard decoded.isReplayable else { throw MatchError.incompatibleRules }
            var reconciled = decoded
            if Self.reconcileParticipants(&reconciled, with: match) {
                payload = reconciled
                // Persist the real identities if it's our turn to write. If it
                // isn't, the corrected payload still stands locally and whoever
                // writes next will carry it.
                if match.currentParticipant?.player?.gamePlayerID == localPlayerID {
                    try? await write(reconciled, disposition: .keepQuietly)
                }
            } else {
                payload = reconciled
            }
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
                autoAssignWells: autoAssignWells,
                actions: []
            )
            payload = fresh
            try await write(fresh, disposition: .keepQuietly)
        }

        guard let payload else { throw MatchError.matchmakingFailed("no payload") }
        onUpdate?(.started(
            participants: localised(payload.participants),
            seed: payload.seed,
            cardsDealt: payload.cardsDealt,
            autoAssignWells: payload.autoAssignWells
        ))
        deliverPendingActions()
    }

    /// Replace placeholder identities with the real ones, once GameKit knows them.
    ///
    /// A match created with an automatch seat is written *before* anybody fills
    /// it, and at that moment `participant.player` is nil — so the payload
    /// recorded a random UUID named "Player" for that seat. When the real player
    /// arrived, their `gamePlayerID` matched nothing, so their own device treated
    /// them as an unknown extra seat: it drew them as an opponent called
    /// "Player", showed the local player no hand, and waited for a turn from
    /// somebody who was in fact holding the phone.
    ///
    /// Seats are matched by index because `match.participants` is stable and
    /// ordered; only the identities inside them arrive late.
    ///
    /// - Returns: whether anything changed.
    static func reconcileParticipants(_ payload: inout MatchPayload, with match: GKTurnBasedMatch) -> Bool {
        var changed = false
        for (index, participant) in match.participants.enumerated() {
            guard index < payload.participantIDs.count,
                  let player = participant.player
            else { continue }

            let recordedID = payload.participantIDs[index]
            if recordedID != player.gamePlayerID {
                // A seat whose id has changed was a placeholder: a real player
                // cannot change gamePlayerID mid-match. Anything already logged
                // against the placeholder was logged before they arrived, which
                // is why it is safe — and necessary — to carry it across.
                for actionIndex in payload.actions.indices
                where payload.actions[actionIndex].playerID == recordedID {
                    payload.actions[actionIndex].playerID = player.gamePlayerID
                }
                payload.participantIDs[index] = player.gamePlayerID
                changed = true
            }
            if payload.participantNames[index] != player.displayName {
                payload.participantNames[index] = player.displayName
                changed = true
            }
        }
        return changed
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

        try await write(payload, disposition: shouldPassTurn(after: action) ? .pass : .keepAndNotify)
    }

    func leave() async {
        guard let match else { return }
        if match.currentParticipant?.player?.gamePlayerID == localPlayerID {
            // Never `Data()` as a fallback here: `matchData` is nil until it has
            // been loaded, and quitting with an empty blob hands everybody still
            // playing an erased match.
            let data: Data
            if let payload, let encoded = try? encode(payload) {
                data = encoded
            } else {
                data = await MatchLibrary.currentData(of: match)
            }
            try? await match.participantQuitInTurn(
                with: .quit,
                nextParticipants: nextParticipants(after: match),
                turnTimeout: GKTurnTimeoutDefault,
                match: data
            )
        } else {
            try? await match.participantQuitOutOfTurn(with: .quit)
        }
        // Emphatically not `unregisterAllListeners()`: that killed the app's
        // only route for incoming invitations for the rest of the session.
        if GameCenterSession.shared.activeObserver === self {
            GameCenterSession.shared.activeObserver = nil
        }
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

    /// What should happen to the turn once this payload is written.
    private enum TurnDisposition {
        /// Play moves to the next seat.
        case pass
        /// The turn stays here, but the other devices must be told the match
        /// data changed.
        case keepAndNotify
        /// The turn stays here and nobody is notified. Only for the write that
        /// establishes the match, before there is anything to tell anyone.
        case keepQuietly
    }

    private func write(_ payload: MatchPayload, disposition: TurnDisposition) async throws {
        guard let match else { throw MatchError.deliveryFailed }
        let data = try encode(payload)

        switch disposition {
        case .pass:
            try await match.endTurn(
                withNextParticipants: nextParticipants(after: match),
                turnTimeout: GKTurnTimeoutDefault,
                match: data
            )

        case .keepAndNotify:
            // `saveCurrentTurn` stores the data and tells nobody — that is its
            // documented behaviour, and it is why a Snackoo never appeared on
            // anyone else's table until some later move happened to push. Ending
            // the turn is the only call that sends a turn event, so end it *to
            // ourselves*: naming this device first leaves the turn exactly where
            // it was while every other participant still gets the event.
            do {
                try await match.endTurn(
                    withNextParticipants: keepingTurn(in: match),
                    turnTimeout: GKTurnTimeoutDefault,
                    match: data
                )
            } catch {
                // Better a silent save than a lost move: the other devices poll
                // as well, so this degrades to "arrives a little later" rather
                // than "never written".
                try await match.saveCurrentTurn(withMatch: data)
            }

        case .keepQuietly:
            try await match.saveCurrentTurn(withMatch: data)
        }
    }

    /// Everyone still in the match, with *this* device first — the ordering that
    /// keeps the turn here while still sending a turn event to the rest.
    private func keepingTurn(in match: GKTurnBasedMatch) -> [GKTurnBasedParticipant] {
        let active = match.participants.filter { $0.matchOutcome == .none }
        guard let us = active.first(where: { $0.player?.gamePlayerID == localPlayerID })
        else { return active }
        return [us] + active.filter { $0 !== us }
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

    /// The match's data, fetched if it isn't already attached.
    ///
    /// `GKTurnBasedMatch.matchData` is documented as "nil until loaded by
    /// `loadMatchDataWithCompletionHandler:`" — and a match handed to a turn
    /// event listener is exactly that case. Reading the property directly meant
    /// every incoming turn hit a `guard` and returned silently, so an open table
    /// never moved: the opponent's play only appeared after quitting and
    /// reopening, which fetches the match afresh.
    private func loadedData(for match: GKTurnBasedMatch) async -> Data? {
        if let data = match.matchData, !data.isEmpty { return data }
        return try? await match.loadMatchData()
    }

    /// - Returns: whether the payload carried anything we hadn't already seen.
    ///   A turn event whose data hasn't propagated yet reads as `false`, which
    ///   is what `matchDidUpdate` retries on.
    @discardableResult
    private func refresh(from match: GKTurnBasedMatch, data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(MatchPayload.self, from: data)
        else { return false }
        guard decoded.isReplayable else {
            onUpdate?(.disconnected(reason: MatchError.incompatibleRules.localizedDescription))
            return true
        }
        // A shorter log than the one in hand is demonstrably stale — the action
        // log is append-only, so it can only ever grow. Adopting it would be
        // worse than ignoring the event: the next move made here would append to
        // the truncated log and write *that* back, erasing turns that had
        // already been played.
        if let existing = payload, decoded.actions.count < existing.actions.count {
            return false
        }
        let advanced = decoded.actions.count > deliveredCount
        self.match = match
        self.payload = decoded
        deliverPendingActions()
        return advanced
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

// MARK: - Match events

extension GameKitTransport: GameCenterMatchObserver {

    var observedMatchID: String? { match?.matchID }

    func matchDidUpdate(_ match: GKTurnBasedMatch) {
        self.match = match
        // Seats can be filled between turns, so identities are re-checked on
        // every update rather than only at join.
        if var current = payload, Self.reconcileParticipants(&current, with: match) {
            payload = current
        }
        staleReadRetry?.cancel()
        staleReadRetry = Task { @MainActor [weak self] in
            guard let self else { return }
            if let data = await self.loadedData(for: match),
               self.refresh(from: match, data: data) { return }

            // The push can beat the data it is announcing: GameKit routinely
            // delivers a turn event whose `matchData` is still the *previous*
            // turn's, and a straight re-read can return the same stale blob.
            // Apple's own advice for this is a backoff and a re-read rather than
            // one magic delay, so that is what this is.
            for delay in Self.staleReadBackoff {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                guard let refreshed = try? await GKTurnBasedMatch.load(withID: match.matchID),
                      let data = await self.loadedData(for: refreshed)
                else { continue }
                if self.refresh(from: refreshed, data: data) { return }
            }
        }
    }

    func matchDidEnd(_ match: GKTurnBasedMatch) {
        self.match = match
        Task { @MainActor in
            guard let data = await loadedData(for: match) else { return }
            refresh(from: match, data: data)
        }
    }

    func playerWantsToQuit(_ playerID: String) {
        onUpdate?(.participantLeft(playerID: playerID))
    }
}

// MARK: - Matchmaker delegate

/// A small box so the closures can be captured; GameKit holds its delegate
/// weakly, so the transport retains this for the lifetime of the presentation.
private final class MatchmakerDelegate: NSObject, GKTurnBasedMatchmakerViewControllerDelegate {
    private let onCancel: () -> Void
    private let onError: (Error) -> Void

    init(onCancel: @escaping () -> Void, onError: @escaping (Error) -> Void) {
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

    // Deliberately no `didFindMatch:`. It is deprecated, the system no longer
    // calls it, and implementing it is how this was broken in the first place:
    // the selected match arrives at the event listener instead.
}
