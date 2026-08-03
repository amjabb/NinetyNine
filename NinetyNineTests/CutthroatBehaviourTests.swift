//
//  CutthroatBehaviourTests.swift
//  The four things the top tier is supposed to actually do.
//
//  Win rate is the verdict on a tier, but it's a blunt one: a change can be
//  right and still vanish into the noise because the situation it applies to
//  comes up twice a game. These pin the behaviours directly, so "it never
//  presses to 99" can be answered with a board rather than a percentage.
//

import XCTest
@testable import NinetyNine

final class CutthroatBehaviourTests: XCTestCase {

    private func engine(_ kinds: [PlayerState.PlayerKind]) throws -> GameEngine {
        let seats = kinds.enumerated().map { index, kind in
            (id: "p\(index)", name: "P\(index)", kind: kind)
        }
        let game = try GameEngine(seats: seats, dealerIndex: seats.count - 1, cardsDealt: 7, seed: 7)
        while let chooser = game.state.wellChooserID {
            try game.chooseWell(slots: [0, 1], by: chooser)
        }
        return game
    }

    private func card(_ rank: Rank, _ suit: Suit) -> Card {
        Deck.standard().first { $0.rank == rank && $0.suit == suit }!
    }

    /// Put a known board in front of a known hand.
    private func board(
        hand: [Card], tally: Int, seat: Int = 0,
        lock: Suit? = nil,
        nextOwesExtraPlay: Bool = false,
        nextSkippedUnder: Suit? = nil,
        nextWellSpent: Bool = false
    ) throws -> GameEngine {
        let game = try engine([.ai(.cutthroat), .ai(.sharp), .ai(.sharp)])
        var state = game.state
        state.currentPlayerIndex = seat
        state.tally = tally
        state.players[seat].hand = hand
        state.suitLock = lock.map { SuitLock(suit: $0, setByPlayerID: "p2") }
        let next = (seat + 1) % state.players.count
        state.players[next].owesExtraPlay = nextOwesExtraPlay
        state.players[next].skippedUnderLock = nextSkippedUnder
        if nextWellSpent { state.players[next].well = [] }
        state.playsRemainingThisTurn = 1
        state.turnStartedWithDebt = false
        game._replaceStateForTesting(state)
        return game
    }

    /// 1 — "it almost never puts the tally to 99 to pressure other players".
    ///
    /// Holding a 9 and a spare card at a quiet tally, against a player repaying a
    /// skip debt with no well left: pinning the board is the kill, and the tier
    /// below declines it because a low tally scores better.
    /// The second card is a 10 on purpose. Holding a 3 instead, refusing to pin
    /// is the *right* move — a board you can't answer yourself is not a weapon,
    /// it's a delayed suicide, and the first version of this test asserted that
    /// the AI should walk into one.
    func testPinsTheBoardAtNinetyNineAgainstADebtPayer() throws {
        let hand = [card(.nine, .spades), card(.ten, .diamonds)]
        let game = try board(
            hand: hand, tally: 20,
            nextOwesExtraPlay: true, nextWellSpent: true
        )
        let move = try XCTUnwrap(AIPlayer(difficulty: .cutthroat).nextMove(for: "p0", engine: game))
        guard case .play(let cardID, _) = move.kind else {
            return XCTFail("expected a play, got \(move.kind)")
        }
        XCTAssertEqual(cardID, hand[0].id, "should pin the board at 99, played \(move.rationale)")
    }

    /// 2 — "it almost never stacks an eight after the next player has already
    /// skipped on a suit to pressure them to go to the well".
    /// The spare card is a Queen so that either lock leaves this hand playable.
    /// With a heart spare, naming diamonds strands the AI on its own lock, and
    /// declining is correct — which is what it did, and what the first version
    /// of this test wrongly called a bug.
    func testRelocksTheSuitTheNextPlayerAlreadyFailedToFollow() throws {
        let hand = [card(.eight, .clubs), card(.queen, .spades)]
        let game = try board(
            hand: hand, tally: 30,
            nextOwesExtraPlay: true, nextSkippedUnder: .diamonds
        )
        let move = try XCTUnwrap(AIPlayer(difficulty: .cutthroat).nextMove(for: "p0", engine: game))
        guard case .play(let cardID, let declaration) = move.kind else {
            return XCTFail("expected a play, got \(move.kind)")
        }
        XCTAssertEqual(cardID, hand[0].id, "should play the 8")
        XCTAssertEqual(
            declaration.lockSuit, .diamonds,
            "should re-lock the suit they already showed they haven't got"
        )
    }

    /// 3 — "it plays its 'good' cards (i.e. 4s, jacks, 10s) way too early".
    ///
    /// At a quiet tally with an ordinary card that does the same job, the out
    /// should stay in hand.
    func testKeepsItsOutsWhenAnOrdinaryCardWouldDo() throws {
        let outs = [card(.jack, .spades), card(.four, .hearts), card(.ten, .clubs)]
        for out in outs {
            let hand = [out, card(.three, .diamonds)]
            let game = try board(hand: hand, tally: 18)
            let move = try XCTUnwrap(AIPlayer(difficulty: .cutthroat).nextMove(for: "p0", engine: game))
            guard case .play(let cardID, _) = move.kind else {
                return XCTFail("expected a play, got \(move.kind)")
            }
            XCTAssertEqual(
                cardID, hand[1].id,
                "should spend the 3 and keep the \(out.rank.displayName) — played \(move.rationale)"
            )
        }
    }

    /// And the other half of that: when the board is genuinely tight, the out is
    /// exactly what it's for. A tier that hoards into its own elimination has
    /// just swapped one bad habit for another.
    func testSpendsItsOutsWhenTheBoardIsTight() throws {
        let hand = [card(.jack, .spades), card(.seven, .diamonds)]
        let game = try board(hand: hand, tally: 95)
        let move = try XCTUnwrap(AIPlayer(difficulty: .cutthroat).nextMove(for: "p0", engine: game))
        guard case .play(let cardID, _) = move.kind else {
            return XCTFail("expected a play, got \(move.kind)")
        }
        XCTAssertEqual(cardID, hand[0].id, "a 7 busts at 95 — the Jack is the only move")
    }

    /// 4 — the read itself: skipping under a lock is recorded, and retired the
    /// moment the player proves it wrong.
    func testSkippingUnderALockIsRecordedAndLaterRetired() throws {
        let game = try engine([.ai(.sharp), .ai(.sharp)])
        var state = game.state
        state.currentPlayerIndex = 0
        state.tally = 40
        state.suitLock = SuitLock(suit: .hearts, setByPlayerID: "p1")
        state.players[0].hand = [card(.two, .clubs)]
        state.playsRemainingThisTurn = 1
        state.turnStartedWithDebt = false
        game._replaceStateForTesting(state)

        try game.skip(by: "p0")
        XCTAssertEqual(
            game.state.players[0].skippedUnderLock, .hearts,
            "the table saw them fail to follow hearts"
        )

        // Now they play a heart, which disproves it.
        var later = game.state
        later.currentPlayerIndex = 0
        later.tally = 10
        later.suitLock = nil
        later.players[0].hand = [card(.three, .hearts)]
        later.playsRemainingThisTurn = 1
        later.turnStartedWithDebt = false
        game._replaceStateForTesting(later)

        try game.play(cardID: card(.three, .hearts).id, by: "p0", declaration: Declaration())
        XCTAssertNil(
            game.state.players[0].skippedUnderLock,
            "a read that's been disproved is worse than no read"
        )
    }
}
