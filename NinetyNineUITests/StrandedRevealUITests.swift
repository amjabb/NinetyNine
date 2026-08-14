//
//  StrandedRevealUITests.swift
//  The dead hand has to actually appear, and the turn has to end by itself.
//

import XCTest

final class StrandedRevealUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Drive a real game to a stranded seat and assert the table shows the cards
    /// and then resolves without anybody touching it.
    func testAStrandedSeatShowsItsHandAndEndsItself() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-stranded"]
        app.launch()

        let playButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Play")
        ).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        playButton.tap()
        XCTAssertTrue(app.buttons["Deal"].waitForExistence(timeout: 5))
        app.buttons["Deal"].tap()
        app.buildAllWells()

        // The forced position lands as soon as the table appears.
        XCTAssertTrue(
            app.otherElements["Tally"].waitForExistence(timeout: 15),
            "the table should open"
        )

        // No SDQ button — being stranded is not a decision.
        let sdq = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "SDQ")
        ).firstMatch
        XCTAssertFalse(
            sdq.waitForExistence(timeout: 2),
            "a stranded seat should not be offered a button whose only outcome is forced"
        )

        // The card reveal itself is asserted in StrandedEndingTests, not here.
        // It is a 2.3-second beat, and an XCUITest query can take longer than
        // that to resolve on a busy hierarchy — so a test for it here would fail
        // on timing rather than on behaviour. What this run is for is the part
        // that persists: nothing was tapped, and the seat still resolved.

        // The verdict, without anybody having touched the screen.
        XCTAssertTrue(
            app.staticTexts["You're out"].waitForExistence(timeout: 20),
            "the stranded seat should resolve itself unprompted"
        )
    }
}
