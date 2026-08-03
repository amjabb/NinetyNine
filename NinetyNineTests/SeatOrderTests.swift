//
//  SeatOrderTests.swift
//  The row of opponents has to agree with the arrows on the tally ring.
//
//  Both come from the same `direction`, so they cannot contradict each other
//  numerically — but they were still unreadable together, because the row was in
//  the table's absolute seating order. With the same direction of play, "next"
//  landed on the left end of the row or the right end depending only on which
//  seat you held, so the arrows pointed at nobody in particular.
//

import XCTest
@testable import NinetyNine

final class SeatOrderTests: XCTestCase {

    private func table(
        you: Int, direction: Int, players count: Int = 3, eliminated: Set<Int> = []
    ) -> PlayerView {
        let ids = (0..<count).map { "p\($0)" }
        var seats = ids.enumerated().map { index, id in
            PlayerState(
                id: id, name: id,
                kind: index == you ? .human : .ai(.sharp),
                handCap: 3
            )
        }
        for index in seats.indices {
            seats[index].hand = [Deck.standard()[index]]
            if eliminated.contains(index) {
                seats[index].isEliminated = true
                seats[index].hand = []
            }
        }
        var state = GameState(
            players: seats, currentPlayerIndex: you,
            drawPile: [], dealerID: ids[0], cardsDealt: 7
        )
        state.direction = direction
        return state.view(for: ids[you])
    }

    /// Clockwise: the next player is the leftmost opponent, from every seat.
    func testClockwisePutsNextAtTheLeftOfTheRowFromEverySeat() {
        for players in 2...6 {
            for you in 0..<players {
                let view = table(you: you, direction: 1, players: players)
                XCTAssertEqual(
                    view.opponents.first?.id, view.nextPlayerID,
                    "\(players)-handed from seat \(you): clockwise, next should be leftmost"
                )
            }
        }
    }

    /// Counter-clockwise: it's the rightmost. Same row, read the other way —
    /// which is exactly what the arrows are telling you to do.
    func testCounterClockwisePutsNextAtTheRightOfTheRowFromEverySeat() {
        for players in 2...6 {
            for you in 0..<players {
                let view = table(you: you, direction: -1, players: players)
                XCTAssertEqual(
                    view.opponents.last?.id, view.nextPlayerID,
                    "\(players)-handed from seat \(you): counter-clockwise, next should be rightmost"
                )
            }
        }
    }

    /// The rule survives eliminations: it's the nearest *live* opponent at that
    /// end, not simply whoever is drawn there.
    func testEliminatedSeatsAreSkippedButDoNotBreakTheMapping() {
        // Five seats, you at 0, the two immediately clockwise are out.
        let clockwise = table(you: 0, direction: 1, players: 5, eliminated: [1, 2])
        let firstLive = clockwise.opponents.first { !$0.isEliminated }
        XCTAssertEqual(firstLive?.id, clockwise.nextPlayerID)

        let counter = table(you: 0, direction: -1, players: 5, eliminated: [3, 4])
        let lastLive = counter.opponents.reversed().first { !$0.isEliminated }
        XCTAssertEqual(lastLive?.id, counter.nextPlayerID)
    }

    /// Reversing direction must not make the opponents swap places. The row is
    /// keyed to the seating, not to which way play happens to be going — a 4
    /// changes which end you read from, not where anybody sits.
    func testReversingDirectionDoesNotRearrangeTheTable() {
        for players in 2...6 {
            for you in 0..<players {
                let clockwise = table(you: you, direction: 1, players: players)
                let counter = table(you: you, direction: -1, players: players)
                XCTAssertEqual(
                    clockwise.opponents.map(\.id), counter.opponents.map(\.id),
                    "\(players)-handed from seat \(you): seats moved when direction flipped"
                )
            }
        }
    }

    /// And the row is still everybody but you, exactly once.
    func testTheRowHoldsEveryOpponentExactlyOnce() {
        for players in 2...6 {
            for you in 0..<players {
                let view = table(you: you, direction: 1, players: players)
                let ids = view.opponents.map(\.id)
                XCTAssertEqual(ids.count, players - 1)
                XCTAssertEqual(Set(ids).count, players - 1, "an opponent appears twice")
                XCTAssertFalse(ids.contains(view.youID), "you are in your own opponent row")
            }
        }
    }
}
