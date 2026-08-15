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
    /// Set the player is assembling by long press. Nil almost always.
    @Published var pendingSet: PendingSet?
    /// The once-a-game moment when queens turn poisonous.
    @Published var queenPoisoning: QueenPoisoning?
    /// True for the length of a well shuffle, so the cards can animate and a
    /// second shake can't interrupt the first.
    @Published private(set) var isShufflingWell = false
    /// A Snackoo in progress, shown to the whole table.
    @Published var snackooMoment: SnackooMoment?
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
    /// Guards the automatic resolution of a stranded seat against re-entry —
    /// it runs from several places, each of which can fire while it's waiting.
    private var isResolvingStranded = false
    private var hasAppliedStrandedUITestPosition = false
    private var hasAppliedPressureUITestPosition = false
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
        /// - Parameter slots: how many cards are still down there. A spent well
        ///   has one, and drawing from it must not pretend otherwise.
        case rolling(playerID: String, slots: Int)
        case revealed(card: Card, playable: Bool, playerID: String)
        /// Unplayable, but the third of its rank — the player is offered the
        /// Snackoo before being told they're out.
        case rescue(card: Card, rank: Rank, playerID: String)
        /// It played. You went to the well expecting to lose and didn't, and
        /// you're two cards richer — the only unambiguously good thing that
        /// happens in a game of 99, so it gets its own beat.
        case survived(card: Card, playerID: String)
        /// The other well card, turned over after an unplayable one has ended
        /// somebody's game. Shown before the loss is announced.
        case whatYouMissed(card: Card, playerID: String)
        /// The hand you were holding when it ended, held on screen for a beat.
        ///
        /// A loss you can't see is a loss you don't believe. The engine sweeps
        /// an eliminated player's cards back into the deck as part of the
        /// elimination, so by the time anything rendered the hand was already
        /// empty and the game simply announced the result.
        case nothingPlayed(cards: [Card], playerID: String)
    }

    struct PendingChoice: Identifiable, Equatable {
        let id = UUID()
        var card: Card
        var options: [Declaration]
        var isFromWell: Bool
    }

    /// A run of same-ranked cards the player is assembling. Reached only by a
    /// long press, so the ordinary tap-to-play path is untouched — hoarding nines
    /// for the endgame shouldn't mean dismissing a prompt every turn.
    struct PendingSet: Identifiable, Equatable {
        let id = UUID()
        var rank: Rank
        /// Every card of this rank in hand, in the order they're held.
        var available: [Card]
        /// Chosen cards, in the order they'll be played.
        var selected: [Card]

        var canPlay: Bool { selected.count > 1 }
    }

    struct QueenPoisoning: Identifiable, Equatable {
        let id = UUID()
        var card: Card
        var triggerName: String
        var itWasYou: Bool
        var yourExiledCount: Int
        var yourNewCap: Int?
    }

    struct SnackooMoment: Identifiable, Equatable {
        let id = UUID()
        var headline: String
        var detail: String
        /// The three that went. Shown to everyone — a Snackoo is a public
        /// declaration, and the cards are the whole claim.
        var cards: [Card]
        var isYours: Bool
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
        cardsDealt: Int,
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
            cardsDealt: cardsDealt,
            dealerID: dealerID,
            seed: seed,
            recordedPlayerID: "human"
        )
    }

    /// Pass-and-play: several humans sharing this device.
    static func passAndPlay(
        playerNames: [String],
        cardsDealt: Int,
        dealerID: String? = nil,
        seed: UInt32? = nil,
        autoAssignWells: Bool = false
    ) -> GameViewModel {
        let participants = playerNames.enumerated().map { index, name in
            MatchParticipant(
                id: "p\(index)",
                name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Player \(index + 1)" : name,
                kind: .localHuman
            )
        }
        let model = GameViewModel(
            participants: participants,
            mode: .passAndPlay,
            difficulty: .sharp,
            cardsDealt: cardsDealt,
            dealerID: dealerID,
            seed: seed,
            recordedPlayerID: nil
        )
        model.coordinator.autoAssignLocalWells = autoAssignWells
        return model
    }

    /// Online: humans on other devices, over Game Center.
    ///
    /// The transport is the only difference from the other two modes — the
    /// rules, the table, and the redaction boundary are identical, because they
    /// were written against `MatchTransport` rather than against any one of them.
    static func online(transport: GameKitTransport) -> GameViewModel {
        GameViewModel(
            transport: transport,
            mode: .online,
            difficulty: .sharp,
            recordedPlayerID: transport.localPlayerID
        )
    }

    /// Shared designated init: everything above builds a transport and calls this.
    private init(
        transport: MatchTransport,
        mode: MatchCoordinator.MatchMode,
        difficulty: Difficulty,
        recordedPlayerID: String?,
        records: Records = .shared,
        settings: Settings = .shared
    ) {
        self.mode = mode
        self.difficulty = difficulty
        self.records = records
        self.settings = settings
        self.recordedPlayerID = recordedPlayerID
        self.coordinator = MatchCoordinator(transport: transport, mode: mode)
        self.coordinator.autoDriveAI = false
    }

    private convenience init(
        participants: [MatchParticipant],
        mode: MatchCoordinator.MatchMode,
        difficulty: Difficulty,
        cardsDealt: Int,
        dealerID: String?,
        seed: UInt32?,
        recordedPlayerID: String?,
        records: Records = .shared,
        settings: Settings = .shared
    ) {
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
            cardsDealt: cardsDealt
        )
        // Pacing lives in the view model, not the coordinator — otherwise two
        // systems fight over when an opponent's move is allowed to appear.
        self.init(
            transport: transport,
            mode: mode,
            difficulty: difficulty,
            recordedPlayerID: recordedPlayerID,
            records: records,
            settings: settings
        )
    }

    /// Validate a configuration without starting it, so an impossible table is
    /// caught on the setup screen rather than on a broken game screen.
    static func canDeal(playerCount: Int, cardsDealt: Int) -> Bool {
        guard (2...6).contains(playerCount) else { return false }
        return cardsDealt >= Rules.minCardsDealt && cardsDealt <= Rules.maxCardsDealt(forPlayerCount: playerCount)
    }

    private static func opponentNames(for difficulty: Difficulty) -> [String] {
        switch difficulty {
        case .sharp: return ["Vale", "Corbin", "Ida", "Rook", "Marlow"]
        case .ruthless: return ["Mordant", "Sable", "Vex", "Grieve", "Thorne"]
        case .merciless: return ["Calder", "Wrenn", "Halloway", "Marsh", "Crane"]
        case .cutthroat: return ["Quill", "Ash", "Verity", "Slate", "Mercer"]
        }
    }

    // MARK: - Derived view state

    var participants: [MatchParticipant] { coordinator.participants }

    /// The seat currently being shown. In pass-and-play this is whoever last
    /// confirmed they're holding the device — never simply whoever's turn it is.
    var viewingPlayerID: String? { coordinator.viewingPlayerID }

    var isYourTurn: Bool {
        guard let view else { return false }
        // Not while *anybody* still owes a well.
        //
        // This used to check only whether **you** were still choosing, which is
        // fine on one device — the wells are buried in sequence and the table
        // doesn't appear until they're done. Online they're buried in parallel,
        // so the moment you finished yours the app showed you a live table,
        // announced "Your move", and then refused every card you tapped: the
        // rules correctly report nothing as playable while a match is still
        // being set up, and the interface hadn't been told.
        return view.isYourTurn
            && !awaitingHandoff
            && !isChoosingWell
            && !isWaitingForOthersToBuryWells
    }

    /// Somebody else still owes a well, so the game hasn't begun.
    var isWaitingForOthersToBuryWells: Bool {
        guard let view, let chooser = view.wellChooserID else { return false }
        return chooser != view.youID
    }

    /// Who the table is waiting on, for a screen that would otherwise just sit
    /// there looking playable.
    var wellChooserName: String? {
        guard let view, let chooser = view.wellChooserID, chooser != view.youID else { return nil }
        return participants.first { $0.id == chooser }?.name
            ?? view.opponents.first { $0.id == chooser }?.name
    }

    /// Several people round one phone, so the builder names whose deal it is.
    var isSharedDevice: Bool { mode == .passAndPlay }

    /// True while this device should be showing the well builder rather than the
    /// table. Gated on the hand-off so a shared device doesn't reveal the next
    /// player's deal before they're holding it.
    var isChoosingWell: Bool {
        guard let view else { return false }
        return view.youAreChoosingYourWell && !awaitingHandoff
    }

    /// Shuffle the two face-down well cards before picking one.
    ///
    /// Only while the "pick one" prompt is up — deliberately *not* during the
    /// opening bury, where a shake would reorder cards the player is in the
    /// middle of choosing between and undo the selection under their hand.
    func shuffleWell() {
        guard case .choosing(let playerID, let slots) = wellReveal, slots > 1 else { return }
        guard playerID == viewingPlayerID else { return }
        guard !isShufflingWell else { return }

        isShufflingWell = true
        Haptics.shared.play(.cardLift)
        SoundEngine.shared.play(.shuffle, volume: 0.8)

        Task {
            await submit(.shuffleWell, by: playerID) {}
            // Long enough for the four-beat choreography to land. A shorter
            // window let a vigorous shake cut its own animation in half.
            try? await Task.sleep(for: .milliseconds(640))
            isShufflingWell = false
        }
    }

    /// Bank two positions and let play begin.
    func chooseWell(slots: [Int]) {
        guard let actor = viewingPlayerID else { return }
        Task {
            await submit(.chooseWell(slots: slots), by: actor) {
                Haptics.shared.play(.cardFlick)
                SoundEngine.shared.play(.cardFlick)
            }
        }
    }

    var opponents: [OpponentView] { view?.opponents ?? [] }

    /// Who plays after whoever is acting now — "you" when that's you, because
    /// "Amir is next" reads oddly on your own device.
    var nextPlayerName: String? {
        guard let view, let id = view.nextPlayerID else { return nil }
        if id == view.youID { return "You" }
        return participants.first { $0.id == id }?.name
    }
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
        guard let current = coordinator.activeSeatID ?? coordinator.currentPlayerID,
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

        // Before the first hand-off, not after: with auto-banked wells on, the
        // app owes the table two decisions per seat, and prompting "pass to Ken"
        // for a choice nobody is being asked to make is worse than the passing
        // the option exists to avoid.
        await driveAITurns()

        if mode == .passAndPlay {
            // The first player must confirm they're holding the device too,
            // otherwise the deal is face-up in front of everyone.
            refreshHandoff()
        } else {
            Haptics.shared.play(.turnStart)
        }
    }

    // MARK: - Player actions

    func tapCard(_ card: Card) {
        guard isYourTurn, !isDealing, wellReveal == .idle, pendingChoice == nil,
              pendingSet == nil, let view else { return }

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

    // MARK: - Sets

    /// Long press. Opens the set builder when the pressed card has company of
    /// the same rank; otherwise it's a no-op, because a long press that does
    /// nothing visible is better than one that scolds you.
    func longPressCard(_ card: Card) {
        guard isYourTurn, !isDealing, wellReveal == .idle,
              pendingChoice == nil, pendingSet == nil, let view else { return }

        let matching = view.yourHand.filter { $0.rank == card.rank }
        guard matching.count > 1 else { return }

        let context = view.rulesContext()
        guard card.rank != .queen else {
            reject(card, message: "Queens can't be run together — each one has to name what it is.")
            return
        }
        // No legal run of this rank at all — say *why*, in the engine's words.
        // This used to assert the tally was the problem, which told a player
        // holding two off-suit sixes under a lock that they'd bust.
        guard Rules.playableSetRanks(for: context.players[context.currentPlayerIndex], in: context)
            .contains(card.rank) else {
            let pair = Array(matching.prefix(2))
            reject(card, message: Rules.blockingReasonForSet(pair, in: context)?.explanation
                ?? "You can't run those together right now.")
            return
        }

        Haptics.shared.play(.cardLift)
        SoundEngine.shared.play(.cardLift, volume: 0.6)
        withAnimation(Motion.panel) {
            pendingSet = PendingSet(
                rank: card.rank,
                available: matching,
                selected: openingRun(pressed: card, from: matching, in: context)
            )
        }
    }

    /// What the builder opens with: **every copy you hold**, or as many of them
    /// as are actually legal.
    ///
    /// It used to open on a pair, which read as a limit rather than a starting
    /// point — a player holding three of a rank reported that the game "only let
    /// them play two". Opening on the whole run says what's possible; dropping
    /// one is a tap.
    ///
    /// Trimmed to the longest legal prefix so it can never open in a state where
    /// Play is disabled, which would look equally broken.
    private func openingRun(
        pressed: Card, from matching: [Card], in context: GameState
    ) -> [Card] {
        // The pressed card leads; the rest follow in hand order.
        var ordered = [pressed]
        ordered += matching.filter { $0.id != pressed.id }

        var best: [Card] = []
        for count in 2...ordered.count {
            let candidate = Array(ordered.prefix(count))
            if !Rules.legalDeclarations(forSet: candidate, in: context).isEmpty {
                best = candidate
            } else {
                // Runs only get more expensive, so the first refusal is the wall.
                break
            }
        }
        return best.isEmpty ? Array(ordered.prefix(2)) : best
    }

    /// Add or remove a card from the run. The pressed card can be removed like
    /// any other — what matters is the count and the rank, not which copies.
    func toggleSetCard(_ card: Card) {
        guard var pending = pendingSet else { return }
        if let index = pending.selected.firstIndex(where: { $0.id == card.id }) {
            pending.selected.remove(at: index)
        } else {
            pending.selected.append(card)
        }
        Haptics.shared.play(.select)
        withAnimation(Motion.panel) { pendingSet = pending }
    }

    /// Declarations that are legal for the run as currently selected. A run of
    /// plain cards has exactly one, and the sheet plays it without asking.
    var setDeclarations: [Declaration] {
        guard let pending = pendingSet, pending.canPlay, let view else { return [] }
        return Rules.legalDeclarations(forSet: pending.selected, in: view.rulesContext())
    }

    /// The tally the current selection would produce under a given declaration,
    /// or nil if it isn't legal. Drives the live preview.
    func projectedSetTally(_ declaration: Declaration) -> Int? {
        guard let pending = pendingSet, pending.canPlay, let view else { return nil }
        switch Rules.resolveSet(cards: pending.selected, declaration: declaration, in: view.rulesContext()) {
        case .success(let effect): return effect.newTally
        case .failure: return nil
        }
    }

    func dismissQueenPoisoning() {
        Haptics.shared.play(.select)
        withAnimation(Motion.drama) { queenPoisoning = nil }
    }

    /// How many of *your* queens this poisoning takes, and the cap you're left
    /// with. Peeks ahead at the .queenPoisoned events that follow in the same
    /// timeline.
    private func remainingQueenExiles(
        in events: [GameEvent], from index: Int
    ) -> (count: Int, newCap: Int?) {
        var count = 0
        var cap: Int?
        for event in events[(index + 1)...] {
            guard case .queenPoisoned(_, let owner, let newCap) = event else { continue }
            if owner == viewingPlayerID {
                count += 1
                cap = newCap
            }
        }
        return (count, cap)
    }

    /// Hold until the player dismisses, with a backstop so an unattended device
    /// (or an AI-only table) doesn't sit here forever.
    private func waitForQueenMoment() async {
        let deadline = Date().addingTimeInterval(6)
        while queenPoisoning != nil && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
        }
        if queenPoisoning != nil {
            withAnimation(Motion.drama) { queenPoisoning = nil }
        }
    }

    func cancelSet() {
        Haptics.shared.play(.select)
        withAnimation(Motion.panel) { pendingSet = nil }
    }

    func playSet(declaration: Declaration) {
        guard let pending = pendingSet, pending.canPlay else { return }
        let cards = pending.selected
        withAnimation(Motion.panel) { pendingSet = nil }
        Task { await commitSet(cards: cards, declaration: declaration) }
    }

    private func commitSet(cards: [Card], declaration: Declaration) async {
        guard let actor = viewingPlayerID, let last = cards.last else { return }

        Haptics.shared.play(.cardFlick)
        SoundEngine.shared.play(.cardFlick)
        withAnimation(Motion.cardFlight) { cardInFlight = last }

        let before = coordinator.actionLog.count
        await coordinator.submit(
            .playSet(cardIDs: cards.map(\.id), declaration: declaration),
            by: actor
        )

        try? await Task.sleep(for: .milliseconds(150))
        cardInFlight = nil

        if let error = coordinator.lastError {
            coordinator.lastError = nil
            announce(headline: "Not legal", detail: error, tone: .bad)
            return
        }
        guard coordinator.actionLog.count > before else { return }

        announce(
            headline: "\(cards.count) \(cards[0].rank.plural)",
            detail: setDetail(for: cards),
            tone: .neutral
        )
        await absorb(coordinator.consumeEvents())
        await driveAITurns()
    }

    /// The one thing about a run that isn't obvious from watching it land.
    private func setDetail(for cards: [Card]) -> String {
        switch cards[0].rank {
        case .four:
            return cards.count % 2 == 0
                ? "Reversed \(cards.count) times — play carries on the way it was."
                : "Reversed \(cards.count) times — the direction flips."
        case .nine:
            return "All in one go."
        default:
            return "Played as a run."
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

    private func reject(_ card: Card, message customMessage: String? = nil) {
        Haptics.shared.play(.rejected)
        SoundEngine.shared.play(.reject, volume: 0.7)
        let message = customMessage
            ?? view.flatMap { Rules.blockingReason(for: card, in: $0.rulesContext())?.explanation }
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
            // Nothing to celebrate here: the event comes straight back through
            // the log and the timeline shows it to everyone, this player
            // included. Announcing locally as well played the sound twice and
            // put a banner behind the confetti.
            await submit(.snackoo(kind: PlayerAction.SnackooKind(kind)), by: actor) {}
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

    /// Take the reprieve on an unplayable well card that completes a trio.
    func takeWellSnackoo() {
        guard case .rescue(_, _, let actor) = wellReveal else { return }
        withAnimation(Motion.drama) { wellReveal = .idle }
        Task {
            await submit(.snackooWellCard, by: actor) {
                Haptics.shared.play(.snackoo)
                SoundEngine.shared.play(.snackoo)
                self.announce(
                    headline: "Snackoo!",
                    detail: "Out of the well by the skin of your teeth. Three fresh cards — and you still owe a play.",
                    tone: .good
                )
            }
        }
    }

    /// Decline it and accept elimination.
    func declineWellSnackoo() {
        guard case .rescue(_, _, let actor) = wellReveal else { return }
        withAnimation(Motion.drama) { wellReveal = .idle }
        Task { await submit(.concedeWellCard, by: actor) {} }
    }

    /// The rank the engine is offering as a rescue, if any.
    private func coordinatorPendingWellRank(for playerID: String) -> Rank? {
        guard let pending = coordinator.view?.pendingWell, pending.playerID == playerID else {
            return nil
        }
        return pending.snackooRank
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

    /// The stranded seat's own resolution, awaited rather than fired off — the
    /// caller is pacing it and needs to know when the table has caught up.
    private func concedeStranded() async {
        guard let actor = viewingPlayerID else { return }
        await submit(.concede, by: actor) {}
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
        withAnimation(Motion.drama) {
            wellReveal = .rolling(playerID: playerID, slots: view?.yourWellCount ?? 1)
        }
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

        // Unplayable, but the third of its rank: hold on the reveal and offer the
        // way out rather than announcing a loss the player can still avoid.
        let rescueRank = view?.pendingWell?.snackooRank
            ?? coordinatorPendingWellRank(for: playerID)

        withAnimation(Motion.drama) {
            wellReveal = .revealed(card: card, playable: playable, playerID: playerID)
        }
        if playable {
            Haptics.shared.play(.wellSurvive)
            SoundEngine.shared.play(.wellSurvive)
        } else if rescueRank != nil {
            Haptics.shared.play(.snackoo)
            SoundEngine.shared.play(.snackoo, volume: 0.8)
        } else {
            Haptics.shared.play(.eliminated)
            SoundEngine.shared.play(.eliminated)
        }
        try? await Task.sleep(for: .milliseconds(playable ? 1_100 : 1_500))

        await absorb(events)

        if playable {
            // Hold on the win before handing the table back.
            withAnimation(Motion.drama) {
                wellReveal = .survived(card: card, playerID: playerID)
            }
            Haptics.shared.play(.snackoo)
            SoundEngine.shared.play(.wellSurvive, volume: 0.9)
            try? await Task.sleep(for: .milliseconds(1_700))
            withAnimation(Motion.drama) { wellReveal = .idle }

            // And then *play it*. A well card that survives is still a card
            // being played: it moves the tally and, if it's an Ace, an 8 or a
            // Queen, its owner still has to say what it is. An earlier version
            // of this celebration returned here, which left the card revealed,
            // uncommitted and unasked-about — the turn simply stopped.
            await resolvePendingWellCard(for: playerID)
            return
        }

        if let rank = rescueRank ?? view?.pendingWell?.snackooRank {
            withAnimation(Motion.drama) {
                wellReveal = .rescue(card: card, rank: rank, playerID: playerID)
            }
            return
        }
        withAnimation(Motion.drama) { wellReveal = .idle }
        await driveAITurns()
    }

    /// Play the well card that's face up, asking how if it needs an answer.
    ///
    /// Separated out because it is the *point* of turning a well card over, and
    /// it was previously buried at the end of a long function behind three
    /// early returns — one of which was later added in front of it.
    private func resolvePendingWellCard(for playerID: String) async {
        guard let pending = view?.pendingWell, pending.playerID == playerID, let view else {
            await driveAITurns()
            return
        }
        let declarations = Rules.legalDeclarations(for: pending.card, in: view.rulesContext())
        if declarations.count == 1 {
            await commitPlay(card: pending.card, declaration: declarations[0], fromWell: true)
        } else if declarations.isEmpty {
            // Shouldn't happen — it was judged playable a moment ago — but
            // stalling silently would be worse than saying so.
            announce(headline: "Stuck", detail: "That card can't be played after all.", tone: .bad)
            await driveAITurns()
        } else {
            withAnimation(Motion.panel) {
                pendingChoice = PendingChoice(
                    card: pending.card, options: declarations, isFromWell: true
                )
            }
        }
    }

    // MARK: - AI

    /// Pump AI seats one move at a time, pacing each so the table stays readable.
    private func driveAITurns() async {
        guard !isDrivingAI else { return }
        isDrivingAI = true
        defer { isDrivingAI = false }

        var safety = 0
        while coordinator.isAITurn || coordinator.isAutoWellTurn, !coordinator.isOver, safety < 400 {
            safety += 1

            // Auto-banked wells get a beat rather than a thinking delay — the
            // point of the option is to get past this, but a table that banks
            // four wells in one frame reads as a glitch rather than a deal.
            if coordinator.isAutoWellTurn {
                try? await Task.sleep(for: .milliseconds(220))
                guard await coordinator.stepAutoWell() else { break }
                await absorb(coordinator.consumeEvents())
                continue
            }

            let thinker = coordinator.currentPlayerID
            thinkingPlayerID = thinker
            try? await Task.sleep(for: .seconds(Double.random(in: coordinator.currentAIThinkingDelay)))
            thinkingPlayerID = nil

            guard coordinator.stepAI() != nil else { break }
            await absorb(coordinator.consumeEvents())
        }

        syncFromCoordinator()
        refreshHandoff()

        applyStrandedUITestPositionIfRequested()
        applyPressureUITestPositionIfRequested()
        await resolveStrandedSeatIfNeeded()
    }

    /// Drop the viewing player into a dead position, once, when the app was
    /// launched with `-uitest-stranded`. Inert in every other run.
    private func applyStrandedUITestPositionIfRequested() {
        // The body is DEBUG-only because the coordinator seam it calls is. Left
        // unguarded this compiles cleanly for every test run — which are all
        // Debug — and fails the Release archive, i.e. at exactly the moment
        // there's a build to ship.
        #if DEBUG
        guard UITestStranded.enabled, !hasAppliedStrandedUITestPosition else { return }
        guard let view, !view.youOweAWell, !isDealing, !coordinator.isOver else { return }
        hasAppliedStrandedUITestPosition = true
        // Sevens and Kings both bust from 99, so the hand is dead and the refill
        // can't rescue it either.
        let dead = Deck.standard().filter { $0.rank == .seven || $0.rank == .king }
        coordinator._forceStrandedForTesting(
            hand: Array(dead.prefix(2)), tally: Rules.ceiling
        )
        syncFromCoordinator()
        #endif
    }

    /// Raise the tally to a dangerous number, once, when launched with
    /// `-uitest-pressure`. Inert in every other run.
    private func applyPressureUITestPositionIfRequested() {
        #if DEBUG
        guard UITestPressure.enabled, !hasAppliedPressureUITestPosition else { return }
        guard let view, !view.youOweAWell, !isDealing, !coordinator.isOver, isYourTurn else { return }
        // Wait for a few real cards to be played first. Forcing the tally at the
        // deal produced a board reading 92 with an empty discard pile — which is
        // not a position this game can reach, and would have gone to the App
        // Store as a screenshot of something that cannot happen.
        guard view.discardPile.count >= 6 else { return }
        hasAppliedPressureUITestPosition = true
        // The player's own cards, kept — only the board is moved. A shot of a
        // hand nobody was dealt would be a different kind of lie.
        coordinator._forceHandForTesting(view.yourHand, tally: 92)
        syncFromCoordinator()
        #endif
    }

    /// End a turn that has no moves left in it, without asking.
    ///
    /// Being stranded means no legal card, no well, and a play owed — there is
    /// exactly one thing that can happen next. Offering "SDQ" there presented it
    /// as a decision and then waited, which is a button whose only function is
    /// to make you agree to something already true. Worse in pass-and-play,
    /// where the table sits waiting for a player to concede a game they have
    /// already lost.
    ///
    /// So it resolves itself, after a beat long enough to read the board and see
    /// why. The button remains in the pause menu, where conceding *is* a choice.
    private func resolveStrandedSeatIfNeeded() async {
        guard !isResolvingStranded else { return }
        guard isYourTurn, options.isStranded, !coordinator.isOver else { return }
        guard !isDealing, wellReveal == .idle, pendingChoice == nil,
              pendingSet == nil, snackooMoment == nil, !awaitingHandoff
        else { return }

        isResolvingStranded = true
        defer { isResolvingStranded = false }

        announce(
            headline: "Nowhere to go",
            detail: "No legal card, no well, and a play owed.",
            tone: .bad
        )
        Haptics.shared.play(.rejected)
        try? await Task.sleep(for: .milliseconds(2_200))

        guard isYourTurn, options.isStranded, !coordinator.isOver else { return }
        await concedeStranded()
    }

    // MARK: - Event choreography

    #if DEBUG
    /// Wait until the table has stopped moving on its own.
    ///
    /// A fixed sleep isn't enough: the AI turn loop started by `begin()` runs
    /// for as long as it runs, and under a loaded machine that is longer than
    /// any number you'd want to hardcode. A position forced while it's still
    /// going simply gets played over.
    /// The shared log, for tests that care that a decision was *recorded* and
    /// not just applied — anything missing from here breaks replay.
    var _actionLogForTesting: [SubmittedAction] { coordinator.actionLog }

    /// Strand the viewing player and let the view model notice, exactly as it
    /// would after a real play left them with nothing.
    func _forceStrandedForTesting(hand: [Card], tally: Int) {
        coordinator._forceStrandedForTesting(hand: hand, tally: tally)
        syncFromCoordinator()
        Task { await driveAITurns() }
    }

    func _settleForTesting(timeout: Duration = .seconds(20)) async {
        let deadline = ContinuousClock.now + timeout
        var stableTicks = 0
        var previous = ""
        while ContinuousClock.now < deadline {
            let snapshot = "\(view?.currentPlayerID ?? "")|\(view?.tally ?? -1)|\(coordinator.actionLog.count)"
            let quiet = snapshot == previous
                && thinkingPlayerID == nil
                && wellReveal == .idle
                && !isDealing
            stableTicks = quiet ? stableTicks + 1 : 0
            if stableTicks >= 4 { return }
            previous = snapshot
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    var _lastErrorForTesting: String? { coordinator.lastError }
    var _availableActionsForTesting: [PlayerAction] {
        guard let id = viewingPlayerID else { return [] }
        return coordinator.availableActions(for: id)
    }

    /// Put a known well and hand on the table, at a known tally.
    func _forceWellForTesting(_ well: [Card], hand: [Card], tally: Int) {
        coordinator._forceWellForTesting(well, hand: hand, tally: tally)
        syncFromCoordinator()
    }

    /// Drive the real well flow, celebration and all, and wait for it to settle.
    func _drawWellForTesting(slot: Int) async {
        guard let actor = viewingPlayerID else { return }
        await runWell(for: actor, slot: slot)
    }

    /// Put a known hand on the table. Reproducing a reported hand by shuffling
    /// for it is a waiting game; this states it.
    func _forceHandForTesting(_ hand: [Card], tally: Int) {
        coordinator._forceHandForTesting(hand, tally: tally)
        syncFromCoordinator()
    }

    /// Feed a timeline straight in. Reaching the once-per-game moments through
    /// real play means waiting for a particular card to come off the deck, which
    /// makes a test either slow, flaky, or both.
    func _absorbForTesting(_ events: [GameEvent]) async {
        await absorb(events)
    }
    #endif

    private func absorb(_ events: [GameEvent]) async {
        // Indexed because one case — queens turning poisonous — needs to read
        // the events that follow it to know what the moment costs this player.
        for (index, event) in events.enumerated() {
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

            case .queensBecamePoisonous(let card, let trigger):
                Haptics.shared.play(.poison)
                SoundEngine.shared.play(.poison)
                // The rest of this event's consequences — whose queens got
                // exiled and what that did to their caps — arrive as separate
                // .queenPoisoned events *after* this one. Read them ahead so the
                // overlay can state the cost in the same breath rather than
                // flashing a second banner behind it.
                let mine = remainingQueenExiles(in: events, from: index)
                withAnimation(Motion.drama) {
                    // Whatever banner was up belongs to the previous beat; left
                    // alone it sits behind this and reads through it.
                    announcement = nil
                    queenPoisoning = QueenPoisoning(
                        card: card,
                        triggerName: name(of: trigger),
                        itWasYou: trigger == viewingPlayerID,
                        yourExiledCount: mine.count,
                        yourNewCap: mine.newCap
                    )
                }
                await waitForQueenMoment()

            case .queenPoisoned(_, let owner, let cap):
                // Already stated by the overlay when it was this player's queen.
                if owner == viewingPlayerID, queenPoisoning == nil {
                    Haptics.shared.play(.poison)
                    announce(
                        headline: "Queen exiled",
                        detail: "Your hand limit drops to \(cap).",
                        tone: .poison
                    )
                    try? await Task.sleep(for: .milliseconds(400))
                }

            case .snackoo(let by, let kind, let cards):
                // Everyone's, not just yours. A Snackoo can happen out of turn,
                // to anyone, and it's the one move in 99 that's purely good —
                // the table should get to see it rather than read about it in a
                // banner that's already sliding away.
                let mine = by == viewingPlayerID
                SoundEngine.shared.play(.snackoo, volume: mine ? 1.0 : 0.8)
                Haptics.shared.play(.snackoo)
                withAnimation(Motion.drama) {
                    snackooMoment = SnackooMoment(
                        headline: mine ? "SNACKOO!" : "\(name(of: by)): Snackoo!",
                        detail: snackooDetail(kind),
                        cards: cards,
                        isYours: mine
                    )
                }
                // Long enough to actually read the three cards. Two seconds
                // was time to notice something had happened and not to see what.
                try? await Task.sleep(for: .milliseconds(3_400))
                withAnimation(Motion.drama) { snackooMoment = nil }

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

            // Somebody *else* is going to the well. This is the most dramatic
            // thing that happens in a round and it was invisible unless it was
            // happening to you: the overlay was only ever driven by the local
            // player's own draw, so from every other seat a player quietly
            // survived or quietly vanished.
            //
            // The whole table watches now, at the same pace the actor sees it.
            case .wellRevealed(let card, let by, let playable) where by != viewingPlayerID:
                withAnimation(Motion.drama) {
                    // Their well, so its size comes from the public count.
                    let left = view?.opponents.first { $0.id == by }?.wellCount ?? 1
                    wellReveal = .rolling(playerID: by, slots: left)
                }
                Haptics.shared.play(.wellReveal)
                SoundEngine.shared.play(.wellRoll, volume: 0.75)
                try? await Task.sleep(for: .milliseconds(850))

                withAnimation(Motion.drama) {
                    wellReveal = .revealed(card: card, playable: playable, playerID: by)
                }
                SoundEngine.shared.play(playable ? .wellSurvive : .eliminated, volume: 0.75)
                Haptics.shared.play(playable ? .wellSurvive : .eliminated)
                try? await Task.sleep(for: .milliseconds(1_300))

                if playable {
                    withAnimation(Motion.drama) {
                        wellReveal = .survived(card: card, playerID: by)
                    }
                    try? await Task.sleep(for: .milliseconds(1_200))
                }
                // An unplayable card is left on screen: the elimination event
                // follows immediately and says what it cost them.
                withAnimation(Motion.drama) { wellReveal = .idle }

            case .playerEliminated(let id, let reason, _, let unspentWell, let finalHand):
                // Turn the card they didn't pick face up first. At a table this
                // is automatic — you show the other one — and "what was the one
                // I didn't take?" is the first thing anybody asks. Skipping it
                // made the loss land as an announcement rather than a reveal.
                if case .unplayableWellCard = reason, let missed = unspentWell.first {
                    withAnimation(Motion.drama) {
                        wellReveal = .whatYouMissed(card: missed, playerID: id)
                    }
                    Haptics.shared.play(.cardLift)
                    SoundEngine.shared.play(.cardFlick, volume: 0.7)
                    try? await Task.sleep(for: .milliseconds(1_900))
                    withAnimation(Motion.drama) { wellReveal = .idle }
                }

                // The hand that couldn't answer, held up before the verdict —
                // for the player it happened to, who is owed the reason.
                if id == viewingPlayerID, !finalHand.isEmpty {
                    withAnimation(Motion.drama) {
                        wellReveal = .nothingPlayed(cards: finalHand, playerID: id)
                    }
                    Haptics.shared.play(.rejected)
                    try? await Task.sleep(for: .milliseconds(2_300))
                    withAnimation(Motion.drama) { wellReveal = .idle }
                }

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
