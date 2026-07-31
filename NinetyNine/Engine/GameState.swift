//
//  GameState.swift
//  The complete, serialisable state of one game of 99, plus read-only queries.
//
//  GameState is a value type on purpose: the presentation layer keeps the
//  previous snapshot around to diff against, which is what drives the
//  card-flight and tally animations.
//

import Foundation

// MARK: - Player

struct PlayerState: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var kind: PlayerKind

    /// Cards the player can see and play from.
    var hand: [Card] = []
    /// The two face-down lifelines. Shrinks as they're spent.
    var well: [Card] = []
    /// Queens exiled face-down in front of the player.
    var poisonPile: [Card] = []

    /// Personal hand-size ceiling. Drops permanently with each poisoned queen.
    var handCap: Int
    /// Set when the player skips; makes their *next* turn cost two plays.
    var owesExtraPlay: Bool = false

    var isEliminated: Bool = false
    /// 1 for the first player knocked out, 2 for the second, and so on.
    var eliminationRank: Int?

    var isHuman: Bool { kind == .human }

    enum PlayerKind: Codable, Hashable, Sendable {
        case human
        case ai(Difficulty)

        var difficulty: Difficulty? {
            if case .ai(let d) = self { return d }
            return nil
        }
    }
}

// MARK: - Difficulty

enum Difficulty: String, Codable, CaseIterable, Hashable, Sendable {
    case casual
    case sharp
    case ruthless

    var displayName: String {
        switch self {
        case .casual: return "Casual"
        case .sharp: return "Sharp"
        case .ruthless: return "Ruthless"
        }
    }

    var blurb: String {
        switch self {
        case .casual: return "Plays reasonably, but misses the killer line."
        case .sharp: return "Reads the table and defends its margin."
        case .ruthless: return "Hoards brakes, weaponises the lock, sets traps."
        }
    }
}

// MARK: - Suit lock

struct SuitLock: Codable, Hashable, Sendable {
    var suit: Suit
    /// Who set (or last renamed) it — used for the on-table attribution line.
    var setByPlayerID: String
}

// MARK: - Pending well reveal

/// A well card that has been turned face up and is awaiting its declaration.
/// Held in state (rather than in the view) so the reveal survives a
/// backgrounding and can never be silently dropped.
struct PendingWell: Codable, Hashable, Sendable {
    var playerID: String
    var card: Card
    var isPlayable: Bool
    /// Set when the card is *unplayable* but completes a three-of-a-kind with
    /// the player's hand. An unplayable well card normally ends the game for its
    /// owner — this is the one way out, and it must be offered before they're
    /// told they've lost.
    var snackooRank: Rank?
}

// MARK: - Game state

struct GameState: Codable, Sendable {
    var players: [PlayerState]
    /// +1 clockwise, -1 counter-clockwise. Flipped by a 4.
    var direction: Int = 1
    var currentPlayerIndex: Int

    var tally: Int = 0
    var discardPile: [Card] = []
    var drawPile: [Card] = []

    var suitLock: SuitLock?
    /// True in the single slot right after the tally hits 100.
    var forcedNegativeNext: Bool = false
    /// Suit of a 9 played as the immediately-previous card — the only window
    /// in which the 99 → 100 Ace exception can fire.
    var pendingNineSuit: Suit?

    var queensArePoisonous: Bool = false

    var dealerID: String
    /// What the dealer called. Two of these become each player's well, so the
    /// opening hand is `cardsDealt - Rules.wellSize`.
    var cardsDealt: Int
    /// Players who still have to bank two cards as their well, in the order
    /// they choose. Non-empty only at the very start — play can't begin until
    /// everyone has a well.
    var wellSelectionQueue: [String] = []
    var firstEliminatedID: String?
    var winnerID: String?

    /// Plays the current player still owes this turn (2 when repaying a skip).
    var playsRemainingThisTurn: Int = 1
    /// True when this turn began with a skip debt — such a turn may not skip
    /// again (prevents infinite skip loops).
    var turnStartedWithDebt: Bool = false

    var pendingWell: PendingWell?

    /// Human-readable play-by-play, newest last.
    var journal: [String] = []

    // MARK: Queries

    var currentPlayer: PlayerState { players[currentPlayerIndex] }

    /// True while wells are still being chosen. Nothing else may happen yet.
    var isChoosingWells: Bool { !wellSelectionQueue.isEmpty }

    /// Whoever is picking their well right now.
    var wellChooserID: String? { wellSelectionQueue.first }

    var activePlayers: [PlayerState] { players.filter { !$0.isEliminated } }

    var isOver: Bool { winnerID != nil }

    func player(id: String) -> PlayerState? { players.first { $0.id == id } }

    func index(of playerID: String) -> Int? { players.firstIndex { $0.id == playerID } }

    var topOfDiscard: Card? { discardPile.last }

    /// Cards left to draw before a reshuffle becomes necessary.
    var effectiveDrawCount: Int { drawPile.count + max(0, discardPile.count - 1) }

    /// How close the tally is to the 99 ceiling, 0...1. Drives the gauge's
    /// colour ramp and the ambient tension of the table.
    var pressure: Double {
        guard tally > 0 else { return 0 }
        return min(1, Double(tally) / 99.0)
    }
}
