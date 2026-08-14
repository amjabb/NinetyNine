//
//  StrandedEndingTests.swift
//  Losing should be shown, not announced — and never put to a vote.
//
//  Two reports, one cause. A player eliminated mid-turn (surviving the well but
//  still owing a play, then holding nothing legal) had their hand swept back
//  into the deck as part of the elimination, so the screen went straight to the
//  result with the cards already gone. And a player who *was* given a beat was
//  given it as an "SDQ" button — asked to press a thing whose only outcome was
//  the one already forced on them.
//

import XCTest
@testable import NinetyNine

@MainActor
final class StrandedEndingTests: XCTestCase {

    private func card(_ rank: Rank, _ suit: Suit) -> Card {
        Deck.standard().first { $0.rank == rank && $0.suit == suit }!
    }

    /// The elimination carries the hand that couldn't answer, captured before
    /// the sweep. Without it the UI has nothing left to show.
    func testEliminationCarriesTheHandThatCouldNotAnswer() throws {
        let seats = [
            (id: "a", name: "A", kind: PlayerState.PlayerKind.human),
            (id: "b", name: "B", kind: PlayerState.PlayerKind.ai(.sharp)),
        ]
        let engine = try GameEngine(seats: seats, dealerIndex: 1, cardsDealt: 7, seed: 3)
        while let chooser = engine.state.wellChooserID {
            try engine.chooseWell(slots: [0, 1], by: chooser)
        }

        // Stranded: repaying a debt, tally at the ceiling, nothing legal, well spent.
        var state = engine.state
        let seat = try XCTUnwrap(state.index(of: "a"))
        state.currentPlayerIndex = seat
        state.tally = Rules.ceiling
        state.players[seat].hand = [card(.seven, .clubs), card(.eight, .hearts)]
        state.players[seat].well = []
        state.turnStartedWithDebt = true
        state.playsRemainingThisTurn = 1
        engine._replaceStateForTesting(state)

        let events = try engine.concedeStranded(by: "a")
        let elimination = events.first { if case .playerEliminated = $0 { return true }; return false }
        guard case .playerEliminated(let id, _, _, _, let finalHand)? = elimination else {
            return XCTFail("expected an elimination")
        }
        XCTAssertEqual(id, "a")
        XCTAssertEqual(
            Set(finalHand.map(\.id)),
            Set([card(.seven, .clubs).id, card(.eight, .hearts).id]),
            "the hand has to ride along — the engine has already swept it"
        )
        XCTAssertTrue(
            engine.state.players[seat].hand.isEmpty,
            "and it really is gone, so the event is the only copy"
        )
    }

    /// The engine's own mid-turn elimination — the reported case: a play landed,
    /// a play was still owed, the hand refilled, and none of the new cards were
    /// legal either.
    ///
    /// The refill is the part that makes this worth stating. You don't keep the
    /// hand you played from — you draw back up to three — so being stranded means
    /// the cards you were *dealt into the hole* were dead too. Which is precisely
    /// why the player is owed a look at them.
    func testBeingStrandedAfterAPlayStillCarriesTheHandYouDrewInto() throws {
        let seats = [
            (id: "a", name: "A", kind: PlayerState.PlayerKind.human),
            (id: "b", name: "B", kind: PlayerState.PlayerKind.ai(.sharp)),
        ]
        let engine = try GameEngine(seats: seats, dealerIndex: 1, cardsDealt: 7, seed: 11)
        while let chooser = engine.state.wellChooserID {
            try engine.chooseWell(slots: [0, 1], by: chooser)
        }

        var state = engine.state
        let seat = try XCTUnwrap(state.index(of: "a"))
        state.currentPlayerIndex = seat
        state.tally = Rules.ceiling
        // A Jack is 0, so it plays even at 99. Everything else here is dead
        // there: a 7 or an 8 would bust, and so would the King.
        state.players[seat].hand = [card(.jack, .spades), card(.king, .diamonds)]
        state.players[seat].well = []
        state.drawPile = [card(.seven, .clubs), card(.eight, .diamonds)]
        state.turnStartedWithDebt = true
        state.playsRemainingThisTurn = 2
        engine._replaceStateForTesting(state)

        let events = try engine.play(cardID: card(.jack, .spades).id, by: "a", declaration: Declaration())
        let elimination = events.first { if case .playerEliminated = $0 { return true }; return false }
        guard case .playerEliminated(_, let reason, _, _, let finalHand)? = elimination else {
            return XCTFail("expected the engine to end the turn it can't finish")
        }
        XCTAssertEqual(reason, .strandedWithoutWell)
        XCTAssertFalse(finalHand.isEmpty, "the hand has to survive the sweep for the UI to show it")
        XCTAssertTrue(
            finalHand.contains { $0.id == card(.king, .diamonds).id },
            "the card that was already stuck should be in what the player is shown"
        )
        XCTAssertTrue(
            finalHand.allSatisfy { !Rules.isPlayable($0, in: engine.state) },
            "every card shown should genuinely be one they couldn't play"
        )
    }

    /// Stranded is not a decision, so the table stops offering it as one. The
    /// view model ends the turn on its own.
    func testAStrandedSeatEndsItselfWithoutBeingAsked() async throws {
        let model = GameViewModel.solo(
            difficulty: .sharp, opponentCount: 1, cardsDealt: 7,
            playerName: "You", seed: 21
        )
        await model.begin()
        await model._settleForTesting()
        // Solo still opens on the well builder, and it waits for a human.
        if model.view?.youOweAWell == true {
            model.chooseWell(slots: [0, 1])
            await model._settleForTesting()
        }
        XCTAssertFalse(model.view?.youOweAWell ?? true, "should be past the well builder")

        model._forceStrandedForTesting(
            hand: [card(.seven, .clubs), card(.king, .diamonds)], tally: Rules.ceiling
        )

        // Watch the phase while it resolves — the reveal is transient by design,
        // so the only way to know it happened is to be looking.
        var sawTheHand: [Card]? = nil
        for _ in 0..<120 {
            if case .nothingPlayed(let cards, _) = model.wellReveal { sawTheHand = cards }
            if model.outcome != nil && sawTheHand != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        await model._settleForTesting()

        let shown = try XCTUnwrap(
            sawTheHand, "the hand that couldn't answer should be held up before the verdict"
        )
        XCTAssertFalse(shown.isEmpty)

        XCTAssertNotNil(
            model.outcome,
            "a seat with no legal card, no well and a play owed should resolve itself"
        )
    }
}
