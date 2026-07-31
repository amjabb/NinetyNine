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
        app.buildAllWells()
        XCTAssertTrue(app.otherElements["Tally"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2.4)
        shot("store-6-table")

        // Capture the declaration sheet on turn one, where the tally is 0 and
        // every card is legal — so an Ace, an 8, or a Queen in hand is guaranteed
        // to open it. Waiting for one to turn up mid-game left this shot to luck.
        var capturedSheet = captureDeclarationSheet()
        if !capturedSheet, app.buttons["Rematch"].exists == false {
            // Deal again and try once more; a 6-card hand holds at least one of
            // those ranks the large majority of the time.
            app.buttons["Pause"].tap()
            // BrassButton composes its label from title + subtitle, so the pause
            // menu's button reads "SDQ, Self Disqualify" rather than "SDQ".
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "SDQ")
            ).firstMatch.tap()
            _ = playButton.waitForExistence(timeout: 5)
            playButton.tap()
            _ = app.buttons["Deal"].waitForExistence(timeout: 5)
            app.buttons["Deal"].tap()
            app.buildAllWells()
            XCTAssertTrue(app.otherElements["Tally"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 2.4)
            capturedSheet = captureDeclarationSheet()
        }

        // Play on and grab the table once the tally is genuinely dangerous — a
        // screenshot of a tally of 4 sells nothing.
        var moves = 0
        var capturedTension = false
        while moves < 400 {
            moves += 1
            if app.buttons["Rematch"].exists { break }

            // Fallback: if turn one didn't hold a suitable card, take the sheet
            // whenever one does appear later.
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
            if pickAWellCardIfAsked() { continue }

            // Query each control only in the state where it exists. Polling for
            // "The Well" every iteration races the opponents' turns, and
            // resolving a query mid-transition throws rather than returning
            // empty.
            if app.staticTexts["No legal card"].exists {
                if tapFirstExisting(["The Well", "Skip", "No outs"]) { continue }
            } else if tapFirstExisting(["Snackoo"]) {
                continue
            }
            if !capturedSheet, tapAPlayableCard(preferringRanks: ["Ace", "Eight", "Queen"]) { continue }
            if tapAPlayableCard() { continue }
            Thread.sleep(forTimeInterval: 0.2)
        }

        // The move budget can run out while a game is still going — dramatic
        // beats (well reveals, eliminations) hold the table for a second or two
        // each. Give the game a chance to finish on its own before giving up on
        // the outcome shot.
        var capturedOutcome = false
        if app.buttons["Rematch"].waitForExistence(timeout: 60) {
            Thread.sleep(forTimeInterval: 1.2)
            shot("store-9-outcome")
            capturedOutcome = true
        }

        // Report what was and wasn't captured, so a missing shot is visible in the
        // log rather than silently absent.
        XCTContext.runActivity(named: "capture summary") { _ in
            print("SHOTS captured: sheet=\(capturedSheet) pressure=\(capturedTension) outcome=\(capturedOutcome)")
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
        ["One, or eleven?", "Lock a suit?", "What is she copying?"]
            .contains { app.staticTexts[$0].exists }
    }

    /// Reads the tally off the gauge's accessibility value.
    private var currentTally: Int? {
        let gauge = app.otherElements["Tally"]
        guard gauge.exists, let value = gauge.value as? String else { return nil }
        let leading = value.prefix { $0.isNumber || $0 == "-" }
        return Int(leading)
    }

    /// Taps an Ace, 8, or Queen to open the declaration sheet, captures it, and
    /// backs out leaving the card unplayed. Returns false if the hand held none.
    private func captureDeclarationSheet() -> Bool {
        guard isPlayersTurn else { return false }
        guard tapAPlayableCard(preferringRanks: ["Ace", "Eight", "Queen"]) else { return false }
        guard app.staticTexts["One, or eleven?"].waitForExistence(timeout: 2)
                || app.staticTexts["Lock a suit?"].exists
                || app.staticTexts["What is she copying?"].exists
        else { return false }

        Thread.sleep(forTimeInterval: 0.7)
        shot("store-7-declaration")
        // Leave the board untouched so the play loop below starts from a clean
        // position rather than mid-decision.
        if app.buttons["Back"].exists { app.buttons["Back"].tap() }
        return true
    }

    @discardableResult
    private func pickAWellCardIfAsked() -> Bool {
        guard app.staticTexts["Pick one. You won't know until you turn it."].exists else { return false }
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Well card", "Your last well card")
        ).firstMatch
        return tapSteadily(card)
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
            if tapSteadily(element) { return true }
        }
        return false
    }

    /// Tap an element by absolute coordinate rather than by re-resolving it.
    ///
    /// `element.tap()` re-queries at tap time, so a button that was present a
    /// millisecond ago but is mid-animation raises "No matches found" and fails
    /// the test. Banners in this app dismiss on timers, which re-renders the
    /// action bar underneath. Capturing the frame first and tapping the app at
    /// that point sidesteps the re-resolve entirely.
    @discardableResult
    private func tapSteadily(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else { return false }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
        return true
    }


    /// Taps a playable card. `preferringRanks` matches against the card's
    /// accessibility label ("Queen of Hearts"), and returns false rather than
    /// falling back, so the caller can decide what to do when no preferred card
    /// is available.
    private func tapAPlayableCard(preferringRanks ranks: [String] = []) -> Bool {
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "hand-card-"))
        // Resolving allElementsBoundByIndex while the hierarchy is mid-animation
        // throws rather than returning empty, so wait for the fan to exist first.
        guard query.firstMatch.waitForExistence(timeout: 4) else { return false }
        let cards = query.allElementsBoundByIndex

        let playable = cards.filter { $0.isHittable && ($0.value as? String) == "Playable" }
        let candidates = ranks.isEmpty
            ? playable
            : playable.filter { card in ranks.contains { card.label.hasPrefix($0) } }

        guard let card = candidates.first else { return false }
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.62)).tap()
        return true
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
