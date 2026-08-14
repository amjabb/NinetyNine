//
//  RulebookTapTargetUITests.swift
//  The arrow has to open the section, because it looks like the control.
//
//  Reported by a player: the rulebook sections only opened when you hit the
//  title. A SwiftUI Button's label hit-tests where it draws and nowhere else,
//  so the Spacer between the title and the chevron was dead, and the chevron
//  itself is an 11-point glyph — well under the 44 points anybody can reliably
//  hit. The row looked like one control and behaved like two small ones.
//

import XCTest

final class RulebookTapTargetUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func openRulebook() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rules'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ninety-Nine"].waitForExistence(timeout: 10))
        return app
    }

    /// Tap at the far right of the row — where the arrow is, and where the old
    /// hit area stopped.
    func testTappingTheArrowOpensTheSection() {
        let app = openRulebook()

        let row = app.buttons["rule-section-lock"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the suit-lock section should be listed")

        let body = app.staticTexts["Naming a suit is optional — you can play an 8 and lock nothing."]
        let wasOpen = body.exists
        XCTAssertFalse(wasOpen, "sections start collapsed")

        // 96% of the way across: the chevron end, not the title.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()

        XCTAssertTrue(
            body.waitForExistence(timeout: 5),
            "tapping the arrow should open the section, not just tapping the words"
        )
    }

    /// And the dead zone in the middle, which never worked either.
    func testTappingTheEmptyMiddleOfTheRowOpensTheSection() {
        let app = openRulebook()

        let row = app.buttons["rule-section-nine"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5)).tap()

        XCTAssertTrue(
            app.staticTexts["A 9 sets the tally to exactly 99, whatever it was before. Brutal for whoever plays next."]
                .waitForExistence(timeout: 5),
            "the gap between the title and the arrow should be part of the control"
        )
    }
}
