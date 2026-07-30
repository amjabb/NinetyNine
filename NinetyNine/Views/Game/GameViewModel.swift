//
//  GameViewModel.swift
//  Turns a match's event timeline into something the table can animate.
//
//  The engine is synchronous and instant: applying an action returns the whole
//  consequence as an array of events. The table needs those consequences spread
//  over time — the card flies, *then* the tally ticks, *then* the lock snaps
//  shut, *then* the next player starts thinking. This class owns that
//  choreography, and it is the only place in the app that knows about timing.
//
//  It sits on a `MatchCoordinator`, which means one view model and one table
//  screen serve solo, pass-and-play, and (later) online. The differences between
//  those collapse to two questions the coordinator already answers: is the seat
//  to play driven by AI in this process, and is that seat at this device.
//
//  Consequently the table only ever sees a redacted `PlayerView` — solo included.
//  There is no code path where the screen holds another player's cards.
//

import SwiftUI

@MainActor
final class GameViewModel: ObservableObject {

    // MARK: - Published table state

    /// What the person holding the device is allowed to see.
    @Published private(set) var view: PlayerView?
    /// Nil until the game ends.
    @Published private(set) var outcome: Outcome?

    /// A transient banner describing the last significant thing that happened.
    @Published var announcement: Announcement?
    /// The floating +8 / −10 chip, cleared automatically.
    @Published var tallyDelta: Int?
    /// Set while a 9 is landing, so the gauge can use the slam curve.
    @Published var isSlamming = false
    /// The card currently in flight to the discard pile.
    @Published var cardInFlight: Card?
    /// Drives the drum-roll → flip → verdict sequence.
    @Published var wellReveal: WellRevealPhase = .idle
    /// Which opponent is "thinking", for their seat's progress ring.
    @Published var thinkingPlayerID: String?
    /// Whose declaration the player is being asked for, if any.
    @Published var pendingChoice: PendingChoice?
    /// Set when the player taps a card that can't legally be played.
    @Published var rejection: Rejection?
    /// The achievement toast currently on screen.
    @Published var achievementToast: Achievement?
    /// True while cards are being dealt at the start of a game.
    @Published var isDealing = true
    /// Pass-and-play only: cover the screen until the next player confirms.
    @Published private(set) var awaitingHandoff = false

    // MARK: - Configuration

    let mode: MatchCoordinator.MatchMode
    private let coordinator: MatchCoordinator
    private let difficulty: Difficulty
    private let records: Records
    private let settings: Settings
    private var hasRecordedEnd = false
    private var isDrivingAI = false
    /// Solo only: the single human whose achievements are being tracked. In
    /// pass-and-play nobody's lifetime record is touched — it isn't one person's
    /// game, and crediting the device owner with a shared win would be a lie.
    private let recordedPlayerID: String?

    // MARK: - Types

    enum Outcome: Equatable {
        case won
        /// `position` is the finishing place: 2 is runner-up, `players.count` is
        /// last (the first player knocked out).
        case lost(position: Int)
    }

    struct Announcement: Identifiable, Equatable {
        let id = UUID()
        var headline: String
        var detail: String?
        var tone: Tone

        enum Tone { case neutral, good, bad, danger, poison }
    }

    enum WellRevealPhase: Equatable {
        case idle
        /// The player is being asked which of their face-down well cards to turn
        /// over. Only shown for a human on this device — the AI has nothing to
        /// choose on.
        case choosing(playerID: String, slots: Int)
        case rolling(playerID: String)
        case revealed(card: Card, playable: Bool, playerID: String)
    }

    struct PendingChoice: Identifiable, Equatable {
        let id = UUID()
        var card: Card
        var options: [Declaration]
        var isFromWell: Bool
    }

    struct Rejection: Identifiable, Equatable {
        let id = UUID()
        var cardID: Int
        var message: String
    }

    // MARK: - Init

    /// Solo: one human on this device, the rest AI.
    static func solo(
        difficulty: Difficulty,
        opponentCount: Int,
        handSize: Int,
        playerName: String,
        dealerID: String? = nil,
        seed: UInt32? = nil
    ) -> GameViewModel {
        var participants = [MatchParticipant(id: "human", name: playerName, kind: .localHuman)]
        let names = opponentNames(for: difficulty)
        for index in 0..<opponentCount {
            participants.append(
                MatchParticipant(id: "ai\(index)", name: names[index % names.count], kind: .ai(difficulty))
            )
        }
        return GameViewModel(
            participants: participants,
            mode: .solo,
            difficulty: difficulty,
            handSize: handSize,
            dealerID: dealerID,
            seed: seed,
            recordedPlayerID: "human"
        )
    }

    /// Pass-and-play: several humans sharing this device.
    static func passAndPlay(
        playerNames: [String],
        handSize: Int,
        dealerID: String? = nil,
        seed: UInt32? = nil
    ) -> GameViewModel {
        let participants = playerNames.enumerated().map { index, name in
            MatchParticipant(
                id: "p\(index)",
                name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Player \(index + 1)" : name,
                kind: .localHuman
            )
        }
        return GameViewModel(
            participants: participants,
            mode: .passAndPlay,
            difficulty: .sharp,
            handSize: handSize,
            dealerID: dealerID,
            seed: seed,
            recordedPlayerID: nil
        )
    }

    private init(
        participants: [MatchParticipant],
        mode: MatchCoordinator.MatchMode,
        difficulty: Difficulty,
        handSize: Int,
        dealerID: String?,
        seed: UInt32?,
        recordedPlayerID: String?,
        records: Records = .shared,
        settings: Settings = .shared
    ) {
        self.mode = mode
        self.difficulty = difficulty
        self.records = records
        self.settings = settings
        self.recordedPlayerID = recordedPlayerID

        // The dealer sits last so play opens on the seat after them, per the
        // rulebook. Rotating the seating rather than passing an index keeps the
        // transport's participant order and the engine's seating identical.
        let seated: [MatchParticipant]
        if let dealerID, let dealerIndex = participants.firstIndex(where: { $0.id == dealerID }) {
            let after = dealerIndex + 1
            seated = Array(participants[after...] + participants[..<after])
        } else {
            seated = participants
        }

        let transport = LoopbackTransport(
            localPlayerID: seated.first { $0.kind.isLocalHuman }?.id ?? seated[0].id,
            participants: seated,
            seed: seed ?? UInt32.random(in: 0...UInt32.max),
            handSize: handSize
        )
        self.coordinator = MatchCoordinator(transport: transport, mode: mode)
        // Pacing lives here, not in the coordinator — otherwise two systems
        // fight over when an opponent's move is allowed to appear.
        self.coordinator.autoDriveAI = false
    }

    /// Validate a configuration without starting it, so an impossible table is
    /// caught on the setup screen rather than on a broken game screen.
    static func canDeal(playerCount: Int, handSize: Int) -> Bool {
        guard (2...6).contains(playerCount) else { return false }
        return handSize >= Rules.minHandSize && handSize <= Rules.maxHandSize(forPlayerCount: playerCount)
    }

    private static func opponentNames(for difficulty: Difficulty) -> [String] {
        switch difficulty {
        case .casual: return ["Pip", "Dot", "Bram", "Sunny", "Nell"]
        case .sharp: return ["Vale", "Corbin", "Ida", "Rook", "Marlow"]
        case .ruthless: return ["Mordant", "Sable", "Vex", "Grieve", "Thorne"]
        }
    }

    // MARK: - Derived view state

    var participants: [MatchParticipant] { coordinator.participants }

    /// The seat currently being shown. In pass-and-play this is whoever last
    /// confirmed they're holding the device — never simply whoever's turn it is.
    var viewingPlayerID: String? { coordinator.viewingPlayerID }

    var isYourTurn: Bool {
        guard let view else { return false }
        return view.isYourTurn && !awaitingHandoff
    }

    var opponents: [OpponentView] { view?.opponents ?? [] }
    var yourHand: [Card] { view?.yourHand ?? [] }

    /// Cards legal against the current board. Computed from the redacted view,
    /// through the same `Rules` the engine uses.
    var playableCardIDs: Set<Int> {
        guard let view, wellReveal == .idle, pendingChoice == nil, !view.isOver else { return [] }
        return view.playableCardIDs
    }

    var options: TurnOptions {
        coordinator.turnOptions() ?? TurnOptions(
            canPlayFromHand: false, canUseWell: false, canSkip: false, isStranded: false
        )
    }

    var snackooRanks: [Rank] {
        guard let view else { return [] }
        var counts: [Rank: Int] = [:]
        for card in view.yourHand where card.rank != .queen {
            counts[card.rank, default: 0] += 1
        }
        return Rank.allCases.filter { (counts[$0] ?? 0) >= 3 }
    }

    var canSnackooPoison: Bool { (view?.yourPoisonPile.count ?? 0) >= 3 }

    var handoffTargetName: String? { coordinator.handoffTargetName }
    var handoffSeatNumber: Int {
        guard let current = coordinator.currentPlayerID,
              let index = participants.firstIndex(where: { $0.id == current })
        else { return 1 }
        return index + 1
    }

    func projectedTally(for card: Card, declaration: Declaration) -> Int? {
        guard let view else { return nil }
        guard case .success(let effect) = Rules.resolve(
            card: card, declaration: declaration, in: view.rulesContext()
        ) else { return nil }
        return effect.newTally
    }

    // MARK: - Opening

    func begin() async {
        SoundEngine.shared.warmUp()
        do {
            try await coordinator.start()
        } catch {
            announce(headline: "Couldn't deal", detail: error.localizedDescription, tone: .bad)
            return
        }
        syncFromCoordinator()

        SoundEngine.shared.play(.shuffle, volume: 0.8)
        let dealtCards = view?.yourHand.count ?? 6
        try? await Task.sleep(for: .milliseconds(Int(Double(dealtCards) * Motion.dealStagger * 1000) + 620))
        isDealing = false

        if mode == .passAndPlay {
            // The first player must confirm they're holding the device too,
            // otherwise the deal is face-up in front of everyone.
            refreshHandoff()
        } else {
            Haptics.shared.play(.turnStart)
        }
        await driveAITurns()
    }

    // MARK: - Player actions

    func tapCard(_ card: Card) {
        guard isYourTurn, !isDealing, wellReveal == .idle, pendingChoice == nil,
              let view else { return }

        let declarations = Rules.legalDeclarations(for: card, in: view.rulesContext())
        guard !declarations.isEmpty else {
            reject(card)
            return
        }
        if declarations.count == 1 {
            Task { await commitPlay(card: card, declaration: declarations[0], fromWell: false) }
            return
        }

        Haptics.shared.play(.cardLift)
        SoundEngine.shared.play(.cardLift, volume: 0.6)
        withAnimation(Motion.panel) {
            pendingChoice = PendingChoice(card: card, options: declarations, isFromWell: false)
        }
    }

    func chooseDeclaration(_ declaration: Declaration) {
        guard let choice = pendingChoice else { return }
        withAnimation(Motion.panel) { pendingChoice = nil }
        Task { await commitPlay(card: choice.card, declaration: declaration, fromWell: choice.isFromWell) }
    }

    func cancelChoice() {
        Haptics.shared.play(.select)
        withAnimation(Motion.panel) { pendingChoice = nil }
    }

    private func reject(_ card: Card) {
        Haptics.shared.play(.rejected)
        SoundEngine.shared.play(.reject, volume: 0.7)
        let message = view.flatMap { Rules.blockingReason(for: card, in: $0.rulesContext())?.explanation }
            ?? "That card can't be played right now."
        withAnimation(Motion.panel) { rejection = Rejection(cardID: card.id, message: message) }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(Motion.panel) { if rejection?.cardID == card.id { rejection = nil } }
        }
    }

    func declareSnackoo(_ kind: GameEvent.SnackooKind) {
        guard let actor = viewingPlayerID else { return }
        Task {
            await submit(.snackoo(kind: PlayerAction.SnackooKind(kind)), by: actor) {
                Haptics.shared.play(.snackoo)
                SoundEngine.shared.play(.snackoo)
                self.announce(headline: "Snackoo!", detail: self.snackooDetail(kind), tone: .good)
            }
        }
    }

    private func snackooDetail(_ kind: GameEvent.SnackooKind) -> String {
        switch kind {
        case .threeOfAKind(let rank): return "Three \(rank.displayName)s away, three fresh cards in."
        case .threeQueens: return "The poison pile is clear."
        }
    }

    /// Opens the well. The player picks a card before anything is revealed.
    func useWell() {
        guard isYourTurn, options.canUseWell, let actor = viewingPlayerID,
              let remaining = view?.yourWellCount, remaining > 0 else { return }
        Haptics.shared.play(.cardLift)
        withAnimation(Motion.drama) {
            wellReveal = .choosing(playerID: actor, slots: remaining)
        }
    }

    /// The player chose which face-down card to turn over.
    func chooseWellCard(slot: Int) {
        guard case .choosing(let actor, _) = wellReveal else { return }
        Task { await runWell(for: actor, slot: slot) }
    }

    func cancelWellChoice() {
        Haptics.shared.play(.select)
        withAnimation(Motion.drama) { wellReveal = .idle }
    }

    func skipTurn() {
        guard isYourTurn, options.canSkip, let actor = viewingPlayerID else { return }
        Task {
            await submit(.skip, by: actor) {
                Haptics.shared.play(.cardLand)
                self.announce(
                    headline: "Skipped",
                    detail: "Two plays owed next turn.",
                    tone: .neutral
                )
            }
        }
    }

    func concede() {
        guard let actor = viewingPlayerID else { return }
        Task { await submit(.concede, by: actor) {} }
    }

    func acknowledgeHandoff() {
        Haptics.shared.play(.turnStart)
        coordinator.acknowledgeHandoff()
        syncFromCoordinator()
        awaitingHandoff = false
        // A fresh hand deserves the deal animation, so the new player sees their
        // cards arrive rather than blinking into existence.
        isDealing = true
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(Motion.deal) { isDealing = false }
        }
    }

    // MARK: - Submitting

    /// Shared path for every action: submit, then pace the resulting events.
    private func submit(
        _ action: PlayerAction,
        by playerID: String,
        onAccepted: @escaping () -> Void
    ) async {
        let before = coordinator.actionLog.count
        await coordinator.submit(action, by: playerID)

        if let error = coordinator.lastError {
            coordinator.lastError = nil
            Haptics.shared.play(.rejected)
            announce(headline: "Not legal", detail: error, tone: .bad)
            return
        }
        guard coordinator.actionLog.count > before else { return }

        onAccepted()
        await absorb(coordinator.consumeEvents())
        await driveAITurns()
    }

    private func commitPlay(card: Card, declaration: Declaration, fromWell: Bool) async {
        guard let actor = viewingPlayerID else { return }

        Haptics.shared.play(.cardFlick)
        SoundEngine.shared.play(.cardFlick)
        withAnimation(Motion.cardFlight) { cardInFlight = card }

        let action: PlayerAction = fromWell
            ? .resolveWell(declaration: declaration)
            : .play(cardID: card.id, declaration: declaration)

        let before = coordinator.actionLog.count
        await coordinator.submit(action, by: actor)

        try? await Task.sleep(for: .milliseconds(150))
        cardInFlight = nil

        if let error = coordinator.lastError {
            coordinator.lastError = nil
            reject(card)
            _ = error
            return
        }
        guard coordinator.actionLog.count > before else { return }

        await absorb(coordinator.consumeEvents())
        await driveAITurns()
    }

    // MARK: - The well

    private func runWell(for playerID: String, slot: Int) async {
        withAnimation(Motion.drama) { wellReveal = .rolling(playerID: playerID) }
        Haptics.shared.play(.wellReveal)
        SoundEngine.shared.play(.wellRoll)
        try? await Task.sleep(for: .milliseconds(950))

        let before = coordinator.actionLog.count
        await coordinator.submit(.drawFromWell(slot: slot), by: playerID)
        guard coordinator.actionLog.count > before else {
            coordinator.lastError = nil
            withAnimation(Motion.drama) { wellReveal = .idle }
            return
        }

        let events = coordinator.consumeEvents()
        guard case .wellRevealed(let card, _, let playable) = events.first else {
            withAnimation(Motion.drama) { wellReveal = .idle }
            await absorb(events)
            return
        }

        withAnimation(Motion.drama) {
            wellReveal = .revealed(card: card, playable: playable, playerID: playerID)
        }
        if playable {
            Haptics.shared.play(.wellSurvive)
            SoundEngine.shared.play(.wellSurvive)
        } else {
            Haptics.shared.play(.eliminated)
            SoundEngine.shared.play(.eliminated)
        }
        try? await Task.sleep(for: .milliseconds(playable ? 1_250 : 1_900))
        withAnimation(Motion.drama) { wellReveal = .idle }

        await absorb(events)

        if playable, let pending = view?.pendingWell, pending.playerID == playerID, let view {
            let declarations = Rules.legalDeclarations(for: pending.card, in: view.rulesContext())
            if declarations.count == 1 {
                await commitPlay(card: pending.card, declaration: declarations[0], fromWell: true)
            } else {
                withAnimation(Motion.panel) {
                    pendingChoice = PendingChoice(card: pending.card, options: declarations, isFromWell: true)
                }
            }
            return
        }
        await driveAITurns()
    }

    // MARK: - AI

    /// Pump AI seats one move at a time, pacing each so the table stays readable.
    private func driveAITurns() async {
        guard !isDrivingAI else { return }
        isDrivingAI = true
        defer { isDrivingAI = false }

        var safety = 0
        while coordinator.isAITurn, !coordinator.isOver, safety < 400 {
            safety += 1
            let thinker = coordinator.currentPlayerID
            thinkingPlayerID = thinker
            try? await Task.sleep(for: .seconds(Double.random(in: coordinator.currentAIThinkingDelay)))
            thinkingPlayerID = nil

            guard coordinator.stepAI() != nil else { break }
            await absorb(coordinator.consumeEvents())
        }

        syncFromCoordinator()
        refreshHandoff()

        if isYourTurn, options.isStranded {
            announce(
                headline: "Nowhere to go",
                detail: "No legal card, no well, and a play owed.",
                tone: .bad
            )
        }
    }

    // MARK: - Event choreography

    private func absorb(_ events: [GameEvent]) async {
        for event in events {
            switch event {
            case .tallyChanged(let from, let to):
                let delta = to - from
                let pressure = to > 0 ? min(1, Double(to) / 99.0) : 0
                withAnimation(Motion.tallyTick) {
                    syncFromCoordinator()
                    tallyDelta = delta
                }
                if delta != 0 {
                    Haptics.shared.play(delta > 0 ? .tallyClimb(pressure: pressure) : .tallyDrop)
                    SoundEngine.shared.playTick(pressure: pressure)
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(1_100))
                    withAnimation(.easeOut(duration: 0.3)) { tallyDelta = nil }
                }

            case .nineSlammed:
                isSlamming = true
                Haptics.shared.play(.slam)
                SoundEngine.shared.play(.slam)
                announce(headline: "Ninety-nine.", detail: "No room left.", tone: .danger)
                try? await Task.sleep(for: .milliseconds(420))
                isSlamming = false

            case .hundredReached:
                Haptics.shared.play(.hundred)
                SoundEngine.shared.play(.hundred)
                announce(
                    headline: "One hundred!",
                    detail: "The next card played counts negative.",
                    tone: .danger
                )
                try? await Task.sleep(for: .milliseconds(700))

            case .suitLocked(let suit, let by):
                Haptics.shared.play(.lock)
                SoundEngine.shared.play(.lock)
                announce(
                    headline: "\(suit.displayName) locked",
                    detail: "\(name(of: by)) named the suit. Follow it or skip.",
                    tone: .neutral
                )
                try? await Task.sleep(for: .milliseconds(320))

            case .suitLockLifted:
                announce(headline: "Lock broken", detail: "Any suit is legal again.", tone: .good)

            case .directionReversed(let clockwise):
                Haptics.shared.play(.reverse)
                SoundEngine.shared.play(.reverse)
                announce(
                    headline: clockwise ? "Clockwise" : "Counter-clockwise",
                    detail: "Turn order reversed.",
                    tone: .neutral
                )
                try? await Task.sleep(for: .milliseconds(280))

            case .queensBecamePoisonous(let trigger):
                Haptics.shared.play(.poison)
                SoundEngine.shared.play(.poison)
                announce(
                    headline: "Queens are poisonous",
                    detail: "\(name(of: trigger)) drew one. Every held Queen is exiled.",
                    tone: .poison
                )
                try? await Task.sleep(for: .milliseconds(900))

            case .queenPoisoned(_, let owner, let cap):
                if owner == viewingPlayerID {
                    Haptics.shared.play(.poison)
                    announce(
                        headline: "Queen exiled",
                        detail: "Your hand limit drops to \(cap).",
                        tone: .poison
                    )
                    try? await Task.sleep(for: .milliseconds(400))
                }

            case .snackoo(let by, let kind):
                if by != viewingPlayerID {
                    SoundEngine.shared.play(.snackoo, volume: 0.7)
                    announce(headline: "\(name(of: by)): Snackoo!", detail: snackooDetail(kind), tone: .neutral)
                    try? await Task.sleep(for: .milliseconds(500))
                }

            case .drawPileReshuffled:
                SoundEngine.shared.play(.shuffle, volume: 0.6)
                announce(headline: "Reshuffled", detail: "The discards are back in play.", tone: .neutral)

            case .cardPlayed(let card, let by, _) where by != viewingPlayerID:
                SoundEngine.shared.play(.cardLand, volume: 0.8)
                withAnimation(Motion.cardFlight) {
                    cardInFlight = card
                    syncFromCoordinator()
                }
                try? await Task.sleep(for: .milliseconds(180))
                cardInFlight = nil

            case .playerEliminated(let id, let reason, _):
                if id == viewingPlayerID {
                    Haptics.shared.play(.eliminated)
                    SoundEngine.shared.play(.eliminated)
                    announce(headline: "You're out", detail: reason.explanation, tone: .bad)
                } else {
                    SoundEngine.shared.play(.eliminated, volume: 0.7)
                    announce(headline: "\(name(of: id)) is out", detail: reason.explanation, tone: .good)
                }
                withAnimation(Motion.drama) { syncFromCoordinator() }
                try? await Task.sleep(for: .milliseconds(1_100))

            case .gameWon(let winner):
                withAnimation(Motion.drama) { syncFromCoordinator() }
                finish(winnerID: winner)
                return

            case .turnAdvanced(let to, let owesTwo):
                withAnimation(Motion.handReflow) { syncFromCoordinator() }
                if to == viewingPlayerID && !coordinator.isOver {
                    Haptics.shared.play(.turnStart)
                    if owesTwo {
                        announce(
                            headline: "Two plays owed",
                            detail: "Both must be legal. You can't skip again.",
                            tone: .danger
                        )
                    }
                }

            default:
                withAnimation(Motion.handReflow) { syncFromCoordinator() }
            }
        }

        syncFromCoordinator()
        refreshHandoff()
        recordProgress(events)
    }

    // MARK: - Syncing

    private func syncFromCoordinator() {
        view = coordinator.view
    }

    private func refreshHandoff() {
        guard mode == .passAndPlay else {
            awaitingHandoff = false
            return
        }
        let shouldCover = coordinator.awaitingHandoff && !coordinator.isOver
        if shouldCover != awaitingHandoff {
            withAnimation(Motion.drama) { awaitingHandoff = shouldCover }
        }
    }

    // MARK: - Records

    /// Only solo games touch the lifetime record. A pass-and-play win belongs to
    /// whoever was holding the phone, not to the device's owner.
    private func recordProgress(_ events: [GameEvent]) {
        guard let recordedPlayerID, let view else { return }
        records.record(events: events, humanID: recordedPlayerID, state: view.rulesContext())
        surfaceAchievementToast()
    }

    // MARK: - Endgame

    private func finish(winnerID: String) {
        guard !hasRecordedEnd else { return }
        hasRecordedEnd = true

        let standings = coordinator.finishingOrder
        let subjectID = recordedPlayerID ?? viewingPlayerID
        let won = winnerID == subjectID

        if won {
            Haptics.shared.play(.victory)
            SoundEngine.shared.play(.victory)
            outcome = .won
        } else {
            let position = standings.first { $0.participant.id == subjectID }?.position
                ?? participants.count
            outcome = .lost(position: position)
        }

        if let recordedPlayerID, let view {
            records.recordGameEnd(
                won: won,
                state: view.rulesContext(),
                humanID: recordedPlayerID,
                difficulty: difficulty
            )
            surfaceAchievementToast()
        }
    }

    /// Final standings for the game-over screen.
    var finishingOrder: [(participant: MatchParticipant, position: Int)] {
        coordinator.finishingOrder
    }

    var winnerName: String? {
        guard let id = coordinator.winnerID else { return nil }
        return participants.first { $0.id == id }?.name
    }

    /// Who deals the next game — the first player knocked out, per the rulebook.
    /// Falls back to the winner if nobody was eliminated (can't happen in a
    /// finished game, but the UI shouldn't depend on that).
    var nextDealer: MatchParticipant? {
        let id = coordinator.nextDealerID ?? coordinator.winnerID
        return participants.first { $0.id == id }
    }

    // MARK: - Helpers

    private func name(of playerID: String) -> String {
        if playerID == viewingPlayerID { return "You" }
        return participants.first { $0.id == playerID }?.name ?? "Someone"
    }

    private func announce(headline: String, detail: String?, tone: Announcement.Tone) {
        withAnimation(Motion.panel) {
            announcement = Announcement(headline: headline, detail: detail, tone: tone)
        }
        let id = announcement?.id
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if announcement?.id == id {
                withAnimation(Motion.panel) { announcement = nil }
            }
        }
    }

    private func surfaceAchievementToast() {
        guard achievementToast == nil, let next = records.drainToast() else { return }
        withAnimation(Motion.panel) { achievementToast = next }
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            withAnimation(Motion.panel) { achievementToast = nil }
            surfaceAchievementToast()
        }
    }
}
