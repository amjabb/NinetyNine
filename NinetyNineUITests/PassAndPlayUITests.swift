//
//  PassAndPlayUITests.swift
//  Drives a real pass-and-play game through the hand-off, with real taps.
//
//  The assertion that matters most is that the table is genuinely covered
//  between players. Everything else about pass-and-play is ordinary card game;
//  that one thing is what makes sharing a screen work at all.
//

import XCTest

final class PassAndPlayUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "YES"]
        app.launch()
    }

    // MARK: - Setup

    func test01_SetupOffersPassAndPlayWithNameEntry() {
        playButton.tap()
        XCTAssertTrue(app.staticTexts["Set it up"].waitForExistence(timeout: 5))

        // Solo is the default; both modes should be offered.
        XCTAssertTrue(app.buttons["Solo"].exists)
        let passAndPlay = app.buttons["Pass & play"]
        XCTAssertTrue(passAndPlay.exists)
        passAndPlay.tap()

        XCTAssertTrue(
            app.staticTexts["Two to six of you, sharing this device. The screen covers between turns."]
                .waitForExistence(timeout: 3),
            "Choosing pass & play should explain what it is"
        )

        // Names matter here — the hand-off has to name who to give the phone to.
        let firstSeat = app.textFields["Name for seat 1"]
        XCTAssertTrue(firstSeat.waitForExistence(timeout: 3), "Each seat should be nameable")
        XCTAssertTrue(app.textFields["Name for seat 2"].exists)

        // Difficulty is meaningless with no AI, so it shouldn't be offered.
        XCTAssertFalse(app.buttons["Ruthless"].exists, "Difficulty is irrelevant with no AI seats")
    }

    func test02_SeatCountAddsAndRemovesNameFields() {
        playButton.tap()
        _ = app.staticTexts["Set it up"].waitForExistence(timeout: 5)
        app.buttons["Pass & play"].tap()

        app.buttons["2"].tap()
        XCTAssertTrue(app.textFields["Name for seat 2"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["Name for seat 3"].exists)

        app.buttons["4"].tap()
        XCTAssertTrue(app.textFields["Name for seat 4"].waitForExistence(timeout: 3))
    }

    // MARK: - The hand-off

    func test03_PlayingAPassAndPlayGameCoversTheScreenBetweenPlayers() throws {
        startTwoPlayerGame(firstName: "Ada", secondName: "Bo")

        // The deal itself is now private: each player picks two of their own
        // cards for their well, so their hand is on screen before anyone has
        // played. That has to be behind a hand-off like everything else.
        // BrassButton composes its accessibility label from title + subtitle,
        // so match on the prefix rather than the bare title.
        let firstPrompt = handoffButton(for: "Ada")
        XCTAssertTrue(
            firstPrompt.waitForExistence(timeout: 10),
            "Even the opening deal should be behind a hand-off"
        )
        XCTAssertFalse(
            app.otherElements["well-selection"].isHittable,
            "Ada's dealt cards must be covered until she's holding the device"
        )
        shot("pp-1-handoff")

        firstPrompt.tap()
        XCTAssertTrue(app.buildOneWell(), "Ada should be asked to build her well")

        // And Bo's deal must be covered from Ada in turn.
        let boPrompt = handoffButton(for: "Bo")
        XCTAssertTrue(
            boPrompt.waitForExistence(timeout: 10),
            "Bo's deal should be behind his own hand-off"
        )
        XCTAssertFalse(
            app.otherElements["well-selection"].isHittable,
            "Bo's dealt cards must not be visible to Ada"
        )
        boPrompt.tap()
        XCTAssertTrue(app.buildOneWell(), "Bo should be asked to build his well")

        // Only now does play begin — behind one more hand-off.
        let adasTurn = handoffButton(for: "Ada")
        XCTAssertTrue(adasTurn.waitForExistence(timeout: 10), "Ada's turn needs a hand-off too")
        XCTAssertFalse(app.otherElements["Tally"].isHittable, "The table must be covered")
        adasTurn.tap()
        XCTAssertTrue(app.otherElements["Tally"].waitForExistence(timeout: 6))
        Thread.sleep(forTimeInterval: 1.6)
        shot("pp-2-first-player")

        // Ada plays; the screen must then be covered for Bo.
        XCTAssertTrue(takeATurn(), "Ada should have had a legal move")

        let secondPrompt = handoffButton(for: "Bo")
        XCTAssertTrue(
            secondPrompt.waitForExistence(timeout: 8),
            "After Ada's move the device must be covered for Bo"
        )
        shot("pp-3-handoff-to-bo")

        secondPrompt.tap()
        XCTAssertTrue(app.otherElements["Tally"].waitForExistence(timeout: 5))
    }

    func test04_EachPlayerSeesOnlyTheirOwnHand() throws {
        startAndBuildWells(firstName: "Ada", secondName: "Bo")

        // buildAllWells leaves the device covered for whoever leads.
        if handoffButton(for: "Ada").exists { handoffButton(for: "Ada").tap() }
        _ = app.otherElements["Tally"].waitForExistence(timeout: 6)
        Thread.sleep(forTimeInterval: 1.8)

        let adasHand = Set(handCards.map(\.label))
        XCTAssertFalse(adasHand.isEmpty)

        XCTAssertTrue(takeATurn())
        XCTAssertTrue(handoffButton(for: "Bo").waitForExistence(timeout: 8))
        handoffButton(for: "Bo").tap()
        _ = app.otherElements["Tally"].waitForExistence(timeout: 5)
        Thread.sleep(forTimeInterval: 1.8)

        let bosHand = Set(handCards.map(\.label))
        XCTAssertFalse(bosHand.isEmpty)

        // Two different players, two different hands. Any overlap would mean the
        // redaction boundary leaked a card between seats.
        XCTAssertTrue(
            adasHand.intersection(bosHand).isEmpty,
            "Bo is holding cards that were in Ada's hand: \(adasHand.intersection(bosHand))"
        )
    }

    func test05_PassAndPlayReachesAWinnerNamedOnScreen() throws {
        startAndBuildWells(firstName: "Ada", secondName: "Bo")

        // A two-handed game of 99 can run long once the deck starts recycling, and
        // each XCUITest query costs real time — so the budget is generous and the
        // per-iteration sleep is small. The headless tests already prove games
        // terminate; what this one proves is that the *UI* can drive one to the end.
        var turns = 0
        while turns < 900 {
            turns += 1
            Thread.sleep(forTimeInterval: 0.05)

            if app.buttons["Rematch"].exists { break }

            // Take the device when offered.
            let handoff = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "I'm ")
            ).firstMatch
            if handoff.exists && handoff.isHittable {
                handoff.tap()
                Thread.sleep(forTimeInterval: 0.35)
                continue
            }

            // A rematch deals again, so the well builder can reappear
            // part-way through the loop.
            if app.otherElements["well-selection"].isHittable {
                if app.buildOneWell(timeout: 2) { continue }
            }
            if resolveDeclarationSheetIfPresent() { continue }
            if pickAWellCardIfAsked() { continue }
            if app.staticTexts["No legal card"].exists {
                if tapFirst(["The Well", "Skip", "No outs"]) { continue }
            } else if app.staticTexts["Your move"].exists {
                if tapFirst(["Snackoo"]) { continue }
                if tapAPlayableCard() { continue }
            }
        }

        XCTAssertTrue(
            app.buttons["Rematch"].waitForExistence(timeout: 180),
            "A pass-and-play game should reach a conclusion"
        )
        // On a shared screen the winner is named, not called "You" — everyone is
        // reading the same result.
        let namedWinner = app.staticTexts["Ada"].exists || app.staticTexts["Bo"].exists
        XCTAssertTrue(namedWinner, "The winner should be named on a shared device")
        shot("pp-4-outcome")
    }

    // MARK: - Helpers

    /// Answers the well's "pick one" prompt. Returns false when it isn't up.
    @discardableResult
    private func pickAWellCardIfAsked() -> Bool {
        guard app.staticTexts["Pick one. You won't know until you turn it."].exists else { return false }
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Well card", "Your last well card")
        ).firstMatch
        return tapSteadily(card)
    }

    private func handoffButton(for name: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "I'm \(name)")
        ).firstMatch
    }

    private var playButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play")).firstMatch
    }

    private var handCards: [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "hand-card-"))
            .allElementsBoundByIndex
    }

    private func startTwoPlayerGame(firstName: String, secondName: String) {
        playButton.tap()
        _ = app.staticTexts["Set it up"].waitForExistence(timeout: 5)
        app.buttons["Pass & play"].tap()
        app.buttons["2"].tap()

        setName(seat: 1, to: firstName)
        setName(seat: 2, to: secondName)

        app.buttons["Deal"].tap()
        // Deliberately stops here. Each seat still has to build a well, and each
        // one sits behind its own hand-off — which is exactly what test03 is
        // checking, so this must not quietly tap through them.
    }

    /// Get to a table: every seat builds a well, dismissing hand-offs on the way.
    private func startAndBuildWells(firstName: String, secondName: String) {
        startTwoPlayerGame(firstName: firstName, secondName: secondName)
        app.buildAllWells()
    }

    private func setName(seat: Int, to name: String) {
        let field = app.textFields["Name for seat \(seat)"]
        guard field.waitForExistence(timeout: 3) else {
            XCTFail("No name field for seat \(seat)")
            return
        }
        field.tap()
        field.typeText(name)
        // Dismiss the keyboard so it can't cover the Deal button.
        app.keyboards.buttons["done"].firstMatch.tap()
    }

    /// Play one legal card (resolving a declaration sheet if it appears).
    @discardableResult
    private func takeATurn() -> Bool {
        guard tapAPlayableCard() else { return false }
        Thread.sleep(forTimeInterval: 0.4)
        _ = resolveDeclarationSheetIfPresent()
        Thread.sleep(forTimeInterval: 0.6)
        return true
    }

    private func tapAPlayableCard() -> Bool {
        for card in handCards where card.isHittable {
            if (card.value as? String) == "Playable" {
                card.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.62)).tap()
                return true
            }
        }
        return false
    }

    @discardableResult
    private func tapFirst(_ prefixes: [String]) -> Bool {
        for prefix in prefixes {
            let element = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
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


    @discardableResult
    private func resolveDeclarationSheetIfPresent() -> Bool {
        app.resolveDeclarationSheet()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}
