//
//  ScreenshotTests.swift
//  Captures App Store screenshots by driving the real app into each state.
//
//  Kept separate from FlowUITests because these aren't assertions about
//  behaviour — they exist to produce marketing images from the shipping build,
//  so what the store shows can never diverge from what the app does.
//
//  Run explicitly:
//    xcodebuild test ... -only-testing:NinetyNineUITests/ScreenshotTests
//

import XCTest

final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A seeded record so the home screen and record screen look lived-in
        // rather than empty.
        app.launchArguments = ["-uitest-reset", "YES", "-uitest-showcase", "YES"]
        app.launch()
    }

    func testCaptureStoreScreenshots() throws {
        // 1 — Home
        XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.2)
        shot("store-1-home")

        // 2 — Rulebook
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rules'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ninety-Nine"].waitForExistence(timeout: 5))
        for title in ["The 9 and the 100", "The well"] {
            let header = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            if header.exists { header.tap() }
        }
        Thread.sleep(forTimeInterval: 0.8)
        shot("store-2-rules")
        app.buttons["Back"].tap()

        // 3 — Record
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Record'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Wins"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        shot("store-3-record")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.9)
        shot("store-4-achievements")
        app.buttons["Back"].tap()

        // 4 — Setup
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        playButton.tap()
        XCTAssertTrue(app.staticTexts["Set it up"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        shot("store-5-setup")

        // 5 — The table, early and then under real pressure.
        app.buttons["Deal"].tap()
        XCTAssertTrue(app.otherElements["Tally"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2.4)
        shot("store-6-table")

        // Play on and grab the table once the tally is genuinely dangerous — a
        // screenshot of a tally of 4 sells nothing.
        var moves = 0
        var capturedTension = false
        var capturedSheet = false
        while moves < 200 {
            moves += 1
            if app.buttons["Rematch"].exists { break }

            // A declaration sheet is the most distinctive screen in the game.
            if !capturedSheet, isDeclarationSheetUp {
                Thread.sleep(forTimeInterval: 0.6)
                shot("store-7-declaration")
                capturedSheet = true
            }
            if resolveDeclarationSheetIfPresent() { continue }

            if !capturedTension, let tally = currentTally, tally >= 78 {
                Thread.sleep(forTimeInterval: 0.5)
                shot("store-8-pressure")
                capturedTension = true
            }

            guard isPlayersTurn else {
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            if tapFirstExisting(["Snackoo", "The Well", "Skip", "No outs"]) { continue }
            if tapAPlayableCard() { continue }
            Thread.sleep(forTimeInterval: 0.2)
        }

        if app.buttons["Rematch"].exists {
            Thread.sleep(forTimeInterval: 1.0)
            shot("store-9-outcome")
        }

        // Report what was and wasn't captured, so a missing shot is visible in the
        // log rather than silently absent.
        XCTContext.runActivity(named: "capture summary") { _ in
            print("SHOTS captured: sheet=\(capturedSheet) pressure=\(capturedTension)")
        }
    }

    // MARK: - Helpers

    private var playButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play")).firstMatch
    }

    private var isPlayersTurn: Bool {
        app.staticTexts["Your move"].exists || app.staticTexts["No legal card"].exists
    }

    private var isDeclarationSheetUp: Bool {
        ["One, or eleven?", "Name the suit", "What is she copying?"]
            .contains { app.staticTexts[$0].exists }
    }

    /// Reads the tally off the gauge's accessibility value.
    private var currentTally: Int? {
        let gauge = app.otherElements["Tally"]
        guard gauge.exists, let value = gauge.value as? String else { return nil }
        let leading = value.prefix { $0.isNumber || $0 == "-" }
        return Int(leading)
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }

    @discardableResult
    private func tapFirstExisting(_ prefixes: [String]) -> Bool {
        for prefix in prefixes {
            let element = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", prefix)
            ).firstMatch
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
        }
        return false
    }

    private func tapAPlayableCard() -> Bool {
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "hand-card-"))
            .allElementsBoundByIndex
        for card in cards where card.isHittable {
            if (card.value as? String) == "Playable" {
                card.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.62)).tap()
                return true
            }
        }
        return false
    }

    @discardableResult
    private func resolveDeclarationSheetIfPresent() -> Bool {
        guard isDeclarationSheetUp || app.staticTexts["The well delivered"].exists else { return false }
        for prefix in ["1, tally becomes", "11, tally becomes", "Lock the suit to"] {
            let element = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", prefix)
            ).firstMatch
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
        }
        for button in app.buttons.allElementsBoundByIndex {
            guard button.exists, button.isHittable else { continue }
            if button.label == "Back" || button.label == "Pause" { continue }
            button.tap()
            return true
        }
        return false
    }
}
