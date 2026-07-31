import XCTest
@testable import NinetyNine

@MainActor
final class ThreeOfAKindRunTests: XCTestCase {

    /// Reported: holding three 7s early in a game, only two could be played
    /// together. Drives the same path the sheet does.
    func testAllThreeOfARankCanBeSelectedAndPlayed() async throws {
        let model = GameViewModel.solo(
            difficulty: .sharp, opponentCount: 2, cardsDealt: 7,
            playerName: "You", dealerID: nil, seed: 1
        )
        await model.begin()
        var guardCount = 0
        while model.view?.youAreChoosingYourWell == true && guardCount < 8 {
            guardCount += 1
            model.chooseWell(slots: [0, 1])
            try? await Task.sleep(for: .milliseconds(150))
        }

        // Force a hand of three sevens at a low tally.
        let sevens = [Suit.spades, Suit.hearts, Suit.clubs].enumerated().map {
            Card(id: 500 + $0.offset, rank: .seven, suit: $0.element)
        }
        model._forceHandForTesting(sevens, tally: 0)

        let hand = try XCTUnwrap(model.view).yourHand
        XCTAssertEqual(hand.count, 3, "Setup: three sevens in hand")

        model.longPressCard(hand[0])
        let pending = try XCTUnwrap(model.pendingSet, "Long press should open the run builder")
        XCTAssertEqual(pending.available.count, 3, "All three should be offered")
        XCTAssertEqual(
            pending.selected.count, 3,
            "It should open on every copy you hold, not a pair"
        )
        XCTAssertFalse(
            model.setDeclarations.isEmpty,
            "Three sevens from zero is 21 — it must be playable straight away"
        )
        XCTAssertEqual(model.projectedSetTally(model.setDeclarations[0]), 21)

        // And one can be kept back.
        model.toggleSetCard(pending.available[2])
        XCTAssertEqual(try XCTUnwrap(model.pendingSet).selected.count, 2)
    }

    /// It must never open in a state where Play is disabled — so when the whole
    /// run would bust, it opens on the longest run that doesn't.
    func testItOpensOnTheLongestLegalRunWhenTheWholeLotWouldBust() async throws {
        let model = GameViewModel.solo(
            difficulty: .sharp, opponentCount: 2, cardsDealt: 7,
            playerName: "You", dealerID: nil, seed: 1
        )
        await model.begin()
        var guardCount = 0
        while model.view?.youAreChoosingYourWell == true && guardCount < 8 {
            guardCount += 1
            model.chooseWell(slots: [0, 1])
            try? await Task.sleep(for: .milliseconds(150))
        }

        // Three sevens from 85: two is 99, three would be 106.
        let sevens = [Suit.spades, Suit.hearts, Suit.clubs].enumerated().map {
            Card(id: 600 + $0.offset, rank: .seven, suit: $0.element)
        }
        model._forceHandForTesting(sevens, tally: 85)

        let hand = try XCTUnwrap(model.view).yourHand
        model.longPressCard(hand[0])

        let pending = try XCTUnwrap(model.pendingSet)
        XCTAssertEqual(pending.selected.count, 2, "Three would bust, so it opens on two")
        XCTAssertFalse(model.setDeclarations.isEmpty, "And that pair must be playable")
        XCTAssertEqual(model.projectedSetTally(model.setDeclarations[0]), 99)
    }
}

// MARK: - Who's next

/// Reported: no clear sign of whose turn is coming. It's computed from the
/// seating order and the direction rather than sent, so it can't disagree with
/// the arrow drawn on the table — these pin that it tracks a reversal and steps
/// over anyone knocked out.
final class NextPlayerTests: XCTestCase {

    private func table(direction: Int = 1, eliminated: Set<String> = []) -> GameState {
        var players = ["a", "b", "c", "d"].map {
            PlayerState(id: $0, name: $0.uppercased(), kind: .human, handCap: 5)
        }
        for index in players.indices where eliminated.contains(players[index].id) {
            players[index].isEliminated = true
        }
        var state = GameState(
            players: players, currentPlayerIndex: 0, dealerID: "d", cardsDealt: 7
        )
        state.direction = direction
        return state
    }

    func testNextIsTheSeatToTheLeftGoingClockwise() {
        let view = table().view(for: "a")
        XCTAssertEqual(view.currentPlayerID, "a")
        XCTAssertEqual(view.nextPlayerID, "b")
    }

    func testAReversalTurnsItAround() {
        let view = table(direction: -1).view(for: "a")
        XCTAssertEqual(view.nextPlayerID, "d", "Counter-clockwise from A is D")
    }

    func testEliminatedSeatsAreSteppedOver() {
        let view = table(eliminated: ["b", "c"]).view(for: "a")
        XCTAssertEqual(view.nextPlayerID, "d")
    }

    /// It has to name *you* when the turn comes back round, which is the case
    /// that matters most: it's the difference between dumping a 99 and eating it.
    func testItNamesYouWhenItComesBackToYou() {
        let view = table(eliminated: ["c", "d"]).view(for: "b")
        XCTAssertEqual(view.currentPlayerID, "a")
        XCTAssertEqual(view.nextPlayerID, "b", "You are next")
        XCTAssertEqual(view.nextPlayerID, view.youID)
    }

    func testThereIsNoNextPlayerOnceTheGameIsOver() {
        var state = table()
        state.winnerID = "a"
        XCTAssertNil(state.view(for: "a").nextPlayerID)
    }
}
