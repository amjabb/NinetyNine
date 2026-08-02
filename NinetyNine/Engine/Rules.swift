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
    /// Chosen suit when the effective rank is an 8. Nil together with
    /// `declinesLock` false means "not answered yet".
    var lockSuit: Suit?
    /// An 8 may be played without locking anything — the lock is an option, not
    /// an obligation. Distinguishes "chose no suit" from "hasn't chosen".
    var declinesLock: Bool = false

    init(
        queenAs: Rank? = nil,
        aceValue: AceValue? = nil,
        lockSuit: Suit? = nil,
        declinesLock: Bool = false
    ) {
        self.queenAs = queenAs
        self.aceValue = aceValue
        self.lockSuit = lockSuit
        self.declinesLock = declinesLock
    }

    static let plain = Declaration()
    static func ace(_ value: AceValue) -> Declaration { Declaration(aceValue: value) }
    static func lock(_ suit: Suit) -> Declaration { Declaration(lockSuit: suit) }
    /// An 8 played without naming a suit.
    static let lockNothing = Declaration(declinesLock: true)
    static func queen(
        as rank: Rank,
        aceValue: AceValue? = nil,
        lockSuit: Suit? = nil,
        declinesLock: Bool = false
    ) -> Declaration {
        Declaration(queenAs: rank, aceValue: aceValue, lockSuit: lockSuit, declinesLock: declinesLock)
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
    /// True when an 8 was played *without* naming a suit. Playing an 8 always
    /// resets the lock — declining just resets it to nothing.
    var liftsSuitLock: Bool = false
    var setsForcedNegativeNext: Bool = false
    var isNine: Bool = false
    var completesHundred: Bool = false
    /// Signed change applied to the tally, for the floating "+8" / "−10" chip.
    var tallyDelta: Int
}

// MARK: - Resolver

enum Rules {
    static let ceiling = 99
    static let hundredException = 100

    /// How many cards a player refills to, regardless of how many they were
    /// dealt.
    ///
    /// The deal size is a *starting* position, not a standing allowance: deal
    /// seven and you play down to three, then hold at three.
    ///
    /// Three, not five, and the difference is the whole texture of the game — a
    /// hand of three is barely a hand. There is rarely a safe card *and* a brake
    /// *and* an out, so most turns are a choice between bad options rather than
    /// a search for the best one, and the tally climbs faster because nobody is
    /// sitting on a 10 waiting for the right moment.
    ///
    /// Bonus cards (a survived well) may push a hand above this; refill never
    /// removes cards, it only tops up.
    static let sustainingHandCap = 3

    /// How many of a kind make a Snackoo.
    static let snackooSize = 3

    /// A poisoned queen costs one card of capacity while it sits in the poison
    /// pile. Clearing three of them with a Snackoo gives that capacity back.
    ///
    /// Against a sustaining hand of three this bites hard and deliberately: one
    /// queen and you're down to two, two queens and you're on one for the rest
    /// of the game unless you can clear them. Three queens
    /// down means a hand of two — the floor only exists so a player can never be
    /// left unable to hold a card at all.
    static let poisonedHandCapFloor = 1

    // MARK: What the dealer deals

    /// Cards set aside face-down as the well, chosen by the player from their
    /// own deal.
    static let wellSize = 2

    /// The dealer names a number of cards to deal. **Two of them become the
    /// well**, so the opening hand is `cardsDealt - 2` — deal 7 and you start
    /// with five and play down to three, deal 5 and you start at the sustaining
    /// three straight away.
    ///
    /// This is why the number isn't called "hand size": it stopped being one.
    static func maxCardsDealt(forPlayerCount count: Int) -> Int {
        let uncapped = 52 / max(1, count)
        return max(minCardsDealt, min(12, uncapped))
    }

    /// Two go to the well, so three is the smallest deal that leaves a hand at
    /// all. Anything less and a player opens holding nothing.
    static let minCardsDealt = wellSize + 1

    // MARK: Core resolution

    /// Resolve `card` played by the current player under `declaration`.
    /// Returns the effect, or the specific reason it's illegal.
    static func resolve(
        card: Card,
        declaration: Declaration,
        in state: GameState
    ) -> Result<CardEffect, IllegalReason> {

        // A Queen borrows another rank's value *and* ability. Her printed suit
        // is irrelevant to the lock — see the lock check below.
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
            // Locking is optional. `declinesLock` is how a player says "no suit"
            // — without it we can't tell that apart from not having answered.
            guard declaration.lockSuit != nil || declaration.declinesLock else {
                return .failure(.missingDeclaration("Name a suit to lock, or choose none."))
            }
            delta = forcedNegative ? -8 : 8
            locksSuit = declaration.lockSuit

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

        // Zero is a one-way gate. Going *down* through it is free — a 10 drops
        // the tally below zero from wherever it stands — but climbing back out
        // has to touch exactly 0 on the way.
        //
        // The asymmetry is the point: diving is cheap and getting out is not,
        // so the negatives are somewhere you choose to go and then have to work
        // your way back from.
        if tally < 0 && newTally > 0 {
            return .failure(.mustLandOnZeroFirst(resulting: newTally))
        }

        // Follow the suit, or answer the card. `lockBlocking` is the single
        // definition of what gets past a lock — a Queen, or a card matching the
        // rank of the one face up.
        let blockedBy = lockBlocking(card, in: state)
        if let suit = blockedBy {
            return .failure(.suitLocked(suit))
        }

        // Beating a lock by rank drags it to the suit you played, so the next
        // player is following *your* suit. An 8 is the exception: it names a
        // suit of its own (or declines), and that choice wins.
        var movesLockToOwnSuit = false
        if let lock = state.suitLock,
           card.suit != lock.suit,
           card.rank != .queen,
           effectiveRank != .eight {
            movesLockToOwnSuit = true
        }

        return .success(CardEffect(
            newTally: newTally,
            effectiveRank: effectiveRank,
            effectiveSuit: card.suit,
            reversesDirection: reverses,
            locksSuit: movesLockToOwnSuit ? card.suit : locksSuit,
            liftsSuitLock: effectiveRank == .eight && locksSuit == nil,
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
            consider(.lockNothing)
        case .queen:
            for rank in Rank.allCases where rank != .queen {
                switch rank {
                case .ace:
                    for value in AceValue.allCases { consider(.queen(as: .ace, aceValue: value)) }
                case .eight:
                    for suit in Suit.allCases { consider(.queen(as: .eight, lockSuit: suit)) }
                    consider(.queen(as: .eight, declinesLock: true))
                default:
                    consider(.queen(as: rank))
                }
            }
        default:
            consider(.plain)
        }

        return results
    }

    /// Resolve several cards of the same rank played together.
    ///
    /// Each card is validated *in sequence*, against the tally as it stands after
    /// the ones before it — so three 5s from 90 is illegal because the third
    /// would bust, not because the set as a whole is too big. That's the same
    /// answer as playing them one at a time, which is what makes it fair.
    ///
    /// Each 4 reverses, so they compound: two 4s cancel out and leave the
    /// direction alone, three flip it once. The suit lock is different — it's a
    /// state, not a toggle, so the last 8 in the set simply sets it.
    ///
    /// Queens are excluded — a set of wilds each impersonating something is a
    /// different feature, and a confusing one.
    static func resolveSet(
        cards: [Card],
        declaration: Declaration,
        in state: GameState
    ) -> Result<CardEffect, IllegalReason> {
        guard let first = cards.first else {
            return .failure(.missingDeclaration("No cards selected."))
        }
        guard cards.count > 1 else {
            return resolve(card: first, declaration: declaration, in: state)
        }
        guard first.rank != .queen else {
            return .failure(.missingDeclaration("Queens can't be played as a set."))
        }
        guard cards.allSatisfy({ $0.rank == first.rank }) else {
            return .failure(.missingDeclaration("A set must be all the same rank."))
        }

        var running = state
        var combined: CardEffect?
        var reversals = 0

        for card in cards {
            switch resolve(card: card, declaration: declaration, in: running) {
            case .failure(let reason):
                return .failure(reason)
            case .success(let step):
                if step.reversesDirection { reversals += 1 }
                running.tally = step.newTally
                // Each card in the run lands on the one before it, so a run of
                // 8s keeps the door open for the next 8 in the same run.
                running.topPlayedAsEight = step.effectiveRank == .eight
                if let locked = step.locksSuit {
                    running.suitLock = SuitLock(suit: locked, setByPlayerID: "")
                } else if step.liftsSuitLock {
                    running.suitLock = nil
                }
                // A 9 clears the pending-nine window for the card after it, so
                // the sequence has to carry that too.
                running.pendingNineSuit = step.isNine ? card.suit : nil
                running.forcedNegativeNext = step.setsForcedNegativeNext
                combined = CardEffect(
                    newTally: step.newTally,
                    effectiveRank: step.effectiveRank,
                    effectiveSuit: step.effectiveSuit,
                    // Net parity: an even number of 4s leaves play going the way
                    // it already was.
                    reversesDirection: reversals % 2 == 1,
                    locksSuit: step.locksSuit,
                    liftsSuitLock: step.liftsSuitLock,
                    setsForcedNegativeNext: step.setsForcedNegativeNext,
                    isNine: step.isNine,
                    completesHundred: step.completesHundred,
                    tallyDelta: step.newTally - state.tally
                )
            }
        }
        return combined.map { .success($0) } ?? .failure(.missingDeclaration("No cards selected."))
    }

    /// Ranks the player holds two or more of *and* could legally play together.
    /// Used to decide whether a long press should offer the set at all.
    static func playableSetRanks(for player: PlayerState, in state: GameState) -> [Rank] {
        var counts: [Rank: [Card]] = [:]
        for card in player.hand where card.rank != .queen {
            counts[card.rank, default: []].append(card)
        }
        return Rank.allCases.filter { rank in
            guard let cards = counts[rank], cards.count > 1 else { return false }
            // *Any* run of two or more, not the whole holding. Testing only the
            // full set meant that holding three 7s near the ceiling made the
            // rank un-runnable outright — even though two of them were legal and
            // the player could see it.
            return (2...cards.count).contains { length in
                !legalDeclarations(forSet: Array(cards.prefix(length)), in: state).isEmpty
            }
        }
    }

    /// Whether the suit lock blocks this card outright, judged on its printed
    /// rank alone — which is all the "why can't I play this" paths know before
    /// a declaration has been picked.
    ///
    /// One definition rather than three: `resolve` decides legality, and both
    /// explanation paths used to re-state the rule themselves. They had already
    /// drifted — neither knew about the 8-on-8 exception, so an 8 that could
    /// legally take over a lock was reported as blocked by it.
    static func lockBlocking(_ card: Card, in state: GameState) -> Suit? {
        guard let lock = state.suitLock else { return nil }
        if card.suit == lock.suit { return nil }
        // A Queen is wild for suit as well as rank.
        if card.rank == .queen { return nil }
        // Matching the rank of the card on the table gets you past the lock,
        // whatever suit you're holding — and drags the lock over to your suit.
        // That's what makes a lock survivable: you follow the suit *or* you
        // answer the card, exactly as you would in any matching game.
        if card.rank == topPlayedRank(in: state) { return nil }
        return lock.suit
    }

    /// The rank the face-up card counts as, which is what a rank match is
    /// measured against. A Queen played as an 8 is an 8 for this purpose, so the
    /// next player can answer her with an 8.
    static func topPlayedRank(in state: GameState) -> Rank? {
        // The flag answers first, and without needing the pile. A run resolves
        // against a running state that tracks what the last card *counted as*
        // but never appends to the discard pile, so asking the pile first made
        // the second 8 of a run of 8s illegal under the lock the first one had
        // just set.
        if state.topPlayedAsEight { return .eight }
        return state.topOfDiscard?.rank
    }

    /// Why a run of these cards can't be played, in the player's words.
    ///
    /// Tries the declarations the rank could take and reports what the engine
    /// actually objected to. The UI used to guess — it assumed any refusal meant
    /// the tally, and told a player holding two off-suit sixes under a lock that
    /// they'd bust, which is both wrong and unhelpful.
    static func blockingReasonForSet(_ cards: [Card], in state: GameState) -> IllegalReason? {
        guard let first = cards.first else { return nil }
        guard first.rank != .queen else {
            return .missingDeclaration("Queens can't be run together.")
        }
        // Checked first, and on every card in the run: a lock holds whatever
        // declaration you pick, whereas a bust depends on the choice — and
        // `resolve` tests the tally before the suit, so leaving this to the
        // resolver reported an arithmetic complaint about a card that was never
        // going to be legal anyway.
        for card in cards {
            if let suit = lockBlocking(card, in: state) { return .suitLocked(suit) }
        }
        var reason: IllegalReason?
        for declaration in candidateDeclarations(for: first, in: state) {
            switch resolveSet(cards: cards, declaration: declaration, in: state) {
            case .success: return nil
            case .failure(let failure): reason = reason ?? failure
            }
        }
        return reason
    }

    /// Every legal way to play this set together.
    static func legalDeclarations(forSet cards: [Card], in state: GameState) -> [Declaration] {
        guard let first = cards.first, first.rank != .queen else { return [] }
        return candidateDeclarations(for: first, in: state).filter { declaration in
            if case .success = resolveSet(cards: cards, declaration: declaration, in: state) {
                return true
            }
            return false
        }
    }

    /// Every declaration a run of this rank could be played under, legal or not.
    /// Shared by the "what can I do" and "why can't I" paths so the two can't
    /// drift apart.
    private static func candidateDeclarations(for card: Card, in state: GameState) -> [Declaration] {
        switch card.rank {
        case .ace: return AceValue.allCases.map { .ace($0) }
        case .eight: return Suit.allCases.map { .lock($0) } + [.lockNothing]
        default: return [.plain]
        }
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
        if let suit = lockBlocking(card, in: state) { return .suitLocked(suit) }
        var fallback: IllegalReason?
        let candidates: [Declaration]
        switch card.rank {
        case .ace: candidates = AceValue.allCases.map { .ace($0) }
        case .eight: candidates = Suit.allCases.map { .lock($0) } + [.lockNothing]
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
