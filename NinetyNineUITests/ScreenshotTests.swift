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

        // 6 — Building your well. The headline of this version and the first
        // thing anyone sees in a game, so it earns a slot: face-down cards, and
        // a decision you make without information.
        app.buttons["Deal"].tap()
        XCTAssertTrue(
            app.otherElements["well-selection"].waitForExistence(timeout: 12),
            "A game should open on the well builder"
        )
        Thread.sleep(forTimeInterval: 1.6)
        // With two buried, so the slots are filled and the intent is legible.
        let candidates = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "well-candidate-"))
            .allElementsBoundByIndex
        if candidates.count > 3 {
            candidates[1].tap()
            candidates[3].tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        shot("store-6-well")

        // 7 — The table, early and then under real pressure.
        app.buildAllWells()
        XCTAssertTrue(app.otherElements["Tally"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2.4)
        shot("store-7-table")

        // Capture the declaration sheet on turn one, where the tally is 0 and
        // every card is legal — so an Ace, an 8, or a Queen in hand is guaranteed
        // to open it. Waiting for one to turn up mid-game left this shot to luck.
        //
        // Redeal until one turns up. A single retry left this to a coin-flip a
        // hand of five loses about one time in twenty — which is exactly how the
        // iPad slot ended up shipping nine screenshots instead of ten, with the
        // capture reporting success.
        var capturedSheet = captureDeclarationSheet()
        var redeals = 0
        while !capturedSheet, redeals < 4, !app.buttons["Rematch"].exists {
            redeals += 1
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
                shot("store-8-declaration")
                capturedSheet = true
            }
            if resolveDeclarationSheetIfPresent() { continue }

            if !capturedTension, let tally = currentTally, tally >= 78 {
                Thread.sleep(forTimeInterval: 0.5)
                shot("store-9-pressure")
                capturedTension = true
            }

            guard isPlayersTurn else {
                // Somebody at the well holds the screen for a few seconds.
                // Checked here rather than at the top of the loop: resolving an
                // identifier that isn't on screen costs seconds in XCUITest
                // retries, so it must only run when nothing else was actionable.
                if app.otherElements["well-reveal"].isHittable {
                    Thread.sleep(forTimeInterval: 0.4)
                } else {
                    Thread.sleep(forTimeInterval: 0.2)
                }
                continue
            }
            if pickAWellCardIfAsked() { continue }

            // While the declaration shot is still outstanding, go looking for it
            // — play an Ace, an 8 or a Queen in preference to anything else.
            // Leaving it to whatever the hand happened to hold missed the shot
            // about a quarter of the time.
            if !capturedSheet, tapAPlayableCard(preferringRanks: ["Ace", "Eight", "Queen"]) {
                continue
            }

            // Query each control only in the state where it exists. Polling for
            // "The Well" every iteration races the opponents' turns, and
            // resolving a query mid-transition throws rather than returning
            // empty.
            // Snackoo is deliberately absent from this list: it's optional, it
            // comes and goes with the hand, and no store shot needs it — chasing
            // it only made this capture race a button already withdrawing.
            if app.staticTexts["No legal card"].exists {
                if tapFirstExisting(["The Well", "Skip", "No outs"]) { continue }
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
            shot("store-10-outcome")
            capturedOutcome = true
        }

        // Fail on a missing shot rather than reporting it.
        //
        // This used to print a summary and pass. A run that captured nine of ten
        // therefore looked identical to a complete one, and the capture script
        // — which only checked that *something* had been produced — replaced a
        // full set of App Store screenshots with the short one.
        XCTAssertTrue(capturedSheet, "never captured the declaration sheet")
        XCTAssertTrue(capturedTension, "never captured the table under pressure")
        XCTAssertTrue(capturedOutcome, "never captured the outcome screen")
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
        shot("store-8-declaration")
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
        // Re-check immediately before reading the frame. Some controls here are
        // transient — Snackoo appears and withdraws as the hand changes — and
        // reading `.frame` on one that has just gone raises rather than
        // returning nil, which fails the whole test.
        guard element.exists else { return false }
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
        // Scoped to the sheet: `app.buttons` also holds the hand behind the
        // scrim, and tapping a card there does nothing while leaving the sheet
        // up — a loop with no way out.
        let sheet = app.otherElements["declaration-sheet"]
        let candidates = sheet.exists
            ? sheet.buttons.allElementsBoundByIndex
            : app.buttons.allElementsBoundByIndex.filter {
                !$0.identifier.hasPrefix("hand-card-")
            }
        for button in candidates {
            guard button.exists, button.isHittable else { continue }
            if ["Back", "Pause", "Pick a different card"].contains(button.label) { continue }
            button.tap()
            return true
        }
        return false
    }
}
