//
//  GameViewModel.swift
//  Turns the engine's event timeline into something the table can animate.
//
//  The engine is synchronous and instant: `play` returns the whole consequence
//  as an array of events. The table needs those consequences spread over time —
//  the card flies, *then* the tally ticks, *then* the lock snaps shut, *then*
//  the next player starts thinking. This class owns that choreography, and it is
//  the only place in the app that knows about timing.
//

import SwiftUI

@MainActor
final class GameViewModel: ObservableObject {

    // MARK: - Published table state

    @Published private(set) var state: GameState
    /// Nil until the game ends.
    @Published private(set) var outcome: Outcome?

    /// A transient banner describing the last significant thing that happened.
    @Published var announcement: Announcement?
    /// The floating +8 / −10 chip, cleared automatically.
    @Published var tallyDelta: Int?
    /// Set while a 9 is landing, so the gauge can use the slam curve.
    @Published var isSlamming = false
    /// The card currently in flight to the discard pile, for the flight animation.
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

    // MARK: - Configuration

    let humanID = "human"
    private let engine: GameEngine
    private let difficulty: Difficulty
    private let records: Records
    private let settings: Settings
    private var hasRecordedEnd = false
    /// Guards against the AI loop being started twice.
    private var isRunningAI = false

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
        /// Two face-down cards shuffling before one is chosen.
        case rolling(playerID: String)
        /// Revealed and awaiting the verdict beat.
        case revealed(card: Card, playable: Bool, playerID: String)
    }

    /// A card is halfway played and needs the player to resolve its choices.
    struct PendingChoice: Identifiable, Equatable {
        let id = UUID()
        var card: Card
        /// Every legal way this card can be played right now.
        var options: [Declaration]
        /// True when the card came from the well rather than the hand.
        var isFromWell: Bool
    }

    struct Rejection: Identifiable, Equatable {
        let id = UUID()
        var cardID: Int
        var message: String
    }

    // MARK: - Init

    init(
        difficulty: Difficulty,
        opponentCount: Int,
        handSize: Int,
        playerName: String,
        seed: UInt32? = nil,
        records: Records = .shared,
        settings: Settings = .shared
    ) throws {
        self.difficulty = difficulty
        self.records = records
        self.settings = settings

        var seats: [(id: String, name: String, kind: PlayerState.PlayerKind)] = [
            (humanID, playerName, .human),
        ]
        let names = Self.opponentNames(for: difficulty)
        for index in 0..<opponentCount {
            seats.append(("ai\(index)", names[index % names.count], .ai(difficulty)))
        }

        // The human sits at seat 0; the dealer is the last seat so play opens on
        // the human — a game should never begin by making you watch.
        let dealerIndex = seats.count - 1
        self.engine = try GameEngine(
            seats: seats,
            dealerIndex: dealerIndex,
            handSize: handSize,
            seed: seed
        )
        self.state = engine.state
    }

    /// Opponent names carry the difficulty's character — it's a cheap way to set
    /// expectations before the first card is played.
    private static func opponentNames(for difficulty: Difficulty) -> [String] {
        switch difficulty {
        case .casual: return ["Pip", "Dot", "Bram", "Sunny", "Nell"]
        case .sharp: return ["Vale", "Corbin", "Ida", "Rook", "Marlow"]
        case .ruthless: return ["Mordant", "Sable", "Vex", "Grieve", "Thorne"]
        }
    }

    // MARK: - Derived view state

    var human: PlayerState { state.player(id: humanID) ?? state.players[0] }
    var opponents: [PlayerState] { state.players.filter { $0.id != humanID } }
    var isHumanTurn: Bool { state.currentPlayer.id == humanID && !state.isOver }
    var options: TurnOptions { engine.currentPlayerOptions }

    /// Cards in the human's hand that are legal against the *current* board. The
    /// table shades everything else, so the player never has to compute legality.
    ///
    /// Deliberately not gated on whose turn it is: greying out the whole hand
    /// while an opponent thinks tells the player nothing and actively misleads
    /// them. Legality is information; whether they may *act* on it is separate,
    /// and handled by `isInteractive` on the fan.
    var playableCardIDs: Set<Int> {
        guard wellReveal == .idle, pendingChoice == nil, !state.isOver else { return [] }
        return Set(human.hand.filter { Rules.isPlayable($0, in: state) }.map(\.id))
    }

    var snackooRanks: [Rank] { Rules.snackooRanksInHand(for: human) }
    var canSnackooPoison: Bool { Rules.canSnackooPoison(human) }

    /// The value a card would contribute if played — shown on the card itself, so
    /// mental arithmetic is never required.
    func projectedTally(for card: Card, declaration: Declaration) -> Int? {
        guard case .success(let effect) = Rules.resolve(card: card, declaration: declaration, in: state) else {
            return nil
        }
        return effect.newTally
    }

    // MARK: - Opening

    func begin() async {
        SoundEngine.shared.warmUp()
        // Let the deal animation play out before anyone can act.
        SoundEngine.shared.play(.shuffle, volume: 0.8)
        try? await Task.sleep(for: .milliseconds(Int(Double(human.hand.count) * Motion.dealStagger * 1000) + 620))
        isDealing = false
        Haptics.shared.play(.turnStart)
        await advanceIfAI()
    }

    // MARK: - Player actions

    /// The player tapped a card. Either plays it immediately, or asks for the
    /// declaration it needs first.
    func tapCard(_ card: Card) {
        guard isHumanTurn, !isDealing, wellReveal == .idle, pendingChoice == nil else { return }

        let declarations = Rules.legalDeclarations(for: card, in: state)
        guard !declarations.isEmpty else {
            reject(card)
            return
        }

        // One legal way to play it: no need to ask.
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
        let message = Rules.blockingReason(for: card, in: state)?.explanation
            ?? "That card can't be played right now."
        withAnimation(Motion.panel) {
            rejection = Rejection(cardID: card.id, message: message)
        }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(Motion.panel) { if rejection?.cardID == card.id { rejection = nil } }
        }
    }

    func declareSnackoo(_ kind: GameEvent.SnackooKind) {
        guard !state.isOver else { return }
        Task {
            do {
                let events = try engine.declareSnackoo(by: humanID, kind: kind)
                Haptics.shared.play(.snackoo)
                SoundEngine.shared.play(.snackoo)
                announce(
                    headline: "Snackoo!",
                    detail: snackooDetail(kind),
                    tone: .good
                )
                await absorb(events)
            } catch {
                Haptics.shared.play(.rejected)
            }
        }
    }

    private func snackooDetail(_ kind: GameEvent.SnackooKind) -> String {
        switch kind {
        case .threeOfAKind(let rank): return "Three \(rank.displayName)s away, three fresh cards in."
        case .threeQueens: return "The poison pile is clear."
        }
    }

    /// The player chose the well over a skip.
    func useWell() {
        guard isHumanTurn, options.canUseWell else { return }
        Task { await runWell(for: humanID) }
    }

    func skipTurn() {
        guard isHumanTurn, options.canSkip else { return }
        Task {
            do {
                let events = try engine.skip(by: humanID)
                Haptics.shared.play(.cardLand)
                announce(
                    headline: "Skipped",
                    detail: "You owe two plays on your next turn.",
                    tone: .neutral
                )
                await absorb(events)
                await advanceIfAI()
            } catch { Haptics.shared.play(.rejected) }
        }
    }

    func concede() {
        Task {
            guard let events = try? engine.concedeStranded(by: humanID) else { return }
            await absorb(events)
            await advanceIfAI()
        }
    }

    // MARK: - Playing a card

    private func commitPlay(card: Card, declaration: Declaration, fromWell: Bool) async {
        let events: [GameEvent]
        do {
            events = fromWell
                ? try engine.resolveWell(by: humanID, declaration: declaration)
                : try engine.play(cardID: card.id, by: humanID, declaration: declaration)
        } catch {
            reject(card)
            return
        }

        // Card flight first, then the consequences.
        Haptics.shared.play(.cardFlick)
        SoundEngine.shared.play(.cardFlick)
        withAnimation(Motion.cardFlight) { cardInFlight = card }
        try? await Task.sleep(for: .milliseconds(150))
        cardInFlight = nil

        await absorb(events)
        await advanceIfAI()
    }

    // MARK: - The well

    private func runWell(for playerID: String) async {
        withAnimation(Motion.drama) { wellReveal = .rolling(playerID: playerID) }
        Haptics.shared.play(.wellReveal)
        SoundEngine.shared.play(.wellRoll)
        try? await Task.sleep(for: .milliseconds(950))

        let events: [GameEvent]
        do {
            events = try engine.drawFromWell(by: playerID)
        } catch {
            withAnimation(Motion.drama) { wellReveal = .idle }
            return
        }

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
        // Hold on the verdict so it registers as a moment.
        try? await Task.sleep(for: .milliseconds(playable ? 1_250 : 1_900))
        withAnimation(Motion.drama) { wellReveal = .idle }

        // Absorb *after* the reveal, since an unplayable card eliminates here.
        await absorb(events)

        // A playable well card still needs its declaration.
        if playable, let pending = state.pendingWell, pending.playerID == playerID {
            if playerID == humanID {
                let declarations = Rules.legalDeclarations(for: pending.card, in: state)
                if declarations.count == 1 {
                    await commitPlay(card: pending.card, declaration: declarations[0], fromWell: true)
                } else {
                    withAnimation(Motion.panel) {
                        pendingChoice = PendingChoice(card: pending.card, options: declarations, isFromWell: true)
                    }
                }
                return
            }
        }
        await advanceIfAI()
    }

    // MARK: - Absorbing engine events

    /// Walk an event timeline, spacing the dramatic beats and firing feedback.
    private func absorb(_ events: [GameEvent]) async {
        for event in events {
            switch event {
            case .tallyChanged(let from, let to):
                let delta = to - from
                let pressure = to > 0 ? min(1, Double(to) / 99.0) : 0
                withAnimation(Motion.tallyTick) {
                    state = engine.state
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
                if owner == humanID {
                    Haptics.shared.play(.poison)
                    announce(
                        headline: "Queen exiled",
                        detail: "Your hand limit drops to \(cap).",
                        tone: .poison
                    )
                    try? await Task.sleep(for: .milliseconds(400))
                }

            case .snackoo(let by, let kind):
                if by != humanID {
                    SoundEngine.shared.play(.snackoo, volume: 0.7)
                    announce(headline: "\(name(of: by)): Snackoo!", detail: snackooDetail(kind), tone: .neutral)
                    try? await Task.sleep(for: .milliseconds(500))
                }

            case .drawPileReshuffled:
                SoundEngine.shared.play(.shuffle, volume: 0.6)
                announce(headline: "Reshuffled", detail: "The discards are back in play.", tone: .neutral)

            case .cardPlayed(let card, let by, _) where by != humanID:
                // The opponent's card lands here so it's visible before the tally
                // moves — the eye should follow the card, then the number.
                SoundEngine.shared.play(.cardLand, volume: 0.8)
                withAnimation(Motion.cardFlight) {
                    cardInFlight = card
                    state = engine.state
                }
                try? await Task.sleep(for: .milliseconds(180))
                cardInFlight = nil

            case .playerEliminated(let id, let reason, _):
                if id == humanID {
                    Haptics.shared.play(.eliminated)
                    SoundEngine.shared.play(.eliminated)
                    announce(headline: "You're out", detail: reason.explanation, tone: .bad)
                } else {
                    SoundEngine.shared.play(.eliminated, volume: 0.7)
                    announce(
                        headline: "\(name(of: id)) is out",
                        detail: reason.explanation,
                        tone: .good
                    )
                }
                withAnimation(Motion.drama) { state = engine.state }
                try? await Task.sleep(for: .milliseconds(1_100))

            case .gameWon(let winner):
                withAnimation(Motion.drama) { state = engine.state }
                finish(winnerID: winner)
                return

            case .turnAdvanced(let to, let owesTwo):
                withAnimation(Motion.handReflow) { state = engine.state }
                if to == humanID && !state.isOver {
                    Haptics.shared.play(.turnStart)
                    if owesTwo {
                        announce(
                            headline: "You owe two plays",
                            detail: "Both must be legal. You can't skip again.",
                            tone: .danger
                        )
                    }
                }

            case .drewCards, .wellPlayed, .wellBonusDrawn, .turnSkipped,
                 .extraPlayOwed, .dealt, .forcedNegativeConsumed, .wellRevealed,
                 .cardPlayed:
                withAnimation(Motion.handReflow) { state = engine.state }
            }
        }

        state = engine.state
        records.record(events: events, humanID: humanID, state: state)
        surfaceAchievementToast()
    }

    // MARK: - AI turns

    /// Drive every consecutive AI turn until it's the human's move again.
    private func advanceIfAI() async {
        guard !isRunningAI else { return }
        isRunningAI = true
        defer { isRunningAI = false }

        var safety = 0
        while !state.isOver && state.currentPlayer.id != humanID && safety < 400 {
            safety += 1
            let current = state.currentPlayer
            let ai = AIPlayer(difficulty: current.kind.difficulty ?? difficulty)

            thinkingPlayerID = current.id
            let delay = Double.random(in: ai.thinkingDelay)
            try? await Task.sleep(for: .seconds(delay))
            thinkingPlayerID = nil

            guard let move = ai.nextMove(for: current.id, engine: engine) else { break }

            switch move.kind {
            case .play(let cardID, let declaration):
                if state.pendingWell?.card.id == cardID {
                    guard let events = try? engine.resolveWell(by: current.id, declaration: declaration) else { break }
                    await absorb(events)
                } else {
                    guard let events = try? engine.play(cardID: cardID, by: current.id, declaration: declaration) else {
                        break
                    }
                    await absorb(events)
                }
            case .useWell:
                await runWell(for: current.id)
            case .skip:
                guard let events = try? engine.skip(by: current.id) else { break }
                announce(headline: "\(current.name) skips", detail: move.rationale, tone: .neutral)
                await absorb(events)
            case .snackoo(let kind):
                guard let events = try? engine.declareSnackoo(by: current.id, kind: kind) else { break }
                await absorb(events)
            case .concede:
                guard let events = try? engine.concedeStranded(by: current.id) else { break }
                await absorb(events)
            }
        }

        // A human turn that begins already stranded needs surfacing, not silence.
        if isHumanTurn, options.isStranded {
            announce(
                headline: "Nowhere to go",
                detail: "No legal card, no well, and a play owed.",
                tone: .bad
            )
        }
    }

    // MARK: - Endgame

    private func finish(winnerID: String) {
        guard !hasRecordedEnd else { return }
        hasRecordedEnd = true

        let won = winnerID == humanID
        if won {
            Haptics.shared.play(.victory)
            SoundEngine.shared.play(.victory)
            outcome = .won
        } else {
            outcome = .lost(
                position: Standings.position(
                    eliminationRank: human.eliminationRank,
                    of: state.players.count
                )
            )
        }
        records.recordGameEnd(won: won, state: state, humanID: humanID, difficulty: difficulty)
        surfaceAchievementToast()
    }

    // MARK: - Helpers

    private func name(of playerID: String) -> String {
        playerID == humanID ? "You" : (state.player(id: playerID)?.name ?? "Someone")
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
