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
            let declarations = Rules.legalDeclarations(for: pending.card, in: state)
            if let best = bestDeclaration(for: pending.card, among: declarations, player: player, state: state) {
                return AIMove(
                    kind: .play(cardID: pending.card.id, declaration: best.declaration),
                    rationale: "rides the well card out"
                )
            }
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

    // MARK: - Pacing

    /// How long the opponent appears to "think". Deliberate pacing sells the
    /// character and keeps the table readable.
    var thinkingDelay: ClosedRange<Double> {
        switch difficulty {
        case .casual: return 0.45...0.85
        case .sharp: return 0.6...1.1
        case .ruthless: return 0.8...1.5
        }
    }
}
