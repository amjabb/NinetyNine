//
//  WellSelectionUITests.swift
//  Building your well out of your own deal.
//
//  This is now the first thing that happens in every game, so if it's wrong
//  nothing else is reachable. Driven through real taps.
//

import XCTest

final class WellSelectionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "YES", "-uitest-seed", "1"]
        app.launch()
    }

    /// The point of the screen: you cannot see what you're burying.
    func testTheDealIsFaceDownWhileYouChoose() throws {
        startAGame()
        XCTAssertTrue(app.otherElements["well-selection"].waitForExistence(timeout: 12))

        // Every candidate is face down, and says so. If a rank or suit appeared
        // in a label here, the well would be known to its owner from the start —
        // and VoiceOver would read it aloud.
        let candidates = candidateCards()
        XCTAssertGreaterThan(candidates.count, 2)
        for card in candidates {
            XCTAssertTrue(
                card.label.contains("face down"),
                "A candidate leaked its identity: \(card.label)"
            )
            for rank in ["Ace", "King", "Queen", "Jack"] {
                XCTAssertFalse(card.label.contains(rank), "Leaked a rank: \(card.label)")
            }
            for suit in ["Spades", "Hearts", "Diamonds", "Clubs"] {
                XCTAssertFalse(card.label.contains(suit), "Leaked a suit: \(card.label)")
            }
        }
        // And no hand cards are on screen yet either.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "hand-card-"))
                .allElementsBoundByIndex.isEmpty,
            "Your hand shouldn't be visible until the well is buried"
        )
        ShotCollector.capture(app, name: "72-well-blind")
    }

    func testYouBuildYourWellBeforeTheTableAppears() throws {
        startAGame()

        let screen = app.otherElements["well-selection"]
        XCTAssertTrue(
            screen.waitForExistence(timeout: 10),
            "A game should open by asking you to build your well"
        )
        ShotCollector.capture(app, name: "70-well-selection")

        // Nothing is banked yet, so the button must not be live.
        let confirm = app.buttons["well-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertFalse(confirm.isEnabled, "Nothing picked yet")

        let candidates = candidateCards()
        XCTAssertGreaterThan(candidates.count, 2, "Seed 1 deals more than the well size")

        candidates[0].tap()
        XCTAssertFalse(confirm.isEnabled, "One card is not a well")
        candidates[1].tap()
        XCTAssertTrue(waitFor { confirm.isEnabled }, "Two picked — it should be ready")

        ShotCollector.capture(app, name: "71-well-chosen")
        confirm.tap()

        // The table has to appear, and this player's hand must be short by the
        // two they buried.
        XCTAssertTrue(
            app.otherElements["Tally"].waitForExistence(timeout: 15),
            "Burying the well should start the game"
        )
        XCTAssertTrue(waitFor { !screen.exists }, "The builder should be gone")
    }

    func testACardCanBeTakenBackOutOfTheWell() throws {
        startAGame()
        XCTAssertTrue(app.otherElements["well-selection"].waitForExistence(timeout: 10))

        let confirm = app.buttons["well-confirm"]
        let before = candidateCards().count

        let first = candidateCards()[0]
        let bankedID = first.identifier
        first.tap()

        // It stays in place but is now marked as buried — the row is positional,
        // so cards can't be removed from it without renumbering everything.
        XCTAssertTrue(
            waitFor { (self.app.buttons[bankedID].value as? String) == "In your well" },
            "The tapped card should read as buried"
        )
        XCTAssertEqual(candidateCards().count, before, "The row is positional and doesn't reflow")

        // Tapping it again takes it back.
        app.buttons[bankedID].tap()
        XCTAssertTrue(
            waitFor { (self.app.buttons[bankedID].value as? String) == "Kept" },
            "Tapping a buried card again should take it back"
        )
        XCTAssertFalse(confirm.isEnabled)
    }

    // MARK: - Helpers

    private func startAGame() {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play")).firstMatch.tap()
        app.buttons["Deal"].tap()
    }

    private func candidateCards() -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "well-candidate-"))
            .allElementsBoundByIndex
    }

    private func waitFor(timeout: TimeInterval = 6, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }
}
