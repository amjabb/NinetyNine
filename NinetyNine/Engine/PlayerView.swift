//
//  PlayerView.swift
//  What one player is allowed to know.
//
//  `GameState` is the truth and contains everything: every hand, every well
//  card, the draw pile in order. That is fine when the only other minds at the
//  table are AI in the same process.
//
//  Send it to another device and you have handed an opponent the whole game.
//  Not "they could cheat if they tried" — the cards are simply *there* in the
//  payload, readable by anyone with a proxy.
//
//  So a client never receives `GameState`. It receives one of these: its own
//  hand in full, and for everyone else only what you'd see across a real table —
//  counts, never cards.
//

import Foundation

/// An opponent as seen from across the table.
struct OpponentView: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var isAI: Bool

    /// How many cards they hold. Not *which*.
    var handCount: Int
    /// How many well cards remain unspent. Not *which*.
    var wellCount: Int
    /// How many queens are exiled in front of them. Face down, so a count only.
    var poisonCount: Int

    var handCap: Int
    var owesExtraPlay: Bool
    var isEliminated: Bool
    var eliminationRank: Int?
}

/// The whole game, from one seat.
struct PlayerView: Codable, Sendable {

    // MARK: Yours

    let youID: String
    var yourName: String
    /// Your own hand, in full. This is the only place real cards appear for a
    /// living player.
    ///
    /// **Empty while you're choosing your well.** The deal is face down until
    /// the well is banked — see `wellChoiceCount`. Redacting it here rather than
    /// hiding it in the view is the point of this type: a UI that merely
    /// declined to draw the faces would still have them in memory, and in an
    /// online match would have shipped them over the wire.
    var yourHand: [Card]
    /// How many face-down cards you're choosing your well from. Zero unless it's
    /// your turn to choose.
    var wellChoiceCount: Int
    /// Your well cards are face down even to you — a count, not the cards.
    /// Revealing one early would defeat the entire point of the well.
    var yourWellCount: Int
    /// Your poison pile *is* known to you: you saw each queen as it was exiled.
    var yourPoisonPile: [Card]
    var yourHandCap: Int
    var youOweExtraPlay: Bool
    var youAreEliminated: Bool

    // MARK: The table

    /// In seating order, excluding you.
    var opponents: [OpponentView]
    /// Seating order of every player id including you, so the UI can lay the
    /// table out consistently on every device.
    var seatingOrder: [String]

    var tally: Int
    var direction: Int
    var currentPlayerID: String
    /// Whoever is banking their well right now, or nil once play has begun.
    /// The opening phase runs on its own order, so the UI can't infer this
    /// from `currentPlayerID`.
    var wellChooserID: String?
    var suitLock: SuitLock?
    /// Whether the face-up card counts as an 8 — the UI needs this to grey the
    /// right cards, and getting it wrong here means the table disagrees with the
    /// engine about what's legal.
    var topPlayedAsEight: Bool
    var forcedNegativeNext: Bool
    var pendingNineSuit: Suit?
    var queensArePoisonous: Bool

    /// The discard pile is public — everyone watched every card land.
    var discardPile: [Card]
    /// The draw pile is emphatically *not* public. A count only; sending the
    /// ordered pile would let a client see every future draw.
    var drawPileCount: Int

    var dealerID: String
    var cardsDealt: Int
    var winnerID: String?
    var firstEliminatedID: String?

    var playsRemainingThisTurn: Int
    var turnStartedWithDebt: Bool

    /// A well card that has been revealed. Public once face up — everyone at a
    /// real table would see it.
    var pendingWell: PendingWell?

    var journal: [String]

    // MARK: Derived

    var isYourTurn: Bool { currentPlayerID == youID && winnerID == nil }
    var isOver: Bool { winnerID != nil }
    var topOfDiscard: Card? { discardPile.last }

    var pressure: Double {
        guard tally > 0 else { return 0 }
        return min(1, Double(tally) / 99.0)
    }

    func opponent(id: String) -> OpponentView? { opponents.first { $0.id == id } }
}

// MARK: - Redaction

extension GameState {

    /// Produce the view for one player.
    ///
    /// This is the security boundary of multiplayer. Everything hidden is
    /// reduced to a count *here*, before serialisation — not filtered later in
    /// the UI, where forgetting one field would silently leak cards.
    func view(for playerID: String) -> PlayerView {
        let you = player(id: playerID)

        return PlayerView(
            youID: playerID,
            yourName: you?.name ?? "You",
            // Hidden from its owner during the blind pick — a count, not cards.
            yourHand: wellChooserID == playerID ? [] : (you?.hand ?? []),
            wellChoiceCount: wellChooserID == playerID ? (you?.hand.count ?? 0) : 0,
            yourWellCount: you?.well.count ?? 0,
            yourPoisonPile: you?.poisonPile ?? [],
            yourHandCap: you?.handCap ?? cardsDealt,
            youOweExtraPlay: you?.owesExtraPlay ?? false,
            youAreEliminated: you?.isEliminated ?? false,
            opponents: players
                .filter { $0.id != playerID }
                .map { other in
                    OpponentView(
                        id: other.id,
                        name: other.name,
                        isAI: !other.isHuman,
                        handCount: other.hand.count,
                        wellCount: other.well.count,
                        poisonCount: other.poisonPile.count,
                        handCap: other.handCap,
                        owesExtraPlay: other.owesExtraPlay,
                        isEliminated: other.isEliminated,
                        eliminationRank: other.eliminationRank
                    )
                },
            seatingOrder: players.map(\.id),
            tally: tally,
            direction: direction,
            currentPlayerID: currentPlayer.id,
            wellChooserID: wellChooserID,
            suitLock: suitLock,
            topPlayedAsEight: topPlayedAsEight,
            forcedNegativeNext: forcedNegativeNext,
            pendingNineSuit: pendingNineSuit,
            queensArePoisonous: queensArePoisonous,
            discardPile: discardPile,
            drawPileCount: drawPile.count,
            dealerID: dealerID,
            cardsDealt: cardsDealt,
            winnerID: winnerID,
            firstEliminatedID: firstEliminatedID,
            playsRemainingThisTurn: playsRemainingThisTurn,
            turnStartedWithDebt: turnStartedWithDebt,
            pendingWell: pendingWell,
            journal: journal
        )
    }
}

// MARK: - Legality against a view

extension PlayerView {

    /// The UI needs to shade unplayable cards, and in multiplayer it only has a
    /// `PlayerView` to work from. Rebuilding a minimal `GameState` from the
    /// public facts lets the *same* `Rules` decide, rather than a second
    /// implementation drifting out of sync with the first.
    ///
    /// Only your own cards can be judged this way, which is exactly the set the
    /// UI needs. Nothing hidden is invented — the reconstructed state has empty
    /// opponent hands, and no rule consults them.
    /// Who plays after the current player, skipping anyone knocked out.
    ///
    /// Computed from the seating order and the direction rather than sent, so it
    /// can't disagree with the arrow on the table.
    var nextPlayerID: String? {
        guard !isOver, seatingOrder.count > 1 else { return nil }
        guard let start = seatingOrder.firstIndex(of: currentPlayerID) else { return nil }

        let step = direction >= 0 ? 1 : -1
        var index = start
        for _ in 0..<seatingOrder.count {
            index = ((index + step) % seatingOrder.count + seatingOrder.count) % seatingOrder.count
            let id = seatingOrder[index]
            if id == youID {
                if !youAreEliminated { return id }
            } else if opponent(id: id)?.isEliminated == false {
                return id
            }
        }
        return nil
    }

    /// True while *you* are the one banking cards.
    var youAreChoosingYourWell: Bool { wellChooserID == youID }

    /// Face-down placeholders to draw while choosing. They carry no identity —
    /// the real cards aren't in this view at all.
    var wellChoiceSlots: [Int] { Array(0..<wellChoiceCount) }

    func rulesContext() -> GameState {
        var reconstructed = GameState(
            players: seatingOrder.map { id in
                if id == youID {
                    var me = PlayerState(id: id, name: yourName, kind: .human, handCap: yourHandCap)
                    me.hand = yourHand
                    me.poisonPile = yourPoisonPile
                    // Count only — the identity of an unspent well card is
                    // unknown even to its owner, and no legality check reads it.
                    me.well = Array(repeating: Card(id: -1, rank: .jack, suit: .spades), count: yourWellCount)
                    me.owesExtraPlay = youOweExtraPlay
                    me.isEliminated = youAreEliminated
                    return me
                }
                let other = opponent(id: id)
                var them = PlayerState(
                    id: id,
                    name: other?.name ?? id,
                    kind: (other?.isAI ?? false) ? .ai(.sharp) : .human,
                    handCap: other?.handCap ?? cardsDealt
                )
                them.well = Array(repeating: Card(id: -1, rank: .jack, suit: .spades),
                                  count: other?.wellCount ?? 0)
                them.owesExtraPlay = other?.owesExtraPlay ?? false
                them.isEliminated = other?.isEliminated ?? false
                return them
            },
            currentPlayerIndex: seatingOrder.firstIndex(of: currentPlayerID) ?? 0,
            dealerID: dealerID,
            cardsDealt: cardsDealt
        )
        reconstructed.tally = tally
        reconstructed.direction = direction
        reconstructed.suitLock = suitLock
        reconstructed.topPlayedAsEight = topPlayedAsEight
        reconstructed.forcedNegativeNext = forcedNegativeNext
        reconstructed.pendingNineSuit = pendingNineSuit
        reconstructed.queensArePoisonous = queensArePoisonous
        reconstructed.discardPile = discardPile
        reconstructed.winnerID = winnerID
        reconstructed.playsRemainingThisTurn = playsRemainingThisTurn
        reconstructed.turnStartedWithDebt = turnStartedWithDebt
        reconstructed.pendingWell = pendingWell
        // Only the chooser's identity survives redaction, which is all the
        // rules need: the queue's remaining order is nobody else's business.
        reconstructed.wellSelectionQueue = wellChooserID.map { [$0] } ?? []
        return reconstructed
    }

    /// Cards in your hand that are legal right now.
    var playableCardIDs: Set<Int> {
        let context = rulesContext()
        return Set(yourHand.filter { Rules.isPlayable($0, in: context) }.map(\.id))
    }
}
