//
//  AutoWellTests.swift
//  Pass-and-play can bank everyone's well without a lap of the table.
//

import XCTest
@testable import NinetyNine

@MainActor
final class AutoWellTests: XCTestCase {

    /// The whole point: the table opens ready to play, with nobody prompted.
    func testAutoAssignBanksEveryWellBeforePlayBegins() async throws {
        let model = GameViewModel.passAndPlay(
            playerNames: ["Amir", "Ken", "Elaine"],
            cardsDealt: 7,
            seed: 99,
            autoAssignWells: true
        )
        await model.begin()
        await model._settleForTesting()

        let view = try XCTUnwrap(model.view)
        XCTAssertFalse(view.youOweAWell, "nobody should still be owing a well")
        XCTAssertNil(view.wellChooserID)
        // Seven dealt, two banked: the opening hand is five, decaying to the
        // sustaining three over the first couple of turns. What matters here is
        // that the well came *out* of it and the hand is playable.
        XCTAssertEqual(view.yourHand.count, 7 - Rules.wellSize,
                       "the well should have come out of the dealt hand")
    }

    /// Auto-banking must produce a *real* well — two hidden cards each, not an
    /// empty one that quietly costs every player their second life.
    func testEverySeatEndsWithATwoCardWell() async throws {
        let model = GameViewModel.passAndPlay(
            playerNames: ["Amir", "Ken", "Elaine"],
            cardsDealt: 7,
            seed: 4,
            autoAssignWells: true
        )
        await model.begin()
        await model._settleForTesting()

        let view = try XCTUnwrap(model.view)
        XCTAssertEqual(view.yourWellCount, Rules.wellSize)
        for opponent in view.opponents {
            XCTAssertEqual(opponent.wellCount, Rules.wellSize, "\(opponent.name) has no well")
        }
    }

    /// Off by default, and off means the table still asks.
    func testWithoutTheOptionTheTableStillAsks() async throws {
        let model = GameViewModel.passAndPlay(
            playerNames: ["Amir", "Ken"],
            cardsDealt: 7,
            seed: 12
        )
        await model.begin()
        await model._settleForTesting()

        let view = try XCTUnwrap(model.view)
        XCTAssertNotNil(view.wellChooserID, "somebody should be on the hook for a well")
    }

    /// The picks land in the shared action log like any other decision, so a
    /// replay of the log reproduces the game exactly.
    func testAutoPicksAreReplayable() async throws {
        let model = GameViewModel.passAndPlay(
            playerNames: ["Amir", "Ken", "Elaine"],
            cardsDealt: 7,
            seed: 77,
            autoAssignWells: true
        )
        await model.begin()
        await model._settleForTesting()

        let log = model._actionLogForTesting
        let wellPicks = log.filter {
            if case .chooseWell = $0.action { return true }
            return false
        }
        XCTAssertEqual(wellPicks.count, 3, "one logged pick per seat")
    }
}
