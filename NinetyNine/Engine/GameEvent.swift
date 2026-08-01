//
//  GameEvent.swift
//  What just happened, in the order it happened.
//
//  Every engine action returns a list of these. The presentation layer replays
//  them as a timeline — card flight, tally tick, haptic, sound, banner — which
//  keeps *all* animation sequencing out of the engine and means the UI never
//  has to diff two states to guess what changed.
//

import Foundation

enum GameEvent: Equatable, Sendable {
    // Setup
    case dealt(cardsDealt: Int)

    // Ordinary play
    case cardPlayed(card: Card, by: String, effect: CardEffect)
    case tallyChanged(from: Int, to: Int)
    case directionReversed(clockwise: Bool)
    case suitLocked(Suit, by: String)
    case suitLockLifted
    case nineSlammed(to: Int)
    case hundredReached
    case forcedNegativeConsumed

    // Choosing a well
    case wellChosen(by: String, count: Int)
    case wellSelectionFinished

    // Drawing
    case drewCards(count: Int, by: String)
    case drawPileReshuffled

    // Queens
    /// Carries the actual card so the moment can show the queen that did it —
    /// this is the one turn in the game where the state changes for everybody at
    /// once, and it needs to land as an event, not a line of text.
    case queensBecamePoisonous(card: Card, trigger: String)
    case queenPoisoned(card: Card, owner: String, newHandCap: Int)

    // Snackoo
    case snackoo(by: String, kind: SnackooKind)

    // The well
    /// The two face-down well cards were shuffled before one was picked. Public
    /// — the whole table should see somebody stalling over it.
    case wellShuffled(by: String)
    case wellRevealed(card: Card, by: String, playable: Bool)
    case wellPlayed(card: Card, by: String)
    case wellBonusDrawn(count: Int, by: String)

    // Turn flow
    case turnSkipped(by: String)
    case turnAdvanced(to: String, owesTwo: Bool)
    case extraPlayOwed(by: String)

    // Endgame
    case playerEliminated(id: String, reason: EliminationReason, rank: Int)
    case gameWon(by: String)

    enum SnackooKind: Equatable, Sendable {
        case threeOfAKind(Rank)
        case threeQueens
    }

    enum EliminationReason: Equatable, Sendable {
        case unplayableWellCard(Card)
        case strandedWithoutWell
        /// Left the match. Only reachable in multiplayer — see Docs/MULTIPLAYER.md
        /// for why quitting is modelled as elimination rather than as a new state.
        case forfeited

        var explanation: String {
            switch self {
            case .unplayableWellCard(let card):
                return "The well gave up the \(card.accessibleName) — unplayable."
            case .strandedWithoutWell:
                return "No legal play, and the well is dry."
            case .forfeited:
                return "Left the match."
            }
        }
    }

    /// Events that deserve a full-screen moment rather than a quiet animation.
    var isDramatic: Bool {
        switch self {
        case .nineSlammed, .hundredReached, .wellRevealed, .playerEliminated,
             .gameWon, .queensBecamePoisonous, .snackoo:
            return true
        default:
            return false
        }
    }
}
