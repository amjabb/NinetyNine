//
//  GameEngine.swift
//  The referee. Owns every legal state transition in a game of 99.
//
//  Design contract:
//   * Every public action validates through `Rules` before mutating.
//   * Every action returns the ordered `GameEvent` timeline it produced.
//   * All randomness flows through the injected `RandomSource`, so a seeded
//     engine replays byte-identically.
//

import Foundation

enum GameError: Error, LocalizedError, Equatable {
    case gameOver
    case notYourTurn
    case cardNotInHand
    case illegal(IllegalReason)
    case wellEmpty
    case mustPlayFromHandFirst
    case noPendingWell
    case cannotSkipWhileRepayingDebt
    case snackooNotAvailable
    case invalidPlayerCount(Int)
    case invalidDeal(min: Int, max: Int)
    case notChoosingWells
    case wrongWellSize(expected: Int)

    var errorDescription: String? {
        switch self {
        case .gameOver: return "The game is already over."
        case .notYourTurn: return "It isn't your turn."
        case .cardNotInHand: return "That card isn't in your hand."
        case .illegal(let reason): return reason.explanation
        case .wellEmpty: return "Your well is dry."
        case .mustPlayFromHandFirst: return "You have a legal card — you must play it."
        case .noPendingWell: return "There's no revealed well card to resolve."
        case .cannotSkipWhileRepayingDebt: return "You owe a play — you can't skip again."
        case .snackooNotAvailable: return "You don't have a Snackoo available."
        case .invalidPlayerCount(let n): return "99 is for 2–6 players (got \(n))."
        case .notChoosingWells: return "Wells have already been chosen."
        case .wrongWellSize(let expected): return "Pick exactly \(expected) cards for your well."
        case .invalidDeal(let min, let max): return "The deal must be \(min)–\(max) cards."
        }
    }
}

final class GameEngine {
    private(set) var state: GameState
    private let random: RandomSource

    // MARK: - Setup

    /// - Parameters:
    ///   - seats: seating order, clockwise.
    ///   - dealerIndex: index into `seats`.
    ///   - cardsDealt: 5...`Rules.maxCardsDealt(forPlayerCount:)`.
    ///   - seed: pin for reproducible deals (tests, "replay seed").
    init(
        seats: [(id: String, name: String, kind: PlayerState.PlayerKind)],
        dealerIndex: Int,
        cardsDealt: Int,
        seed: UInt32? = nil
    ) throws {
        guard (2...6).contains(seats.count) else {
            throw GameError.invalidPlayerCount(seats.count)
        }
        let maxHand = Rules.maxCardsDealt(forPlayerCount: seats.count)
        guard cardsDealt >= Rules.minCardsDealt && cardsDealt <= maxHand else {
            throw GameError.invalidDeal(min: Rules.minCardsDealt, max: maxHand)
        }

        self.random = RandomSource(seed: seed)
        var deck = random.shuffled(Deck.standard())

        var players = seats.map {
            PlayerState(id: $0.id, name: $0.name, kind: $0.kind, handCap: Rules.sustainingHandCap)
        }

        // Deal clockwise from the dealer's left, one card at a time.
        let count = players.count
        let firstToReceive = (dealerIndex + 1) % count
        func takeTop() -> Card { deck.removeLast() }

        // Everything the dealer calls goes to the hand. The well comes *out* of
        // it — each player chooses which two to bank before play begins, so at
        // this point nobody has a well yet.
        for _ in 0..<cardsDealt {
            for offset in 0..<count {
                players[(firstToReceive + offset) % count].hand.append(takeTop())
            }
        }

        self.state = GameState(
            players: players,
            currentPlayerIndex: (dealerIndex + 1) % count,
            drawPile: deck,
            dealerID: seats[dealerIndex].id,
            cardsDealt: cardsDealt,
            // Same order as the deal: the dealer's left banks first.
            wellSelectionQueue: (0..<count).map { seats[(firstToReceive + $0) % count].id }
        )

        // Hands are dealt sorted for a calmer read; the engine never depends on
        // hand order, so this is purely presentational.
        for index in state.players.indices {
            state.players[index].hand = Self.sorted(state.players[index].hand)
        }
        state.turnStartedWithDebt = false
        state.playsRemainingThisTurn = 1
        note("Dealt \(cardsDealt) each — two of them go to your well.")
    }

    /// Rank-then-suit ordering, aces low. Keeps a hand readable at a glance.
    static func sorted(_ cards: [Card]) -> [Card] {
        let rankOrder = Rank.allCases.enumerated().reduce(into: [Rank: Int]()) { $0[$1.element] = $1.offset }
        let suitOrder = Suit.allCases.enumerated().reduce(into: [Suit: Int]()) { $0[$1.element] = $1.offset }
        return cards.sorted {
            let l = (rankOrder[$0.rank] ?? 0, suitOrder[$0.suit] ?? 0)
            let r = (rankOrder[$1.rank] ?? 0, suitOrder[$1.suit] ?? 0)
            return l < r
        }
    }

    private func note(_ line: String) { state.journal.append(line) }

    #if DEBUG
    /// Test seam for board positions that are impractical to reach by play — a
    /// player holding exactly three poisoned queens, say. Deliberately DEBUG-only
    /// and deliberately ugly to call, so it can't drift into production code.
    func _replaceStateForTesting(_ newState: GameState) {
        state = newState
    }
    #endif

    // MARK: - Playing a card from hand

    @discardableResult
    func play(cardID: Int, by playerID: String, declaration: Declaration) throws -> [GameEvent] {
        guard !state.isOver else { throw GameError.gameOver }
        guard !state.isChoosingWells else { throw GameError.notChoosingWells }
        guard state.currentPlayer.id == playerID else { throw GameError.notYourTurn }
        guard let seat = state.index(of: playerID),
              let handIndex = state.players[seat].hand.firstIndex(where: { $0.id == cardID })
        else { throw GameError.cardNotInHand }

        let card = state.players[seat].hand[handIndex]
        let effect: CardEffect
        switch Rules.resolve(card: card, declaration: declaration, in: state) {
        case .success(let resolved): effect = resolved
        case .failure(let reason): throw GameError.illegal(reason)
        }

        var events: [GameEvent] = []
        state.players[seat].hand.remove(at: handIndex)
        events += apply(effect: effect, card: card, playerID: playerID)
        events += refillHand(seat: seat)
        events += finishOnePlay(seat: seat)
        return events
    }

    /// Commit a resolved effect to the table. Shared by hand plays and well plays.
    private func apply(effect: CardEffect, card: Card, playerID: String) -> [GameEvent] {
        var events: [GameEvent] = []
        let previousTally = state.tally
        let name = state.player(id: playerID)?.name ?? playerID

        state.tally = effect.newTally
        state.discardPile.append(card)
        // Whether the *new* face-up card counts as an 8 — which is what decides
        // if the next player may take the lock over with an off-suit 8. A Queen
        // declared as an 8 counts, so she can be used to seize a lock and then
        // hand the same opportunity on.
        state.topPlayedAsEight = effect.effectiveRank == .eight
        events.append(.cardPlayed(card: card, by: playerID, effect: effect))

        if state.forcedNegativeNext {
            events.append(.forcedNegativeConsumed)
        }

        if previousTally != effect.newTally {
            events.append(.tallyChanged(from: previousTally, to: effect.newTally))
        }

        if effect.isNine {
            events.append(.nineSlammed(to: effect.newTally))
            note("\(name) slams the tally to 99 with the \(card.accessibleName).")
        } else {
            note("\(name) plays \(card.shortName) → \(effect.newTally).")
        }

        // A 4 is a no-op with two players left — reversing between two seats
        // doesn't change whose turn is next.
        if effect.reversesDirection && state.activePlayers.count > 2 {
            state.direction *= -1
            events.append(.directionReversed(clockwise: state.direction == 1))
            note("Turn order reverses.")
        }

        if let suit = effect.locksSuit {
            state.suitLock = SuitLock(suit: suit, setByPlayerID: playerID)
            events.append(.suitLocked(suit, by: playerID))
            note("\(name) locks the suit to \(suit.displayName).")
        } else if effect.liftsSuitLock, state.suitLock != nil {
            // An 8 always resets the lock; declining to name a suit resets it to
            // nothing, which is a real tactical option — it frees everyone.
            state.suitLock = nil
            events.append(.suitLockLifted)
            note("\(name) plays an 8 and names no suit — the lock lifts.")
        }

        state.forcedNegativeNext = effect.setsForcedNegativeNext
        state.pendingNineSuit = effect.isNine ? card.suit : nil

        if effect.completesHundred {
            events.append(.hundredReached)
            note("\(name) rides the matching Ace to 100. The next card is forced negative.")
        }

        return events
    }

    /// Play several cards of the same rank at once.
    ///
    /// Counts as a single play for the turn — dropping three 5s doesn't clear a
    /// two-play skip debt any faster than one card would.
    @discardableResult
    func playSet(cardIDs: [Int], by playerID: String, declaration: Declaration) throws -> [GameEvent] {
        guard !state.isOver else { throw GameError.gameOver }
        guard !state.isChoosingWells else { throw GameError.notChoosingWells }
        guard state.currentPlayer.id == playerID else { throw GameError.notYourTurn }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }

        let cards = cardIDs.compactMap { id in state.players[seat].hand.first { $0.id == id } }
        guard cards.count == cardIDs.count, !cards.isEmpty else { throw GameError.cardNotInHand }

        let effect: CardEffect
        switch Rules.resolveSet(cards: cards, declaration: declaration, in: state) {
        case .success(let resolved): effect = resolved
        case .failure(let reason): throw GameError.illegal(reason)
        }

        var events: [GameEvent] = []
        for card in cards {
            state.players[seat].hand.removeAll { $0.id == card.id }
        }
        // The whole set lands as one move: one tally change, one reversal, one
        // lock. Applying each card separately would reverse three times for
        // three 4s and re-announce the lock for every 8.
        events += apply(effect: effect, card: cards[cards.count - 1], playerID: playerID)
        // Everything under the top card is still on the pile.
        for card in cards.dropLast() {
            state.discardPile.insert(card, at: max(0, state.discardPile.count - 1))
        }
        events += refillHand(seat: seat)
        events += finishOnePlay(seat: seat)
        return events
    }

    // MARK: - Drawing

    private func refillHand(seat: Int) -> [GameEvent] {
        var events: [GameEvent] = []
        var drawn = 0
        while state.players[seat].hand.count < state.players[seat].handCap {
            guard let outcome = drawOne(into: seat, events: &events) else { break }
            if outcome { drawn += 1 }
        }
        if drawn > 0 {
            events.append(.drewCards(count: drawn, by: state.players[seat].id))
            state.players[seat].hand = Self.sorted(state.players[seat].hand)
        }
        return events
    }

    /// Draws a single card for `seat`.
    /// - Returns: `true` if a card reached the hand, `false` if the drawn card
    ///   was diverted to the poison pile (so the caller should try again),
    ///   `nil` if the deck is exhausted.
    @discardableResult
    private func drawOne(into seat: Int, events: inout [GameEvent]) -> Bool? {
        guard let card = takeFromDrawPile(events: &events) else { return nil }
        if card.rank == .queen {
            events += poison(queen: card, seat: seat)
            return false
        }
        state.players[seat].hand.append(card)
        return true
    }

    private func takeFromDrawPile(events: inout [GameEvent]) -> Card? {
        if state.drawPile.isEmpty {
            guard reshuffleDiscard(events: &events) else { return nil }
        }
        return state.drawPile.popLast()
    }

    private func reshuffleDiscard(events: inout [GameEvent]) -> Bool {
        // The active top card stays on the table; everything under it recycles.
        guard state.discardPile.count > 1 else { return false }
        let top = state.discardPile.removeLast()
        state.drawPile = random.shuffled(state.discardPile)
        state.discardPile = [top]
        events.append(.drawPileReshuffled)
        note("Draw pile exhausted — the discards are reshuffled.")
        return true
    }

    // MARK: - Poisonous queens

    /// A queen has come off the draw pile. The first one ever drawn turns
    /// queens poisonous game-wide, exiling every queen already held in hand.
    private func poison(queen: Card, seat: Int) -> [GameEvent] {
        var events: [GameEvent] = []
        let owner = state.players[seat]

        if !state.queensArePoisonous {
            state.queensArePoisonous = true
            events.append(.queensBecamePoisonous(card: queen, trigger: owner.id))
            note("Queens turn poisonous — \(owner.name) drew one.")

            // Everyone's held queens are exiled, the triggering player included — an
            // earlier version skipped their own hand, so the player who caused the
            // poisoning was the one person it didn't touch.
            for index in state.players.indices where !state.players[index].isEliminated {
                let held = state.players[index].hand.filter { $0.rank == .queen }
                for card in held {
                    state.players[index].hand.removeAll { $0.id == card.id }
                    state.players[index].poisonPile.append(card)
                    state.players[index].handCap = max(Rules.poisonedHandCapFloor, state.players[index].handCap - 1)
                    events.append(.queenPoisoned(
                        card: card,
                        owner: state.players[index].id,
                        newHandCap: state.players[index].handCap
                    ))
                    note("\(state.players[index].name)'s \(card.shortName) is exiled to their poison pile.")
                }
            }
        }

        // The drawn queen itself never reaches a hand.
        state.players[seat].poisonPile.append(queen)
        state.players[seat].handCap = max(Rules.poisonedHandCapFloor, state.players[seat].handCap - 1)
        events.append(.queenPoisoned(card: queen, owner: owner.id, newHandCap: state.players[seat].handCap))
        note("\(owner.name) draws \(queen.shortName) straight into the poison pile (cap \(state.players[seat].handCap)).")
        return events
    }

    // MARK: - Turn flow

    #if DEBUG
    /// Bank the first two cards for everyone still owing a well.
    ///
    /// Most tests are about what happens *after* the deal, and making each of
    /// them walk the selection queue by hand would bury the thing they're
    /// actually asserting. Tests that care about the choice itself call
    /// `chooseWell` properly.
    func _finishWellSelectionForTesting() {
        while let chooser = state.wellChooserID, let seat = state.index(of: chooser) {
            guard state.players[seat].hand.count >= Rules.wellSize else {
                state.wellSelectionQueue.removeFirst()
                continue
            }
            _ = try? chooseWell(slots: Array(0..<Rules.wellSize), by: chooser)
        }
    }
    #endif

    // MARK: - Choosing a well

    /// Bank two of your dealt cards face-down as your well. Everyone does this
    /// once, before the first card is played.
    ///
    /// The cards leave the hand rather than being drawn separately, which is the
    /// point of the rule: what you bank is what you give up holding. And it's
    /// **blind** — you pick two positions out of a face-down deal, so the well
    /// stays a real unknown until you're forced to turn one over. Seeing them
    /// would tell you your outs from the first turn and flatten the one moment
    /// the well exists for.
    ///
    /// Positions rather than card IDs for a second reason: this action goes into
    /// the shared log every peer reads, and a well card must stay hidden for the
    /// whole game.
    @discardableResult
    func chooseWell(slots: [Int], by playerID: String) throws -> [GameEvent] {
        guard state.isChoosingWells else { throw GameError.notChoosingWells }
        guard state.wellChooserID == playerID else { throw GameError.notYourTurn }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }

        let unique = Set(slots)
        guard unique.count == Rules.wellSize, slots.count == Rules.wellSize else {
            throw GameError.wrongWellSize(expected: Rules.wellSize)
        }
        let hand = state.players[seat].hand
        guard slots.allSatisfy({ hand.indices.contains($0) }) else {
            throw GameError.cardNotInHand
        }
        let chosen = slots.map { hand[$0] }

        for card in chosen {
            state.players[seat].hand.removeAll { $0.id == card.id }
            state.players[seat].well.append(card)
        }
        state.wellSelectionQueue.removeFirst()

        var events: [GameEvent] = [.wellChosen(by: playerID, count: chosen.count)]
        note("\(state.players[seat].name) banks two cards.")

        if !state.isChoosingWells {
            events.append(.wellSelectionFinished)
            note("\(state.currentPlayer.name) leads.")
            // The leader may be starting below the cap — a small deal leaves a
            // short hand, and the top-up is owed at the start of a turn.
            events += topUpForTurn()
        }
        return events
    }

    /// Draw the current player up to their cap before they act.
    ///
    /// Deal 5 and two go to the well, so play opens with three in hand and two
    /// owed. Refilling only *after* a play would leave that player choosing from
    /// three cards on the turn where they can least afford it.
    private func topUpForTurn() -> [GameEvent] {
        guard !state.isOver, !state.isChoosingWells else { return [] }
        return refillHand(seat: state.currentPlayerIndex)
    }

    private func finishOnePlay(seat: Int) -> [GameEvent] {
        var events: [GameEvent] = []
        state.playsRemainingThisTurn -= 1

        if state.playsRemainingThisTurn > 0 {
            // Still repaying a skip debt. They may not skip again; if they also
            // have no legal card and no well, they're out.
            let playerID = state.players[seat].id
            if !Rules.hasLegalPlay(playerID: playerID, in: state) && state.players[seat].well.isEmpty {
                events += eliminate(seat: seat, reason: .strandedWithoutWell)
                events += advanceTurn()
            }
            return events
        }

        events += advanceTurn()
        return events
    }

    private func advanceTurn() -> [GameEvent] {
        guard !state.isOver else { return [] }
        var events: [GameEvent] = []
        let count = state.players.count
        var index = state.currentPlayerIndex
        var guardCounter = 0
        repeat {
            index = ((index + state.direction) % count + count) % count
            guardCounter += 1
        } while state.players[index].isEliminated && guardCounter <= count * 2

        state.currentPlayerIndex = index
        let owesTwo = state.players[index].owesExtraPlay
        state.turnStartedWithDebt = owesTwo
        state.playsRemainingThisTurn = owesTwo ? 2 : 1
        state.players[index].owesExtraPlay = false
        state.pendingWell = nil
        events.append(.turnAdvanced(to: state.players[index].id, owesTwo: owesTwo))
        // Top up before they act, not after. Normally a no-op — a hand is
        // already at cap when its turn comes round — but it matters on the
        // opening turns of a small deal, and after a poisoned queen changes
        // someone's cap.
        events += topUpForTurn()
        return events
    }

    // MARK: - The well

    /// Shuffle the two face-down well cards, the way people do it at a table:
    /// you shake them about before picking one, because the ritual is the point.
    ///
    /// It is a *real* shuffle, drawn from the same seeded source as everything
    /// else and recorded as an action, rather than an animation over a fixed
    /// order. Nobody could tell the difference — the cards are face down and the
    /// player has never seen them — but a game that quietly lies during its most
    /// tense moment is a bad thing to have in a codebase, and this one keeps a
    /// stricter rule anyway: nothing that affects play happens outside the log.
    @discardableResult
    func shuffleWell(by playerID: String) throws -> [GameEvent] {
        guard !state.isOver else { throw GameError.gameOver }
        guard !state.isChoosingWells else { throw GameError.notChoosingWells }
        guard state.currentPlayer.id == playerID else { throw GameError.notYourTurn }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }
        // Only when there is genuinely a choice to shuffle: one card is not a
        // shuffle, and a card already turned over cannot be un-seen.
        guard state.players[seat].well.count > 1 else { throw GameError.wellEmpty }
        guard state.pendingWell == nil else { throw GameError.noPendingWell }

        state.players[seat].well = random.shuffled(state.players[seat].well)
        note("\(state.players[seat].name) shuffles the well.")
        return [.wellShuffled(by: playerID)]
    }



    /// Turn one of the player's two well cards face up, chosen at random.
    /// A playable card must then be resolved with `resolveWell`; an unplayable
    /// one eliminates its owner on the spot.
    /// - Parameter slot: which of the two face-down well cards to turn over.
    ///   The player chooses; both are face down, so the choice is blind — but it
    ///   is *theirs*. Having the engine pick made the single most tense moment in
    ///   the game something that happened *to* the player rather than something
    ///   they did. Out-of-range values are clamped rather than rejected, since a
    ///   spent well leaves only one slot.
    @discardableResult
    func drawFromWell(by playerID: String, slot: Int = 0) throws -> [GameEvent] {
        guard !state.isOver else { throw GameError.gameOver }
        guard !state.isChoosingWells else { throw GameError.notChoosingWells }
        guard state.currentPlayer.id == playerID else { throw GameError.notYourTurn }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }
        guard !state.players[seat].well.isEmpty else { throw GameError.wellEmpty }
        guard !Rules.hasLegalPlay(playerID: playerID, in: state) else {
            throw GameError.mustPlayFromHandFirst
        }

        let pick = min(max(slot, 0), state.players[seat].well.count - 1)
        let card = state.players[seat].well.remove(at: pick)
        let playable = Rules.isPlayable(card, in: state)

        var events: [GameEvent] = [.wellRevealed(card: card, by: playerID, playable: playable)]
        note("\(state.players[seat].name) goes to the well: \(card.shortName).")

        if playable {
            state.pendingWell = PendingWell(playerID: playerID, card: card, isPlayable: true)
        } else if let rank = Rules.rankCompletedInHand(by: card, for: state.players[seat]) {
            // The one reprieve: the card can't be played, but it's the third of
            // its rank. Snackoo is a free action, so it would be wrong to declare
            // the player out before offering it. Held pending — the player still
            // has to take it.
            state.pendingWell = PendingWell(
                playerID: playerID, card: card, isPlayable: false, snackooRank: rank
            )
            note("\(state.players[seat].name) can Snackoo three \(rank.displayName)s instead of going out.")
        } else {
            events += eliminate(seat: seat, reason: .unplayableWellCard(card))
            events += advanceTurn()
        }
        return events
    }

    /// Play the revealed well card. Rewards two bonus cards on top of the
    /// normal refill.
    @discardableResult
    func resolveWell(by playerID: String, declaration: Declaration) throws -> [GameEvent] {
        guard let pending = state.pendingWell, pending.playerID == playerID else {
            throw GameError.noPendingWell
        }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }

        let effect: CardEffect
        switch Rules.resolve(card: pending.card, declaration: declaration, in: state) {
        case .success(let resolved): effect = resolved
        case .failure(let reason): throw GameError.illegal(reason)
        }

        var events = apply(effect: effect, card: pending.card, playerID: playerID)
        events.append(.wellPlayed(card: pending.card, by: playerID))
        state.pendingWell = nil

        var bonus = 0
        for _ in 0..<2 {
            var drawEvents: [GameEvent] = []
            var landed: Bool? = false
            // Keep pulling until a card actually lands in hand (queens divert).
            while landed == false {
                landed = drawOne(into: seat, events: &drawEvents)
            }
            events += drawEvents
            if landed == true { bonus += 1 }
        }
        if bonus > 0 { events.append(.wellBonusDrawn(count: bonus, by: playerID)) }
        note("The well pays out — \(state.players[seat].name) draws \(bonus) bonus card\(bonus == 1 ? "" : "s").")

        events += refillHand(seat: seat)
        events += finishOnePlay(seat: seat)
        return events
    }

    // MARK: - Skipping

    @discardableResult
    func skip(by playerID: String) throws -> [GameEvent] {
        guard !state.isOver else { throw GameError.gameOver }
        guard !state.isChoosingWells else { throw GameError.notChoosingWells }
        guard state.currentPlayer.id == playerID else { throw GameError.notYourTurn }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }
        guard !state.turnStartedWithDebt else { throw GameError.cannotSkipWhileRepayingDebt }

        var events: [GameEvent] = [.turnSkipped(by: playerID), .extraPlayOwed(by: playerID)]
        state.players[seat].owesExtraPlay = true
        note("\(state.players[seat].name) skips — they owe two plays next turn.")

        // Failing to follow the lock is what breaks it.
        if state.suitLock != nil {
            state.suitLock = nil
            events.append(.suitLockLifted)
            note("The suit lock lifts.")
        }

        events += advanceTurn()
        return events
    }

    // MARK: - Snackoo

    /// A free action, available even off-turn.
    @discardableResult
    func declareSnackoo(by playerID: String, kind: GameEvent.SnackooKind) throws -> [GameEvent] {
        guard !state.isChoosingWells else { throw GameError.notChoosingWells }
        guard let seat = state.index(of: playerID), !state.players[seat].isEliminated else {
            throw GameError.snackooNotAvailable
        }
        var events: [GameEvent] = []
        var replacements = 3

        switch kind {
        case .threeQueens:
            guard Rules.canSnackooPoison(state.players[seat]) else { throw GameError.snackooNotAvailable }
            state.players[seat].poisonPile.removeFirst(3)

            // Clearing the queens gives back the capacity they cost. Without
            // this the reward is incoherent: three cards drawn into a hand that
            // can only hold two, immediately over its own limit and stuck there
            // for the rest of the game. The cap is a weight the queens put on
            // you, and this is putting it down.
            let restored = min(
                Rules.sustainingHandCap,
                state.players[seat].handCap + Rules.snackooSize
            )
            if restored != state.players[seat].handCap {
                state.players[seat].handCap = restored
                events.append(.handCapRestored(to: restored, for: playerID))
            }
            note("\(state.players[seat].name) declares Snackoo — three poisoned queens cleared.")

        case .threeOfAKind(let rank):
            let matching = state.players[seat].hand.filter { $0.rank == rank }
            guard matching.count >= 3 else { throw GameError.snackooNotAvailable }
            for card in matching.prefix(3) {
                state.players[seat].hand.removeAll { $0.id == card.id }
                state.discardPile.append(card)
            }
            note("\(state.players[seat].name) declares Snackoo — three \(rank.displayName)s.")
        }

        events.append(.snackoo(by: playerID, kind: kind))

        var drawn = 0
        while drawn < replacements {
            var drawEvents: [GameEvent] = []
            guard let landed = drawOne(into: seat, events: &drawEvents) else { break }
            events += drawEvents
            if landed { drawn += 1 }
        }
        replacements = drawn
        if drawn > 0 {
            events.append(.drewCards(count: drawn, by: playerID))
            state.players[seat].hand = Self.sorted(state.players[seat].hand)
        }
        return events
    }

    // MARK: - Elimination

    private func eliminate(seat: Int, reason: GameEvent.EliminationReason) -> [GameEvent] {
        guard !state.players[seat].isEliminated else { return [] }
        var events: [GameEvent] = []

        state.players[seat].isEliminated = true
        let rank = state.players.filter { $0.isEliminated }.count
        state.players[seat].eliminationRank = rank
        if state.firstEliminatedID == nil {
            state.firstEliminatedID = state.players[seat].id
        }
        note("\(state.players[seat].name) is out — \(reason.explanation)")

        // Captured before the well is emptied: the UI turns the unspent card
        // over so the player can see what they didn't pick.
        let unspentWell = state.players[seat].well

        // Their cards go back into circulation.
        let returned = state.players[seat].hand + state.players[seat].well + state.players[seat].poisonPile
        state.drawPile = random.shuffled(state.drawPile + returned)
        state.players[seat].hand = []
        state.players[seat].well = []
        state.players[seat].poisonPile = []

        // A lock dies with the player it was pointing at. Leaving it up would
        // hold the remaining players to a suit chosen for a table that no longer
        // exists — same reasoning as a lock lifting when someone can't follow it.
        if state.suitLock != nil {
            state.suitLock = nil
            events.append(.suitLockLifted)
            note("The suit lock lifts.")
        }

        events.append(.playerEliminated(
            id: state.players[seat].id, reason: reason, rank: rank, unspentWell: unspentWell
        ))

        if state.activePlayers.count == 1, let winner = state.activePlayers.first {
            state.winnerID = winner.id
            events.append(.gameWon(by: winner.id))
            note("\(winner.name) takes it.")
        }
        return events
    }

    // MARK: - Stuck detection (used by the UI to offer well/skip)

    /// The options genuinely available to the current player right now.
    var currentPlayerOptions: TurnOptions {
        let player = state.currentPlayer
        let hasPlay = Rules.hasLegalPlay(playerID: player.id, in: state)
        return TurnOptions(
            canPlayFromHand: hasPlay,
            canUseWell: !hasPlay && !player.well.isEmpty && state.pendingWell == nil,
            canSkip: !hasPlay && !state.turnStartedWithDebt && state.pendingWell == nil,
            isStranded: !hasPlay && player.well.isEmpty && state.turnStartedWithDebt
        )
    }

    /// Take the reprieve: the unplayable well card is the third of its rank, so
    /// it and the two in hand are discarded and three replacements drawn.
    ///
    /// This does **not** count as the player's play for the turn — Snackoo is a
    /// free action. They still owe a play, and with the well now spent they may
    /// yet be stranded. It buys a fresh hand, not a free pass.
    @discardableResult
    func snackooWellCard(by playerID: String) throws -> [GameEvent] {
        guard let pending = state.pendingWell,
              pending.playerID == playerID,
              let rank = pending.snackooRank
        else { throw GameError.snackooNotAvailable }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }

        let matching = state.players[seat].hand.filter { $0.rank == rank }
        guard matching.count >= 2 else { throw GameError.snackooNotAvailable }

        for card in matching.prefix(2) {
            state.players[seat].hand.removeAll { $0.id == card.id }
            state.discardPile.append(card)
        }
        state.discardPile.append(pending.card)
        state.pendingWell = nil

        var events: [GameEvent] = [.snackoo(by: playerID, kind: .threeOfAKind(rank))]
        note("\(state.players[seat].name) Snackoos three \(rank.displayName)s out of the well.")

        var drawn = 0
        while drawn < 3 {
            var drawEvents: [GameEvent] = []
            guard let landed = drawOne(into: seat, events: &drawEvents) else { break }
            events += drawEvents
            if landed { drawn += 1 }
        }
        if drawn > 0 {
            events.append(.drewCards(count: drawn, by: playerID))
            state.players[seat].hand = Self.sorted(state.players[seat].hand)
        }

        // Still stuck afterwards, with no well left and a debt owed? Then the
        // reprieve only delayed things.
        if !Rules.hasLegalPlay(playerID: playerID, in: state),
           state.players[seat].well.isEmpty,
           state.turnStartedWithDebt {
            events += eliminate(seat: seat, reason: .strandedWithoutWell)
            events += advanceTurn()
        }
        return events
    }

    /// Decline the reprieve — or have no reprieve to take. The revealed well card
    /// eliminates its owner.
    @discardableResult
    func concedeWellCard(by playerID: String) throws -> [GameEvent] {
        guard let pending = state.pendingWell, pending.playerID == playerID, !pending.isPlayable else {
            throw GameError.noPendingWell
        }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }
        state.pendingWell = nil
        var events = eliminate(seat: seat, reason: .unplayableWellCard(pending.card))
        events += advanceTurn()
        return events
    }

    /// A player leaves the match. Unlike every other elimination this can happen
    /// off-turn, so the turn is only advanced when the leaver was the one holding
    /// it — advancing unconditionally would skip whoever is actually to play.
    @discardableResult
    func forfeit(by playerID: String) throws -> [GameEvent] {
        guard !state.isOver else { throw GameError.gameOver }
        // Deliberately *not* gated on the well phase: someone quitting before
        // they've banked would otherwise wedge everyone still waiting on them.
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }
        guard !state.players[seat].isEliminated else { return [] }

        let wasCurrent = state.currentPlayerIndex == seat
        var events = eliminate(seat: seat, reason: .forfeited)
        // A forfeit mid-reveal must not leave a dangling well card.
        if state.pendingWell?.playerID == playerID { state.pendingWell = nil }
        if wasCurrent && !state.isOver {
            events += advanceTurn()
        }
        return events
    }

    /// Force the elimination of a player who is repaying a debt with no play and
    /// no well. The UI calls this when `TurnOptions.isStranded`.
    @discardableResult
    func concedeStranded(by playerID: String) throws -> [GameEvent] {
        guard !state.isChoosingWells else { throw GameError.notChoosingWells }
        guard let seat = state.index(of: playerID) else { throw GameError.notYourTurn }
        guard state.currentPlayer.id == playerID else { throw GameError.notYourTurn }
        var events = eliminate(seat: seat, reason: .strandedWithoutWell)
        events += advanceTurn()
        return events
    }
}

struct TurnOptions: Equatable, Sendable {
    var canPlayFromHand: Bool
    var canUseWell: Bool
    var canSkip: Bool
    var isStranded: Bool
}
