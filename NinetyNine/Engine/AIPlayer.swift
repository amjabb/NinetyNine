//
//  AIPlayer.swift
//  Heuristic opponents for 99.
//
//  The AI reaches the table only through the same public engine API a human
//  does — it never inspects another player's hand or well, so it plays fair by
//  construction. Difficulty changes *what it values*, not how much it cheats.
//

import Foundation

struct AIMove: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case play(cardID: Int, declaration: Declaration)
        case useWell
        case skip
        case snackoo(GameEvent.SnackooKind)
        /// Take the reprieve on an unplayable well card that completes a trio.
        case snackooWell
        case concede
    }
    var kind: Kind
    /// Short rationale, surfaced in the table's play-by-play so the opponent
    /// reads as a character rather than a random-number generator.
    var rationale: String
}

struct AIPlayer {
    let difficulty: Difficulty
    /// Which pressing weapons are live. Full set in play; the strength harness
    /// varies it to measure one weapon at a time.
    var weapons: PressingWeapons = .all
    /// What a certain kill is worth, in the same units as the headroom term
    /// (which spans 0...99). Tuned by measurement, not taste — see
    /// `AIStrengthTests.testKillPressureWeightSweep`.
    var killPressureWeight: Double = AIPlayer.defaultKillPressureWeight

    static let defaultKillPressureWeight: Double = 120
    /// How much the pressing tier still cares about its own headroom. 1.0 is
    /// "same as every other tier"; lower lets a kill outvote a comfortable board.
    static let defaultHeadroomScale: Double = 1.0


    init(
        difficulty: Difficulty,
        weapons: PressingWeapons = .all,
        killPressureWeight: Double = AIPlayer.defaultKillPressureWeight,
        headroomScale: Double = AIPlayer.defaultHeadroomScale
    ) {
        self.difficulty = difficulty
        self.weapons = weapons
        self.killPressureWeight = killPressureWeight
        self.headroomScale = headroomScale
    }

    var headroomScale: Double = AIPlayer.defaultHeadroomScale

    // MARK: - Entry point

    /// The single next action this AI wants to take. The caller applies it and
    /// asks again — one decision per call keeps the turn animatable.
    func nextMove(for playerID: String, engine: GameEngine) -> AIMove? {
        let state = engine.state
        guard !state.isOver, state.currentPlayer.id == playerID,
              let player = state.player(id: playerID) else { return nil }

        // A pending well reveal must be resolved before anything else.
        if let pending = state.pendingWell, pending.playerID == playerID {
            if pending.snackooRank != nil {
                // Strictly better than elimination — there is nothing to weigh.
                return AIMove(kind: .snackooWell, rationale: "Snackoos out of the well")
            }
            let declarations = Rules.legalDeclarations(for: pending.card, in: state)
            if let best = bestDeclaration(for: pending.card, among: declarations, player: player, state: state) {
                return AIMove(
                    kind: .play(cardID: pending.card.id, declaration: best.declaration),
                    rationale: "rides the well card out"
                )
            }
            // Unplayable with no way out: accept it rather than stalling the turn.
            return AIMove(kind: .concede, rationale: "is finished by the well")
        }

        // Snackoo is free — clear a full poison pile whenever possible, and dump
        // three-of-a-kind when the hand needs churn.
        if Rules.canSnackooPoison(player) {
            return AIMove(kind: .snackoo(.threeQueens), rationale: "clears three poisoned queens")
        }
        if let rank = snackooWorthTaking(player: player, state: state) {
            return AIMove(kind: .snackoo(.threeOfAKind(rank)), rationale: "cycles three \(rank.displayName)s")
        }

        let options = engine.currentPlayerOptions

        if options.canPlayFromHand {
            let candidates = allLegalPlays(player: player, state: state)
            if let best = bestDeclaration(from: candidates, player: player, state: state) {
                return AIMove(
                    kind: .play(cardID: best.card.id, declaration: best.declaration),
                    rationale: best.rationale
                )
            }
        }

        if options.isStranded { return AIMove(kind: .concede, rationale: "has nothing left") }

        // Stuck. The well is a coin flip on elimination; skipping costs a double
        // turn later. Weigh survival odds against how bad the next turn looks.
        if options.canUseWell && options.canSkip {
            return wellIsWorthTheRisk(player: player, state: state)
                ? AIMove(kind: .useWell, rationale: "gambles on the well")
                : AIMove(kind: .skip, rationale: "plays it safe and skips")
        }
        if options.canUseWell { return AIMove(kind: .useWell, rationale: "has no choice but the well") }
        if options.canSkip { return AIMove(kind: .skip, rationale: "skips") }
        return AIMove(kind: .concede, rationale: "is out of outs")
    }

    // MARK: - Candidate generation

    private struct Candidate {
        var card: Card
        var declaration: Declaration
        var effect: CardEffect
        var rationale: String = ""
    }

    private func allLegalPlays(player: PlayerState, state: GameState) -> [Candidate] {
        var candidates: [Candidate] = []
        for card in player.hand {
            for declaration in Rules.legalDeclarations(for: card, in: state) {
                if case .success(let effect) = Rules.resolve(card: card, declaration: declaration, in: state) {
                    candidates.append(Candidate(card: card, declaration: declaration, effect: effect))
                }
            }
        }
        return candidates
    }

    private func bestDeclaration(
        for card: Card,
        among declarations: [Declaration],
        player: PlayerState,
        state: GameState
    ) -> Candidate? {
        let candidates: [Candidate] = declarations.compactMap { declaration in
            guard case .success(let effect) = Rules.resolve(card: card, declaration: declaration, in: state) else {
                return nil
            }
            return Candidate(card: card, declaration: declaration, effect: effect)
        }
        return bestDeclaration(from: candidates, player: player, state: state)
    }

    private func bestDeclaration(from candidates: [Candidate], player: PlayerState, state: GameState) -> Candidate? {
        guard !candidates.isEmpty else { return nil }
        var scored = candidates.map { ($0, score($0, player: player, state: state)) }

        scored.sort { $0.1 > $1.1 }
        var winner = scored[0].0
        winner.rationale = rationale(for: winner, player: player, state: state)
        return winner
    }

    // MARK: - Scoring

    private func score(_ candidate: Candidate, player: PlayerState, state: GameState) -> Double {
        let rank = candidate.effect.effectiveRank
        var score = 0.0

        // Headroom under the ceiling is the currency of this game — but the
        // question is *whose*.
        //
        // Scoring it as "99 minus the new tally" is the single biggest term in
        // this function, and it points the wrong way. It reads as prudence and
        // plays as generosity: every point of headroom you decline to spend is
        // headroom handed to the player after you. It is why the lower tiers
        // drift around the middle of the board all game and almost never put
        // anybody under real pressure.
        //
        // The first version of the pressing tier *dropped* this term, on the
        // theory that headroom is what you hand the next player. Measured over
        // 400 games it was worse than the tier below it: a board you cannot
        // answer is worthless however tight it is for everyone else, and
        // pressing indiscriminately is mostly self-harm — you get the pinned
        // board back.
        //
        // So the term stays, and pressing is *opportunistic* instead: the
        // weapons below fire when a kill is actually on (a debt to repay, a
        // suit they've shown they haven't got, a spent well) and stay holstered
        // the rest of the time.
        score += Double(Rules.ceiling - candidate.effect.newTally)
            * (difficulty.pressesTheTally ? headroomScale : 1.0)

        // A negative tally is a fortress — everyone downstream is squeezed.
        if candidate.effect.newTally < 0 { score += 14 }
        // Landing exactly on 0 re-opens the 10-to-negative door for us.
        if candidate.effect.newTally == 0 { score += 8 }

        // A 9 pins the tally at 99 and hands the next player a near-dead board —
        // brutal offence, but suicidal if it comes back around. Only strong when
        // we hold the matching Ace to ride it to 100, or when opponents are
        // about to be starved.
        if rank == .nine {
            let holdsMatchingAce = player.hand.contains {
                $0.rank == .ace && $0.suit == candidate.card.suit && $0.id != candidate.card.id
            }
            if holdsMatchingAce {
                score += 25
            } else {
                // Still worth it as a finisher if only one opponent stands and
                // their well is spent.
                let opponents = state.activePlayers.filter { $0.id != player.id }
                let allWellsDry = opponents.allSatisfy { $0.well.isEmpty }
                if allWellsDry {
                    score += 20
                } else if difficulty.pressesTheTally && weapons.contains(.pinAtNinetyNine) {
                    // A 9 pins the board at 99 and leaves the next player one
                    // card: a 10, an Ace as one on a matching nine, or nothing.
                    // The blanket -35 treated that as recklessness. It's the
                    // strongest single move in the game against somebody who
                    // has to find *two* legal plays, and merely a good one
                    // against anybody the table has already read as short.
                    score += pressingNineValue(candidate, player: player, state: state)
                } else {
                    score -= 35
                }
            }
        }

        // The suit lock used to be the strongest weapon in the game. It isn't
        // any more: a card matching the rank of the one face up beats it from
        // any suit, and takes the lock with it. So locking is worth a little,
        // not a lot, and worth most when we're long in the suit we name — which
        // at least means we can follow our own lock.
        if rank == .eight, let locked = candidate.declaration.lockSuit {
            let support = player.hand.filter { $0.suit == locked && $0.id != candidate.card.id }.count
            score += 2 + Double(support) * 2
        }

        // Brakes (10s, Aces) are worth hoarding while the tally is low; face
        // cards are dead weight and should be shed early.
        //
        // With one exception, and it's new: a 10 now dives below zero from any
        // tally, and a negative board is the strongest position in the game —
        // everyone downstream has to climb out through exactly nothing. Diving
        // is no longer something you wait at zero for, so a 10 played early can
        // be the best card on the table rather than a wasted brake.
        let isBrake = candidate.card.rank == .ten || candidate.card.rank == .ace
        let dives = candidate.effect.newTally < 0 && state.tally >= 0
        if dives {
            score += 18
        } else if state.tally < 45 {
            if isBrake { score -= 9 }
            if candidate.card.rank == .jack || candidate.card.rank == .king { score += 3 }
        } else if state.tally > 80 && isBrake {
            // Late on, a brake is exactly the right card.
            score += 6
        }

        // A Queen is the most flexible card in the deck — spending it on a
        // routine play wastes it (and holding it risks poisoning; sharp play
        // accepts that trade, ruthless play weighs the poison risk).
        if candidate.card.rank == .queen {
            // Was 16 for ruthless and 8 for everyone else. Hoarding the most
            // flexible card in the deck reads as cunning and measured as a loss:
            // ruthless was the *weakest* tier on the ladder, below the one it
            // was supposed to outrank, and this was part of why.
            score -= 8
            if state.queensArePoisonous { score += 20 } // dump it before it's exiled
        }

        // Reversing is a real weapon: it can hand the squeeze back to the player
        // who just built it.
        if rank == .four && state.activePlayers.count > 2 {
            score += state.tally > 70 ? 8 : 2
        }

        // Don't leave ourselves with an unplayable hand: peek one step ahead and
        // penalise lines that strand us.
        score += Double(lookaheadBonus(candidate, player: player, state: state))

        // Merciless plays at the person receiving the board rather than at the
        // board. Everything above is about what a card does *here*; this is
        // about what it does to whoever has to answer it, which is what the
        // game is actually decided by.
        if difficulty.readsTheTable {
            let pressure = pressureOnNextPlayer(after: candidate, player: player, state: state)
            let safety = ownSafety(after: candidate, player: player, state: state)

            // Strangling the next player is worth more than any tally
            // consideration — being unable to play is the only way to lose.
            score += pressure * 120

            // But not at the cost of walking into it ourselves next turn.
            score += safety * 34
            if safety == 0 { score -= 45 }

            // Keep one universal out in reserve. With a hand of three, holding
            // a card that plays from almost anywhere is the difference between
            // being squeezed and being finished.
            let keptOuts = player.hand
                .filter { $0.id != candidate.card.id }
                .filter { $0.rank == .queen || $0.rank == .ten || $0.rank == .jack || $0.rank == .four }
                .count
            if keptOuts == 0 && player.hand.count > 1 { score -= 12 }

            // An 8 hands the next player the answer to it: after a lock, any 8
            // beats it and takes the lock away. Only worth doing while 8s are
            // scarce enough that they probably haven't got one.
            if rank == .eight {
                let eightsGone = state.discardPile.filter { $0.rank == .eight }.count
                    + player.hand.filter { $0.rank == .eight && $0.id != candidate.card.id }.count
                score += Double(eightsGone) * 6 - 6
            }
        }

        // Ruthless and above: keep the cards that get you out of trouble, and
        // judge the hand by the boards it could still meet.
        //
        // These sit here rather than in the tier above because the ladder has to
        // be *nested* to stay ordered. Ruthless used to differ from Sharp only by
        // tweaked constants — a heavier lookahead, a hoarded Queen, a looser well
        // gamble — and measured out as the weakest tier of the four. Constants
        // tuned by taste don't compose into a ladder; capabilities do.
        if difficulty.holdsItsOuts, weapons.contains(.hoardOuts) {
            score += utilityHoardingPenalty(candidate, player: player, state: state)
        }
        // Reading the table and reading your own future are the same skill
        // pointed in two directions, so they arrive together.
        if difficulty.readsTheTable, weapons.contains(.foresight) {
            score += returningBoardSurvival(candidate, player: player, state: state)
        }

        if difficulty.pressesTheTally {
            if weapons.contains(.debt) {
                score += debtBonus(candidate, player: player, state: state)
            }
            if weapons.contains(.voidHunt) {
                score += voidHuntBonus(candidate, player: player, state: state)
            }
            if weapons.contains(.hardPressure) {
                // The tier below prices a kill at 120 x its probability. At a
                // pinned 99 that probability is about a third, so 40 points —
                // while pinning the tally *costs* up to 74 points of headroom.
                // The kill was priced below the comfort, which is precisely why
                // no tier ever pushed anybody to 99: not a missing idea, an
                // arithmetic one. This closes the gap, and because it scales
                // with the real chance it stays quiet when there is no kill on.
                let pressure = pressureOnNextPlayer(after: candidate, player: player, state: state)
                score += pressure * killPressureWeight
            }
        }

        return score
    }

    /// One-ply self-check: after this play, how many of our remaining cards
    /// would still be legal? A line that leaves us with options is worth more
    /// than one that leaves us praying for the well.
    private func lookaheadBonus(_ candidate: Candidate, player: PlayerState, state: GameState) -> Int {
        var future = state
        future.tally = candidate.effect.newTally
        future.forcedNegativeNext = candidate.effect.setsForcedNegativeNext
        future.pendingNineSuit = candidate.effect.isNine ? candidate.card.suit : nil
        if let locked = candidate.effect.locksSuit {
            future.suitLock = SuitLock(suit: locked, setByPlayerID: player.id)
        }

        let remaining = player.hand.filter { $0.id != candidate.card.id }
        let survivors = remaining.filter { Rules.isPlayable($0, in: future) }.count
        if remaining.isEmpty { return 0 }

        let ratio = Double(survivors) / Double(remaining.count)
        var bonus = Int(ratio * 16)
        if survivors == 0 { bonus -= 30 } // never walk into a dead hand willingly
        return bonus
    }

    // MARK: - Stuck decisions

    /// When stuck with both options open: is the well worth the elimination risk?
    /// Skipping is free now but costs a double play next turn — and a double
    /// play on a tight board is often a slower death.
    private func wellIsWorthTheRisk(player: PlayerState, state: GameState) -> Bool {
        // Rough survival odds: how much of the *unseen* deck would be legal here.
        let seen = Set(player.hand.map(\.id) + state.discardPile.map(\.id))
        let unseen = Deck.standard().filter { !seen.contains($0.id) }
        let playable = unseen.filter { Rules.isPlayable($0, in: state) }.count
        let odds = unseen.isEmpty ? 0 : Double(playable) / Double(unseen.count)

        switch difficulty {
        case .sharp:
            return odds > 0.55
        case .ruthless:
            // Was a pair of fixed thresholds that dropped to 0.45 "when the
            // squeeze is on" — i.e. it accepted a 55% chance of elimination to
            // avoid a skip, which costs two plays and no lives. Ruthless came
            // out the *weakest* tier on the ladder, below the one it was meant
            // to outrank, and this was the largest part of it.
            //
            // Now the same comparison the tiers above make: the well is worth it
            // only when it beats the odds of surviving the skip instead.
            return odds > survivalAfterSkipping(player: player, state: state)
        case .merciless, .cutthroat:
            // Compares the two deaths rather than picking a threshold. A skip
            // costs two plays next turn, which on a board this tight is often
            // worse than the coin flip — so the bar moves with how survivable
            // the *next* turn looks, not with how the tally feels.
            //
            // A previous version had the pressing tier accept 12 points worse
            // odds rather than skip under a lock, on the theory that skipping
            // leaks which suit it is missing. Measured, that one line cost it
            // 13 points of win rate — it was taking a coin flip on elimination
            // to avoid giving away information worth a fraction of it. The
            // cheapest mistake to make and the hardest to see by reading.
            let debtSurvival = survivalAfterSkipping(player: player, state: state)
            return odds > debtSurvival
        }
    }

    /// Only churn a three-of-a-kind when it actually helps: a hand full of
    /// duplicates is a hand with few options.
    private func snackooWorthTaking(player: PlayerState, state: GameState) -> Rank? {
        let ranks = Rules.snackooRanksInHand(for: player)
        guard let rank = ranks.first else { return nil }
        let playableNow = player.hand.filter { Rules.isPlayable($0, in: state) }.count
        // Hold the trio if the hand is already flexible and the deck is thin.
        if playableNow >= 4 && state.effectiveDrawCount < 8 { return nil }
        return rank
    }

    // MARK: - Reading the table

    /// Cards this player cannot account for: not in their hand, not on the
    /// discard pile, not in their own poison pile.
    ///
    /// Deliberately not the engine's draw pile. Everything here is knowable by
    /// somebody sitting at the table with a good memory, which is the whole
    /// point — an opponent that reads the actual deck is not a better player,
    /// it's a cheat, and it would feel like one.
    private func unseenCards(for player: PlayerState, state: GameState) -> [Card] {
        var accounted = Set(player.hand.map(\.id))
        accounted.formUnion(state.discardPile.map(\.id))
        accounted.formUnion(player.poisonPile.map(\.id))
        return Deck.standard().filter { !accounted.contains($0.id) }
    }

    /// Roughly how likely the player after us is to be stuck in `future`.
    ///
    /// This is the thing the other tiers never ask. 99 is not won by playing
    /// well, it's won by being the last one able to play at all — so the value
    /// of a move is mostly what it does to the person receiving it. Their hand
    /// is hidden, but its *size* is public, and so is everything already played;
    /// the chance that none of their cards is legal is what's left.
    private func pressureOnNextPlayer(
        after candidate: Candidate, player: PlayerState, state: GameState
    ) -> Double {
        guard let next = nextActivePlayer(after: player, in: state, reversing: candidate.effect.reversesDirection)
        else { return 0 }

        let future = projected(candidate, by: player, from: state)
        let pool = unseenCards(for: player, state: state)
        guard !pool.isEmpty else { return 0 }

        let dead = pool.filter { !Rules.isPlayable($0, in: future) }.count
        let deadShare = Double(dead) / Double(pool.count)

        // Their whole hand has to be dead, so the share compounds. A player
        // holding one card is far easier to strand than one holding three,
        // which is exactly why the hand count is worth watching.
        // Their *count*, never their cards — the table shows everyone how many
        // each player holds, so this is fair game where reading the hand itself
        // would not be.
        let held = max(1, next.hand.count)
        var chance = pow(deadShare, Double(held))

        // A player who skipped owes two plays: they have to find two legal
        // cards, not one. Squeeze them now or never.
        if next.owesExtraPlay { chance = min(1, chance * 1.6) }
        // A spent well means being stuck is fatal rather than merely expensive.
        if next.well.isEmpty { chance = min(1, chance * 1.35) }
        return chance
    }

    /// How survivable our own next turn looks, judged the same way — against
    /// what we'd be holding, not against what we hold now.
    private func ownSafety(
        after candidate: Candidate, player: PlayerState, state: GameState
    ) -> Double {
        let future = projected(candidate, by: player, from: state)
        let remaining = player.hand.filter { $0.id != candidate.card.id }
        guard !remaining.isEmpty else { return 1 }
        let alive = remaining.filter { Rules.isPlayable($0, in: future) }.count
        return Double(alive) / Double(remaining.count)
    }

    /// The board as it would stand after this play.
    private func projected(_ candidate: Candidate, by player: PlayerState, from state: GameState) -> GameState {
        var future = state
        future.tally = candidate.effect.newTally
        future.forcedNegativeNext = candidate.effect.setsForcedNegativeNext
        future.pendingNineSuit = candidate.effect.isNine ? candidate.card.suit : nil
        future.discardPile.append(candidate.card)
        future.topPlayedAsEight = candidate.effect.effectiveRank == .eight
        if let locked = candidate.effect.locksSuit {
            future.suitLock = SuitLock(suit: locked, setByPlayerID: player.id)
        } else if candidate.effect.liftsSuitLock {
            future.suitLock = nil
        }
        return future
    }

    private func nextActivePlayer(
        after player: PlayerState, in state: GameState, reversing: Bool
    ) -> PlayerState? {
        guard let start = state.index(of: player.id) else { return nil }
        let step = (reversing ? -state.direction : state.direction) >= 0 ? 1 : -1
        let count = state.players.count
        var index = start
        for _ in 0..<count {
            index = ((index + step) % count + count) % count
            if !state.players[index].isEliminated && state.players[index].id != player.id {
                return state.players[index]
            }
        }
        return nil
    }

    /// What our odds look like if we skip instead: two plays owed next turn,
    /// against whatever the board becomes.
    private func survivalAfterSkipping(player: PlayerState, state: GameState) -> Double {
        // Two legal cards needed rather than one, so the bar for taking the
        // well instead is lower the tighter the board is.
        let pool = unseenCards(for: player, state: state)
        guard !pool.isEmpty else { return 0.5 }
        let live = Double(pool.filter { Rules.isPlayable($0, in: state) }.count) / Double(pool.count)
        // Rough: needing two in a row from a hand this size.
        return min(0.75, max(0.3, live * live + 0.25))
    }

    // MARK: - Narration

    private func rationale(for candidate: Candidate, player: PlayerState, state: GameState) -> String {
        let rank = candidate.effect.effectiveRank
        if candidate.effect.completesHundred { return "rides the Ace to 100" }
        if rank == .nine { return "slams it to 99" }
        if let suit = candidate.declaration.lockSuit { return "locks \(suit.displayName)" }
        if rank == .four && state.activePlayers.count > 2 { return "flips the order" }
        if candidate.effect.newTally < 0 { return "digs into the negatives" }
        if candidate.effect.newTally == 0 { return "resets to zero" }
        if rank == .ten { return "hits the brakes" }
        if candidate.card.rank == .queen { return "spends the Queen as a \(rank.displayName)" }
        return "plays \(candidate.card.shortName)"
    }

    /// The opportunistic weapons the pressing tier may use.
    ///
    /// Individually switchable because they had to be measured individually:
    /// bundled together they made the tier *worse* than the one below it, and
    /// there is no way to tell which one carries the loss by reading them.
    struct PressingWeapons: OptionSet, Sendable {
        let rawValue: Int
        /// Press hardest at a player repaying a skip debt.
        static let debt = PressingWeapons(rawValue: 1 << 0)
        /// Re-lock the suit a player has already failed to follow.
        static let voidHunt = PressingWeapons(rawValue: 1 << 1)
        /// Treat a 9 as a finisher rather than a last resort.
        static let pinAtNinetyNine = PressingWeapons(rawValue: 1 << 2)
        /// Keep 4s, Jacks, 10s, Aces and Queens back for the squeeze.
        static let hoardOuts = PressingWeapons(rawValue: 1 << 3)
        /// Judge a hand by the boards it could still answer, not just this one.
        static let foresight = PressingWeapons(rawValue: 1 << 4)
        /// Price a kill at what it is actually worth.
        static let hardPressure = PressingWeapons(rawValue: 1 << 5)

        static let all: PressingWeapons = [
            .debt, .voidHunt, .pinAtNinetyNine, .hoardOuts, .foresight, .hardPressure,
        ]
    }

    // MARK: - Pressing

    /// What a 9 is worth to a tier that presses.
    ///
    /// Pinning the board at 99 leaves the next player needing a 10, a Jack, a 4,
    /// or the Ace that matches — a narrow door. It is a genuine risk, because the
    /// board comes back around still pinned; so this prices the risk rather than
    /// refusing the move.
    private func pressingNineValue(_ candidate: Candidate, player: PlayerState, state: GameState) -> Double {
        guard let next = nextActivePlayer(after: player, in: state, reversing: candidate.effect.reversesDirection)
        else { return -20 }

        var value = 44.0
        // Someone repaying a skip has to find two legal plays out of a board
        // with one door. That is close to a kill.
        if next.owesExtraPlay { value += 62 }
        // A spent well means being stuck is fatal rather than merely expensive.
        if next.well.isEmpty { value += 26 }
        // Short hands have fewer chances to hold the answer.
        if next.hand.count <= 2 { value += 12 }

        // Priced against our own exposure: we get the pinned board back if they
        // survive it, so hold something that opens the door for us too.
        let outs = player.hand.filter { $0.id != candidate.card.id }
            .filter { $0.rank == .ten || $0.rank == .jack || $0.rank == .four || $0.rank == .queen }
            .count
        if outs == 0 { value -= 34 }

        return value
    }

    /// A skip is a wound; this is the tier that reopens it.
    ///
    /// A player repaying a skip debt owes *two* legal plays on their next turn.
    /// Every point of pressure therefore counts roughly twice, and a board they
    /// can only half-answer finishes them where a comfortable one would not.
    private func debtBonus(_ candidate: Candidate, player: PlayerState, state: GameState) -> Double {
        guard let next = nextActivePlayer(after: player, in: state, reversing: candidate.effect.reversesDirection),
              next.owesExtraPlay
        else { return 0 }

        let pressure = pressureOnNextPlayer(after: candidate, player: player, state: state)
        // Doubling the requirement roughly squares the chance of failing it.
        var bonus = pressure * 90
        // Sending a debt-payer to a spent well is the cleanest kill in the game.
        if next.well.isEmpty { bonus += pressure * 40 }
        return bonus
    }

    /// Lock the suit they already told you they haven't got.
    ///
    /// When a player skips under a lock they announce, publicly, that they hold
    /// nothing in that suit, no Queen, and nothing matching the rank showing.
    /// Naming that suit again is the single most direct way to put them back in
    /// the same corner — and against a debt-payer it usually ends them.
    private func voidHuntBonus(
        _ candidate: Candidate, player: PlayerState, state: GameState
    ) -> Double {
        guard difficulty.huntsTheVoid,
              candidate.effect.effectiveRank == .eight,
              let naming = candidate.declaration.lockSuit
        else { return 0 }

        // Deliberately not "the next player" alone. An earlier version asked
        // only whoever plays next and silently never fired — the seat lookup it
        // depended on disagreed with the table in exactly the position this is
        // for. Naming a suit an opponent is void in is worth something whoever
        // they are, so score every opponent that has shown the hole and weight
        // by how soon they have to answer it.
        let order = seatingOrderAfter(player, in: state, reversing: candidate.effect.reversesDirection)
        var bonus = 0.0
        for (distance, opponent) in order.enumerated() where opponent.skippedUnderLock == naming {
            // The player immediately after us has to answer this card; anyone
            // further round may never see the lock at all.
            let immediacy = distance == 0 ? 1.0 : 0.35
            var value = 52.0
            if opponent.owesExtraPlay { value += 30 }
            if opponent.well.isEmpty { value += 16 }
            bonus += value * immediacy
        }
        return bonus
    }

    /// Active opponents in the order they'll have to answer, nearest first.
    private func seatingOrderAfter(
        _ player: PlayerState, in state: GameState, reversing: Bool
    ) -> [PlayerState] {
        guard let start = state.index(of: player.id) else { return [] }
        let step = (reversing ? -state.direction : state.direction) >= 0 ? 1 : -1
        let count = state.players.count
        var result: [PlayerState] = []
        var index = start
        for _ in 0..<count {
            index = ((index + step) % count + count) % count
            let seat = state.players[index]
            if seat.id != player.id && !seat.isEliminated { result.append(seat) }
        }
        return result
    }

    /// How well the hand we'd be left with answers the board when it comes back.
    ///
    /// Every other term here judges a card by what it does to *this* board. But
    /// the board returns, two or three plays later and almost always tighter,
    /// and the hand that meets it is whatever is left after this decision. A
    /// player who never asks that question spends its 4s and Jacks while they
    /// are merely convenient and meets the squeeze holding three number cards.
    private func returningBoardSurvival(
        _ candidate: Candidate, player: PlayerState, state: GameState
    ) -> Double {
        let remaining = player.hand.filter { $0.id != candidate.card.id }
        guard !remaining.isEmpty else { return 0 }

        // Weighted toward a tight return: a hand that only answers a quiet board
        // is a hand that loses.
        let futures: [(tally: Int, weight: Double)] = [
            (55, 0.6), (70, 0.9), (82, 1.3), (90, 1.6), (95, 1.8), (Rules.ceiling, 2.0),
        ]

        var answered = 0.0
        var total = 0.0
        for future in futures {
            total += future.weight
            var board = state
            board.tally = future.tally
            board.forcedNegativeNext = false
            board.pendingNineSuit = nil
            // Deliberately without the suit lock: we're asking what the hand can
            // do about the *tally*, and a lock we can't predict would swamp it.
            board.suitLock = nil
            if remaining.contains(where: { Rules.isPlayable($0, in: board) }) {
                answered += future.weight
            }
        }

        return (answered / max(total, 0.001)) * 40
    }

    /// Stop spending the good cards on ordinary turns.
    ///
    /// 4s, Jacks, 10s, Aces and Queens are the cards that play from almost any
    /// board — they are what a hand is *worth* when the squeeze comes. Spending
    /// one while an ordinary card would have done the same job trades a future
    /// escape for nothing, and it is the most visible weakness in the lower
    /// tiers: by the time the tally is dangerous their hand is three number
    /// cards and a prayer.
    private func utilityHoardingPenalty(_ candidate: Candidate, player: PlayerState, state: GameState) -> Double {
        let utility: Set<Rank> = [.four, .jack, .ten, .ace, .queen]
        guard utility.contains(candidate.card.rank) else { return 0 }

        // Cheap when the board is already desperate — that's what they're for.
        if state.tally > 82 { return 0 }
        // Or when they're the only thing that plays at all.
        let alternatives = player.hand
            .filter { $0.id != candidate.card.id && !utility.contains($0.rank) }
            .filter { Rules.isPlayable($0, in: state) }
        if alternatives.isEmpty { return 0 }

        // Scaled by how early it is: burning a Jack at a tally of 12 is worse
        // than burning one at 70.
        let earliness = Double(max(0, 82 - state.tally)) / 82.0
        return -26 * earliness
    }

    // MARK: - Choosing a well

    /// Which two positions to bank face-down.
    ///
    /// Deliberately ignorant of what the cards are, because the player is too:
    /// the deal is face down while the well is chosen. An opponent that peeked
    /// and banked its two safest cards would be cheating at the one decision
    /// where nobody has any information — so this is a positional choice, and
    /// the tiers differ only in *where* they reach, which is flavour rather than
    /// advantage.
    func chooseWellSlots(dealtCount: Int, size: Int = Rules.wellSize) -> [Int] {
        guard dealtCount > size else { return Array(0..<max(0, dealtCount)) }
        switch difficulty {
        case .sharp: return Array((dealtCount - size)..<dealtCount) // off the bottom
        case .ruthless:                                             // from the middle
            let start = max(0, (dealtCount - size) / 2)
            return Array(start..<(start + size))
        case .merciless, .cutthroat:                                // off the end
            return Array((dealtCount - size)..<dealtCount)
        }
    }

    // MARK: - Dealing

    /// How many cards this opponent deals when it wins the deal.
    ///
    /// The number buys two things, and the second is the interesting one: the
    /// opening hand (`dealt - 2`, which decays to the sustaining three anyway),
    /// and **how much choice everyone gets over their well**. Deal three and a
    /// player banks two of three — no choice at all. Deal nine and they pick the
    /// two they actually want.
    ///
    /// So a tight deal isn't just a small hand, it's a denial of a decision, and
    /// every tier here deals tight for exactly that reason. Sharp is the only one
    /// that leaves anybody a real choice.
    func preferredDeal(maxCardsDealt: Int) -> Int {
        let low = Rules.minCardsDealt
        let high = max(low, maxCardsDealt)
        let wanted: Int
        switch difficulty {
        case .sharp: wanted = 7     // five, decaying to the sustaining three
        case .ruthless: wanted = 5  // straight to three, and a thin choice
        case .merciless: wanted = 5 // same: starve the table of well choice
        case .cutthroat: wanted = 5 // same
        }
        return min(high, max(low, wanted))
    }

    // MARK: - Pacing

    /// How long the opponent appears to "think". Deliberate pacing sells the
    /// character and keeps the table readable.
    var thinkingDelay: ClosedRange<Double> {
        switch difficulty {
        case .sharp: return 0.6...1.1
        case .ruthless: return 0.8...1.5
        case .merciless: return 0.7...1.3
        // Barely pauses. It has already worked out what it is doing to you.
        case .cutthroat: return 0.55...1.0
        }
    }
}
