//
//  Rules.swift
//  Pure legality + effect calculation. Nothing here mutates state.
//
//  Both the validator and the applier go through `Rules.resolve`, so a card
//  can never be *played* in a way it couldn't be *validated* — there is
//  exactly one implementation of the rules.
//
//  See Docs/RULES.md for the rulebook and Docs/INTERPRETATIONS.md for the
//  handful of places where the written rules needed a judgement call.
//

import Foundation

// MARK: - Declaration

enum AceValue: Int, Codable, CaseIterable, Hashable, Sendable {
    case one = 1
    case eleven = 11
}

/// The flexible choices a card may require from its player: an Ace's value, an
/// 8's locked suit, and the rank a Queen impersonates. Flat storage keeps
/// exhaustive enumeration (used by the AI and by the UI's legality shading)
/// straightforward.
struct Declaration: Codable, Hashable, Sendable {
    /// When the played card is a Queen, the rank it is being played as.
    var queenAs: Rank?
    /// Chosen value when the effective rank is an Ace.
    var aceValue: AceValue?
    /// Chosen suit when the effective rank is an 8.
    var lockSuit: Suit?

    init(queenAs: Rank? = nil, aceValue: AceValue? = nil, lockSuit: Suit? = nil) {
        self.queenAs = queenAs
        self.aceValue = aceValue
        self.lockSuit = lockSuit
    }

    static let plain = Declaration()
    static func ace(_ value: AceValue) -> Declaration { Declaration(aceValue: value) }
    static func lock(_ suit: Suit) -> Declaration { Declaration(lockSuit: suit) }
    static func queen(as rank: Rank, aceValue: AceValue? = nil, lockSuit: Suit? = nil) -> Declaration {
        Declaration(queenAs: rank, aceValue: aceValue, lockSuit: lockSuit)
    }
}

// MARK: - Illegality reasons

/// Why a card can't be played. Each case carries what the UI needs to explain
/// itself in plain language — players should never be told just "invalid".
enum IllegalReason: Error, Equatable, Sendable {
    case wouldExceed99(resulting: Int)
    case suitLocked(Suit)
    case nineWhileNegative
    case nineInForcedNegativeSlot
    case tenInForcedNegativeSlot
    case mustLandOnZeroFirst(resulting: Int)
    case cannotGoNegativeExceptFromZero(resulting: Int)
    case missingDeclaration(String)
    case cardNotInHand

    var explanation: String {
        switch self {
        case .wouldExceed99(let resulting):
            return "That would push the tally to \(resulting) — over 99."
        case .suitLocked(let suit):
            return "The suit is locked to \(suit.displayName)."
        case .nineWhileNegative:
            return "A 9 can't be played while the tally is negative."
        case .nineInForcedNegativeSlot:
            return "A 9 can't be played in the forced-negative slot."
        case .tenInForcedNegativeSlot:
            return "A 10 is already negative — it can't take the forced-negative slot."
        case .mustLandOnZeroFirst(let resulting):
            return "From a negative tally you must land exactly on 0 first — that lands on \(resulting)."
        case .cannotGoNegativeExceptFromZero(let resulting):
            return "You can only dip below zero from a tally of exactly 0 — that lands on \(resulting)."
        case .missingDeclaration(let what):
            return what
        case .cardNotInHand:
            return "That card isn't in your hand."
        }
    }
}

// MARK: - Resolved effect

/// Everything that happens as a consequence of a legal play. Produced once and
/// then handed to the applier, so validation and application can't drift.
struct CardEffect: Equatable, Sendable {
    var newTally: Int
    /// The rank actually in force (a Queen's impersonation, or the card's own).
    var effectiveRank: Rank
    /// The card's real suit — what suit-lock legality is judged against, even
    /// for a Queen impersonating an 8.
    var effectiveSuit: Suit
    var reversesDirection: Bool = false
    var locksSuit: Suit?
    var setsForcedNegativeNext: Bool = false
    var isNine: Bool = false
    var completesHundred: Bool = false
    /// Signed change applied to the tally, for the floating "+8" / "−10" chip.
    var tallyDelta: Int
}

// MARK: - Resolver

enum Rules {
    /// The rulebook says a 10 may be played "to send the tally negative" at the
    /// start of play and "any time the tally returns to exactly 0". Read
    /// strictly, that forbids dropping below zero from a mid-range tally (e.g.
    /// 8 → −2). We enforce that reading; flip this to `false` to allow going
    /// negative from any tally.
    static let negativeEntryRequiresZero = true

    static let ceiling = 99
    static let hundredException = 100

    /// How many cards a player refills to, regardless of how many they were
    /// dealt.
    ///
    /// The deal size is a *starting* position, not a standing allowance: deal
    /// seven and you play down to five, then hold at five. The rulebook confirms
    /// it — poisoned queens drop the cap "5 → 4 → 3", a sequence that only makes
    /// sense if the base is five.
    ///
    /// Bonus cards (a survived well) may push a hand above this; refill never
    /// removes cards, it only tops up.
    static let sustainingHandCap = 5

    /// A poisoned queen permanently costs one card of capacity, to this floor.
    static let poisonedHandCapFloor = 3

    // MARK: Hand-size limits

    /// Each player needs `handSize` cards plus a 2-card well, and the dealer may
    /// spend the whole deck: players * (handSize + 2) <= 52.
    static func maxHandSize(forPlayerCount count: Int) -> Int {
        let uncapped = (52 / max(1, count)) - 2
        return max(minHandSize, min(12, uncapped))
    }

    static let minHandSize = 5

    // MARK: Core resolution

    /// Resolve `card` played by the current player under `declaration`.
    /// Returns the effect, or the specific reason it's illegal.
    static func resolve(
        card: Card,
        declaration: Declaration,
        in state: GameState
    ) -> Result<CardEffect, IllegalReason> {

        // A Queen borrows another rank's value *and* ability, but keeps its own
        // suit for suit-lock purposes.
        let effectiveRank: Rank
        if card.rank == .queen {
            guard let impersonated = declaration.queenAs, impersonated != .queen else {
                return .failure(.missingDeclaration("Name the card this Queen is copying."))
            }
            effectiveRank = impersonated
        } else {
            effectiveRank = card.rank
        }

        let tally = state.tally
        let forcedNegative = state.forcedNegativeNext

        var delta: Int?
        var absolute: Int?
        var reverses = false
        var locksSuit: Suit?
        var isNine = false

        switch effectiveRank {
        case .ace:
            guard let aceValue = declaration.aceValue else {
                return .failure(.missingDeclaration("Choose whether this Ace counts as 1 or 11."))
            }
            delta = forcedNegative ? -aceValue.rawValue : aceValue.rawValue

        case .two, .three, .five, .six, .seven:
            let value = Int(effectiveRank.rawValue) ?? 0
            delta = forcedNegative ? -value : value

        case .four:
            delta = 0
            reverses = true

        case .eight:
            guard let suit = declaration.lockSuit else {
                return .failure(.missingDeclaration("Name the suit to lock."))
            }
            delta = forcedNegative ? -8 : 8
            locksSuit = suit

        case .nine:
            isNine = true
            if tally < 0 { return .failure(.nineWhileNegative) }
            if forcedNegative { return .failure(.nineInForcedNegativeSlot) }
            absolute = ceiling

        case .ten:
            if forcedNegative { return .failure(.tenInForcedNegativeSlot) }
            delta = -10

        case .jack:
            delta = 0

        case .king:
            delta = forcedNegative ? -10 : 10

        case .queen:
            // Unreachable: a Queen always resolves to another rank above.
            return .failure(.missingDeclaration("Name the card this Queen is copying."))
        }

        let newTally = absolute ?? (tally + (delta ?? 0))

        // The lone 99 → 100 exception: the Ace matching the suit of a 9 that was
        // *the immediately preceding card*, played as a 1.
        let completesHundred =
            effectiveRank == .ace &&
            declaration.aceValue == .one &&
            tally == ceiling &&
            state.pendingNineSuit == card.suit &&
            newTally == hundredException

        if newTally > ceiling && !completesHundred {
            return .failure(.wouldExceed99(resulting: newTally))
        }

        // Climbing out of the negatives has to touch exactly 0 on the way.
        if tally < 0 && newTally > 0 {
            return .failure(.mustLandOnZeroFirst(resulting: newTally))
        }

        // Dipping below zero is only available from a standing start of 0.
        if negativeEntryRequiresZero && newTally < 0 && tally > 0 {
            return .failure(.cannotGoNegativeExceptFromZero(resulting: newTally))
        }

        // Suit lock is judged on the card's *printed* suit.
        if let lock = state.suitLock, card.suit != lock.suit {
            return .failure(.suitLocked(lock.suit))
        }

        return .success(CardEffect(
            newTally: newTally,
            effectiveRank: effectiveRank,
            effectiveSuit: card.suit,
            reversesDirection: reverses,
            locksSuit: locksSuit,
            setsForcedNegativeNext: newTally == hundredException,
            isNine: isNine,
            completesHundred: completesHundred,
            tallyDelta: newTally - tally
        ))
    }

    // MARK: Enumeration

    /// Every legal way to play `card` right now, in a stable order suitable for
    /// presenting as choices. Empty means the card is dead this turn.
    static func legalDeclarations(for card: Card, in state: GameState) -> [Declaration] {
        var results: [Declaration] = []

        func consider(_ declaration: Declaration) {
            if case .success = resolve(card: card, declaration: declaration, in: state) {
                results.append(declaration)
            }
        }

        switch card.rank {
        case .ace:
            for value in AceValue.allCases { consider(.ace(value)) }
        case .eight:
            for suit in Suit.allCases { consider(.lock(suit)) }
        case .queen:
            for rank in Rank.allCases where rank != .queen {
                switch rank {
                case .ace:
                    for value in AceValue.allCases { consider(.queen(as: .ace, aceValue: value)) }
                case .eight:
                    for suit in Suit.allCases { consider(.queen(as: .eight, lockSuit: suit)) }
                default:
                    consider(.queen(as: rank))
                }
            }
        default:
            consider(.plain)
        }

        return results
    }

    static func isPlayable(_ card: Card, in state: GameState) -> Bool {
        !legalDeclarations(for: card, in: state).isEmpty
    }

    /// Does this player have any legal play at all? Decides whether they're
    /// "stuck" (well/skip unlocked) or obliged to play.
    static func hasLegalPlay(playerID: String, in state: GameState) -> Bool {
        guard let player = state.player(id: playerID) else { return false }
        return player.hand.contains { isPlayable($0, in: state) }
    }

    /// The reason a specific card is dead, for the UI's tap-on-illegal-card
    /// explanation. Returns the most informative failure across all
    /// declarations (a card blocked by the suit lock reports the lock, not an
    /// arithmetic complaint about one arbitrary declaration).
    static func blockingReason(for card: Card, in state: GameState) -> IllegalReason? {
        if let lock = state.suitLock, card.suit != lock.suit {
            return .suitLocked(lock.suit)
        }
        var fallback: IllegalReason?
        let candidates: [Declaration]
        switch card.rank {
        case .ace: candidates = AceValue.allCases.map { .ace($0) }
        case .eight: candidates = Suit.allCases.map { .lock($0) }
        case .queen: candidates = Rank.allCases.filter { $0 != .queen }.map { rank in
            switch rank {
            case .ace: return .queen(as: .ace, aceValue: .one)
            case .eight: return .queen(as: .eight, lockSuit: card.suit)
            default: return .queen(as: rank)
            }
        }
        default: candidates = [.plain]
        }
        for declaration in candidates {
            switch resolve(card: card, declaration: declaration, in: state) {
            case .success: return nil
            case .failure(let reason): fallback = fallback ?? reason
            }
        }
        return fallback
    }

    // MARK: Snackoo detection

    /// Ranks the player holds three-or-more of in hand (Queens excluded — a
    /// held Queen's route out is the poison pile, not a hand Snackoo).
    static func snackooRanksInHand(for player: PlayerState) -> [Rank] {
        var counts: [Rank: Int] = [:]
        for card in player.hand where card.rank != .queen {
            counts[card.rank, default: 0] += 1
        }
        return Rank.allCases.filter { (counts[$0] ?? 0) >= 3 }
    }

    static func canSnackooPoison(_ player: PlayerState) -> Bool {
        player.poisonPile.count >= 3
    }

    /// Does this card complete a three-of-a-kind with two already in hand?
    ///
    /// Used for the well rescue: a revealed well card that can't be played would
    /// normally eliminate its owner, but if it's the third of a rank they can
    /// Snackoo out of it instead. Queens are excluded for the same reason they
    /// are excluded from a hand Snackoo — their route out is the poison pile.
    static func rankCompletedInHand(by card: Card, for player: PlayerState) -> Rank? {
        guard card.rank != .queen else { return nil }
        let matching = player.hand.filter { $0.rank == card.rank }.count
        return matching >= 2 ? card.rank : nil
    }
}
