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

        // Casual play is deliberately imperfect: it picks from the top of a
        // noisy ranking rather than always finding the best line.
        if difficulty == .casual {
            var rng = SystemRandomNumberGenerator()
            scored = scored.map { ($0.0, $0.1 + Double.random(in: -14...14, using: &rng)) }
        }

        scored.sort { $0.1 > $1.1 }
        var winner = scored[0].0
        winner.rationale = rationale(for: winner, player: player, state: state)
        return winner
    }

    // MARK: - Scoring

    private func score(_ candidate: Candidate, player: PlayerState, state: GameState) -> Double {
        let rank = candidate.effect.effectiveRank
        var score = 0.0

        // Headroom under the ceiling is the currency of this game.
        score += Double(Rules.ceiling - candidate.effect.newTally)

        // A negative tally is a fortress — everyone downstream is squeezed.
        if candidate.effect.newTally < 0 { score += difficulty == .casual ? 4 : 14 }
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
                score += difficulty == .ruthless ? 55 : 25
            } else {
                // Still worth it as a finisher if only one opponent stands and
                // their well is spent.
                let opponents = state.activePlayers.filter { $0.id != player.id }
                let allWellsDry = opponents.allSatisfy { $0.well.isEmpty }
                score += allWellsDry && difficulty != .casual ? 20 : -35
            }
        }

        // The suit lock is strongest when we're long in the suit we name.
        if rank == .eight, let locked = candidate.declaration.lockSuit {
            let support = player.hand.filter { $0.suit == locked && $0.id != candidate.card.id }.count
            score += 4 + Double(support) * (difficulty == .ruthless ? 5 : 3)
            // Ruthless play prefers locking a suit it is long in *and* that is
            // statistically scarce, squeezing everyone else.
            if difficulty == .ruthless && support >= 3 { score += 10 }
        }

        // Brakes (10s, Aces) are worth hoarding while the tally is low; face
        // cards are dead weight and should be shed early.
        let isBrake = candidate.card.rank == .ten || candidate.card.rank == .ace
        if state.tally < 45 {
            if isBrake { score -= difficulty == .casual ? 2 : 9 }
            if candidate.card.rank == .jack || candidate.card.rank == .king { score += 3 }
        } else if state.tally > 80 && isBrake {
            // Late on, a brake is exactly the right card.
            score += 6
        }

        // A Queen is the most flexible card in the deck — spending it on a
        // routine play wastes it (and holding it risks poisoning; sharp play
        // accepts that trade, ruthless play weighs the poison risk).
        if candidate.card.rank == .queen {
            score -= difficulty == .ruthless ? 16 : 8
            if state.queensArePoisonous { score += 20 } // dump it before it's exiled
        }

        // Reversing is a real weapon: it can hand the squeeze back to the player
        // who just built it.
        if rank == .four && state.activePlayers.count > 2 {
            score += state.tally > 70 ? 8 : 2
        }

        // Don't leave ourselves with an unplayable hand: peek one step ahead and
        // penalise lines that strand us. Sharp and ruthless only — this is the
        // main thing that separates them from casual.
        if difficulty != .casual {
            score += Double(lookaheadBonus(candidate, player: player, state: state))
        }

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
        var bonus = Int(ratio * (difficulty == .ruthless ? 26 : 16))
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
        case .casual:
            // Impulsive: takes the gamble more often than it should.
            return odds > 0.35
        case .sharp:
            return odds > 0.55
        case .ruthless:
            // Weighs the board: with a tight tally a skip just defers the
            // problem, so it accepts worse odds when the squeeze is on.
            let squeezed = state.tally > 85 || state.suitLock != nil
            return odds > (squeezed ? 0.45 : 0.6)
        case .merciless:
            // Compares the two deaths rather than picking a threshold. A skip
            // costs two plays next turn, which on a board this tight is often
            // worse than the coin flip — so the bar moves with how survivable
            // the *next* turn looks, not with how the tally feels.
            let debtSurvival = survivalAfterSkipping(player: player, state: state)
            return odds > debtSurvival
        }
    }

    /// Only churn a three-of-a-kind when it actually helps: a hand full of
    /// duplicates is a hand with few options.
    private func snackooWorthTaking(player: PlayerState, state: GameState) -> Rank? {
        let ranks = Rules.snackooRanksInHand(for: player)
        guard let rank = ranks.first else { return nil }
        if difficulty == .casual { return rank } // always fires — it's fun and free
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
        case .casual: return Array(0..<size)                       // off the top
        case .sharp: return Array((dealtCount - size)..<dealtCount) // off the bottom
        case .ruthless:                                             // from the middle
            let start = max(0, (dealtCount - size) / 2)
            return Array(start..<(start + size))
        case .merciless:                                            // off the end
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
    /// So a tight deal isn't just a small hand, it's a denial of a decision.
    /// Ruthless deals tight for exactly that reason; casual deals generously
    /// because it's more fun that way.
    func preferredDeal(maxCardsDealt: Int) -> Int {
        let low = Rules.minCardsDealt
        let high = max(low, maxCardsDealt)
        let wanted: Int
        switch difficulty {
        case .casual: wanted = 9    // a cushion of seven, and a real pick
        case .sharp: wanted = 7     // five, decaying to the sustaining three
        case .ruthless: wanted = 5  // straight to three, and a thin choice
        case .merciless: wanted = 5 // same: starve the table of well choice
        }
        return min(high, max(low, wanted))
    }

    // MARK: - Pacing

    /// How long the opponent appears to "think". Deliberate pacing sells the
    /// character and keeps the table readable.
    var thinkingDelay: ClosedRange<Double> {
        switch difficulty {
        case .casual: return 0.45...0.85
        case .sharp: return 0.6...1.1
        case .ruthless: return 0.8...1.5
        case .merciless: return 0.7...1.3
        }
    }
}
