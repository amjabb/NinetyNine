//
//  MatchCoordinator.swift
//  Owns the engine for a match and drives it from transport updates.
//
//  This is the piece that makes "solo vs AI", "pass and play", and "online"
//  the same game. The differences between them collapse into two questions:
//
//    * is the player whose turn it is driven by AI in this process?
//    * is the player whose turn it is sitting at *this* device?
//
//  Everything else — rules, events, redaction — is shared.
//

import Foundation

@MainActor
final class MatchCoordinator: ObservableObject {

    // MARK: Published

    /// The redacted view for whoever should currently be looking at the screen.
    @Published private(set) var view: PlayerView?
    /// Events produced by the most recent action, for the presentation layer to
    /// animate. Cleared once consumed.
    @Published private(set) var pendingEvents: [GameEvent] = []
    /// Set when a submitted action was refused, so the UI can explain rather
    /// than silently doing nothing.
    @Published var lastError: String?
    /// In pass-and-play, true while the device should be showing the hand-off
    /// screen instead of the table.
    @Published private(set) var awaitingHandoff = false

    // MARK: State

    private(set) var participants: [MatchParticipant] = []
    private var engine: GameEngine?
    private let transport: MatchTransport
    private var sequence = 0
    /// Every action applied, in order. This is what makes a match replayable and
    /// what would be shipped as GameKit match data.
    private(set) var actionLog: [SubmittedAction] = []
    private var isDrivingAI = false

    var mode: MatchMode

    enum MatchMode: Equatable {
        /// One human on this device, the rest AI.
        case solo
        /// Several humans sharing this device, handing it over between turns.
        case passAndPlay
        /// Humans on other devices.
        case online
    }

    init(transport: MatchTransport, mode: MatchMode) {
        self.transport = transport
        self.mode = mode
        // Synchronous: `send` must not return before the move has been applied,
        // or callers read a stale action log and think they were refused.
        transport.onUpdate = { [weak self] update in
            self?.handle(update)
        }
    }

    // MARK: Lifecycle

    func start() async throws {
        try await transport.start()
    }

    private func handle(_ update: MatchUpdate) {
        switch update {
        case .started(let participants, let seed, let handSize):
            begin(participants: participants, seed: seed, handSize: handSize)

        case .action(let submitted):
            applyRemote(submitted)

        case .participantLeft(let playerID):
            guard let engine, !engine.state.isOver else { return }
            if let events = try? engine.forfeit(by: playerID) {
                absorb(events)
            }

        case .disconnected(let reason):
            lastError = reason
        }
    }

    private func begin(participants: [MatchParticipant], seed: UInt32, handSize: Int) {
        self.participants = participants
        self.matchSeed = seed
        do {
            engine = try GameEngine(
                seats: participants.map { ($0.id, $0.name, $0.enginePlayerKind) },
                // The dealer is the last seat so play opens on the first — a
                // match should never begin by making someone watch.
                dealerIndex: participants.count - 1,
                handSize: handSize,
                seed: seed
            )
            refreshView()
            // The opening deal needs the hand-off armed too, or the first
            // player's cards are face up in front of the whole table. Nothing
            // else calls this until the first action lands.
            updateHandoffState()
            Task { await driveAITurns() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Submitting

    /// Submit a move made by a human on this device.
    func submit(_ action: PlayerAction, by playerID: String) async {
        guard let engine, !engine.state.isOver else { return }

        // Validate locally first. Sending a move we already know is illegal just
        // burns a round trip and produces a worse error message.
        let submitted = SubmittedAction(playerID: playerID, action: action, sequence: sequence)
        do {
            // Dry-run against a replay of the log so the real engine is never
            // left half-mutated by a refused action.
            try validate(submitted)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "That move isn't legal."
            return
        }

        do {
            try await transport.send(submitted)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Couldn't send that move."
        }
    }

    /// Apply an action that arrived from the transport (including our own, echoed
    /// back). This is the only path that mutates the engine.
    private func applyRemote(_ submitted: SubmittedAction) {
        guard let engine else { return }
        do {
            let events = try engine.apply(submitted)
            sequence = max(sequence, submitted.sequence + 1)
            actionLog.append(submitted)
            absorb(events)
            Task { await driveAITurns() }
        } catch {
            // A refused action from a remote peer means the two sides disagree
            // about the state — worth surfacing rather than swallowing, because
            // silently ignoring it is how desyncs become unexplainable.
            lastError = "A move was rejected: \((error as? LocalizedError)?.errorDescription ?? "unknown")"
        }
    }

    /// Check an action without mutating the live engine.
    private func validate(_ submitted: SubmittedAction) throws {
        guard let engine else { throw MatchError.deliveryFailed }
        let available = engine.availableActions(for: submitted.playerID)
        guard available.contains(submitted.action) else {
            // Fall back to the engine's own error for a precise message.
            let scratch = try replayEngine()
            _ = try scratch.apply(submitted)
            return
        }
    }

    /// A fresh engine with the whole log replayed onto it. Used for dry-runs.
    /// Cheap because the log is small and the engine is pure.
    private func replayEngine() throws -> GameEngine {
        guard let engine else { throw MatchError.deliveryFailed }
        let scratch = try GameEngine(
            seats: participants.map { ($0.id, $0.name, $0.enginePlayerKind) },
            dealerIndex: participants.count - 1,
            handSize: engine.state.handSize,
            seed: matchSeed
        )
        for entry in actionLog { try scratch.apply(entry) }
        return scratch
    }

    private var matchSeed: UInt32 = 0

    // MARK: AI

    /// When false, AI turns must be pumped by the presentation layer via
    /// `stepAI()`. How long an opponent appears to think is *feel*, not rules,
    /// so it belongs to whoever is drawing the table — not in here, where it
    /// would fight the animation choreography for control of the pacing.
    var autoDriveAI = true

    /// True when the seat to play is driven by AI in this process.
    var isAITurn: Bool {
        guard let engine, !engine.state.isOver else { return false }
        return participants
            .first { $0.id == engine.state.currentPlayer.id }?
            .kind.difficulty != nil
    }

    /// Take exactly one AI action, if it's an AI's turn. Returns the events it
    /// produced, or nil if there was nothing to do.
    @discardableResult
    func stepAI() -> [GameEvent]? {
        guard let engine, !engine.state.isOver else { return nil }
        let currentID = engine.state.currentPlayer.id
        guard let participant = participants.first(where: { $0.id == currentID }),
              let difficulty = participant.kind.difficulty
        else { return nil }

        let ai = AIPlayer(difficulty: difficulty)
        guard let move = ai.nextMove(for: currentID, engine: engine) else { return nil }

        let action: PlayerAction
        switch move.kind {
        case .play(let cardID, let declaration):
            action = engine.state.pendingWell?.card.id == cardID
                ? .resolveWell(declaration: declaration)
                : .play(cardID: cardID, declaration: declaration)
        // The AI has no information to choose on, so it takes the first slot.
            case .useWell: action = .drawFromWell(slot: 0)
        case .skip: action = .skip
        case .snackoo(let kind): action = .snackoo(kind: PlayerAction.SnackooKind(kind))
        case .concede: action = .concede
        }

        let submitted = SubmittedAction(playerID: currentID, action: action, sequence: sequence)
        sequence += 1
        guard let events = try? engine.apply(submitted) else { return nil }
        actionLog.append(submitted)
        absorb(events)
        return events
    }

    /// How long the current AI seat should appear to think.
    var currentAIThinkingDelay: ClosedRange<Double> {
        guard let engine,
              let difficulty = participants
                .first(where: { $0.id == engine.state.currentPlayer.id })?.kind.difficulty
        else { return 0.5...0.8 }
        return AIPlayer(difficulty: difficulty).thinkingDelay
    }

    /// Play out consecutive AI turns with their own pacing. Only used when
    /// `autoDriveAI` is true (headless tests, previews).
    private func driveAITurns() async {
        guard autoDriveAI, !isDrivingAI else { return }
        isDrivingAI = true
        defer { isDrivingAI = false }

        var safety = 0
        while isAITurn, safety < 400 {
            safety += 1
            try? await Task.sleep(for: .seconds(Double.random(in: currentAIThinkingDelay)))
            guard stepAI() != nil else { break }
        }
        updateHandoffState()
    }

    // MARK: View

    private func absorb(_ events: [GameEvent]) {
        pendingEvents.append(contentsOf: events)
        refreshView()
        updateHandoffState()
    }

    func consumeEvents() -> [GameEvent] {
        let events = pendingEvents
        pendingEvents = []
        return events
    }

    /// Whose eyes should the screen currently be showing?
    ///
    /// Solo and online: always the local player, because only one person is ever
    /// holding this device.
    ///
    /// Pass-and-play: **whoever last confirmed they are holding it** — never
    /// simply whoever's turn it is. Following the turn would swap the view to the
    /// next player's hand while the previous player is still looking at the
    /// screen, which is precisely the leak the hand-off exists to prevent.
    var viewingPlayerID: String? {
        guard engine != nil else { return nil }
        switch mode {
        case .solo, .online:
            return transport.localPlayerID
        case .passAndPlay:
            return acknowledgedViewerID
                ?? participants.first { $0.kind.isLocalHuman }?.id
                ?? transport.localPlayerID
        }
    }

    /// The player who has confirmed they are holding the device. Only
    /// `acknowledgeHandoff()` may change this — refreshing the view must never
    /// advance it, or the hand-off is silently skipped.
    private var acknowledgedViewerID: String?

    private func refreshView() {
        guard let engine, let id = viewingPlayerID else { return }
        view = engine.state.view(for: id)
    }

    /// In pass-and-play the device must be covered between turns, or the next
    /// player sees the previous player's hand — the entire failure mode of
    /// sharing one screen.
    private func updateHandoffState() {
        guard mode == .passAndPlay, let engine, !engine.state.isOver else {
            awaitingHandoff = false
            return
        }
        let current = engine.state.currentPlayer.id
        let isLocalHuman = participants.first(where: { $0.id == current })?.kind.isLocalHuman == true
        awaitingHandoff = isLocalHuman && current != acknowledgedViewerID
    }

    /// The next player has confirmed they're holding the device.
    func acknowledgeHandoff() {
        guard let engine else { return }
        acknowledgedViewerID = engine.state.currentPlayer.id
        awaitingHandoff = false
        refreshView()
    }

    /// Name of whoever the device should be handed to.
    var handoffTargetName: String? {
        guard let engine else { return nil }
        return participants.first { $0.id == engine.state.currentPlayer.id }?.name
    }

    // MARK: Convenience for the UI

    var isOver: Bool { engine?.state.isOver ?? false }
    var winnerID: String? { engine?.state.winnerID }
    var currentPlayerID: String? { engine?.state.currentPlayer.id }

    /// Who deals the next game. The rulebook is specific: the player eliminated
    /// *first* deals next — a small consolation for going out early.
    var nextDealerID: String? { engine?.state.firstEliminatedID }

    /// Final standings, for the game-over screen. Derived from elimination order.
    var finishingOrder: [(participant: MatchParticipant, position: Int)] {
        guard let engine else { return [] }
        return participants.compactMap { participant in
            guard let seat = engine.state.player(id: participant.id) else { return nil }
            return (
                participant,
                Standings.position(
                    eliminationRank: seat.eliminationRank,
                    of: engine.state.players.count
                )
            )
        }
        .sorted { $0.1 < $1.1 }
    }

    func availableActions(for playerID: String) -> [PlayerAction] {
        engine?.availableActions(for: playerID) ?? []
    }

    func turnOptions() -> TurnOptions? {
        engine?.currentPlayerOptions
    }

    func leave() async {
        await transport.leave()
    }
}
