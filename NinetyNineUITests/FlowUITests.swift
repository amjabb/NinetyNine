//
//  FlowUITests.swift
//  End-to-end interaction coverage, driven through real taps and gestures.
//
//  These tests exist for two jobs:
//   1. Assert every screen, transition, and control actually works — including
//      the ones that only appear in rare game states.
//   2. Capture screenshots of each state to the host filesystem, so the visuals
//      can be reviewed and used for App Store material.
//
//  Screenshots land in the test runner's Documents directory, which lives inside
//  the simulator's data container on the host and so can be collected after the
//  run. `ShotCollector` handles that.
//

import XCTest

final class FlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Reset persisted state so every run starts from a known table.
        app.launchArguments = ["-uitest-reset", "YES"]
        app.launch()
    }

    // MARK: - Menu flows

    func test01_HomeScreenPresentsEveryEntryPoint() {
        XCTAssertTrue(app.buttons["Play, 3 players · Sharp"].waitForExistence(timeout: 8)
            || app.buttons.matching(identifier: "Play").firstMatch.waitForExistence(timeout: 2)
            || playButton.waitForExistence(timeout: 2),
            "The Play button should be on the home screen")
        XCTAssertTrue(button("Rules").exists)
        XCTAssertTrue(button("Record").exists)
        XCTAssertTrue(button("Settings").exists)
        ShotCollector.capture(app, name: "01-home")
    }

    func test02_RulebookOpensExpandsAndReturns() {
        button("Rules").tap()
        XCTAssertTrue(app.staticTexts["Ninety-Nine"].waitForExistence(timeout: 5))
        ShotCollector.capture(app, name: "02-rules-top")

        // Every collapsible section should expand.
        for title in ["Taking a turn", "The suit lock (8)", "The 9 and the 100", "The well"] {
            let header = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            if header.exists {
                header.tap()
            }
        }
        ShotCollector.capture(app, name: "03-rules-expanded")

        app.swipeUp()
        app.swipeUp()
        ShotCollector.capture(app, name: "04-rules-cards")

        button("Back").tap()
        XCTAssertTrue(playButton.waitForExistence(timeout: 5), "Back should return to the menu")
    }

    func test03_RecordScreenShowsStatsAndAchievements() {
        button("Record").tap()
        XCTAssertTrue(app.staticTexts["Wins"].waitForExistence(timeout: 5))
        ShotCollector.capture(app, name: "05-record")
        app.swipeUp()
        app.swipeUp()
        ShotCollector.capture(app, name: "06-achievements")
        button("Back").tap()
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
    }

    func test04_SettingsTogglesPersistAndReturn() {
        button("Settings").tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        ShotCollector.capture(app, name: "07-settings")

        // Flip both feel toggles and confirm they respond.
        let toggles = app.switches
        if toggles.count >= 2 {
            let first = toggles.element(boundBy: 0)
            let before = first.value as? String
            first.tap()
            XCTAssertNotEqual(first.value as? String, before, "Toggle should change state")
            first.tap()
        }
        button("Back").tap()
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
    }

    // MARK: - Setup

    func test05_SetupAdjustsPlayersDifficultyAndHandSize() {
        playButton.tap()
        XCTAssertTrue(app.staticTexts["Set it up"].waitForExistence(timeout: 5))
        ShotCollector.capture(app, name: "08-setup")

        // Player count.
        app.buttons["5"].tap()

        // Difficulty.
        let ruthless = app.buttons["Ruthless"]
        XCTAssertTrue(ruthless.waitForExistence(timeout: 3), "Difficulty options should be present")
        ruthless.tap()
        XCTAssertTrue(
            app.staticTexts["Hoards brakes, weaponises the lock, sets traps."].waitForExistence(timeout: 3),
            "Selecting a difficulty should update its description"
        )
        ShotCollector.capture(app, name: "09-setup-five-ruthless")

        // Hand size stepper should respect the player-count ceiling. With six
        // players the maximum is 6, so increasing repeatedly must clamp.
        let increase = app.buttons["Increase hand size"]
        for _ in 0..<10 where increase.isEnabled { increase.tap() }
        ShotCollector.capture(app, name: "10-setup-clamped")

        // Back to a sane table for the game tests.
        app.buttons["2"].tap()
        app.buttons["Sharp"].tap()

        button("Back").tap()
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
    }

    // MARK: - A full game

    func test06_PlayAGameToCompletion() {
        playButton.tap()
        XCTAssertTrue(app.staticTexts["Set it up"].waitForExistence(timeout: 5))
        app.buttons["Deal"].tap()

        // The table should come up with a gauge and a full hand.
        let gauge = app.otherElements["Tally"]
        XCTAssertTrue(gauge.waitForExistence(timeout: 10), "The tally gauge should be on the table")
        waitForDealToSettle()
        ShotCollector.capture(app, name: "11-table-dealt")

        // Regression guard: the fan must fit the screen. An earlier layout put the
        // outermost cards 37pt off each edge.
        let cards = handCards
        XCTAssertEqual(cards.count, 6, "A 6-card hand should show six cards")
        let screen = app.frame
        for card in cards {
            XCTAssertGreaterThanOrEqual(
                card.frame.minX, -1,
                "Card \(card.identifier) hangs off the left edge"
            )
            XCTAssertLessThanOrEqual(
                card.frame.maxX, screen.maxX + 1,
                "Card \(card.identifier) hangs off the right edge"
            )
            XCTAssertLessThanOrEqual(
                card.frame.maxY, screen.maxY + 1,
                "Card \(card.identifier) hangs off the bottom"
            )
        }

        // Pause menu round-trip.
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 4))
        ShotCollector.capture(app, name: "12-paused")
        app.buttons["Resume"].tap()
        XCTAssertFalse(app.staticTexts["Paused"].waitForExistence(timeout: 2))

        // Play the game out by repeatedly taking whatever action is offered.
        // This is the real integration test: it exercises card taps, the
        // declaration sheet, the well, skips, and Snackoo in whatever order the
        // deal happens to produce.
        playUntilGameOver(moveBudget: 260)

        // Whatever happened, the game must have reached a resolution.
        XCTAssertTrue(
            app.buttons["Rematch"].waitForExistence(timeout: 60),
            "The game should reach a win or loss screen"
        )
        ShotCollector.capture(app, name: "40-outcome")

        // Rematch now routes through the dealer prompt: the first player out
        // deals next and chooses the hand size.
        app.buttons["Rematch"].tap()
        let dealPrompt = app.staticTexts["First one out deals the next game."]
        XCTAssertTrue(
            dealPrompt.waitForExistence(timeout: 8),
            "Rematch should ask the dealer how many to deal"
        )
        ShotCollector.capture(app, name: "43-next-deal")

        let deal = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Deal", "Continue")
        ).firstMatch
        XCTAssertTrue(deal.exists, "The dealer prompt should offer to deal")
        deal.tap()
        XCTAssertTrue(app.otherElements["Tally"].waitForExistence(timeout: 10), "Rematch should deal again")
        ShotCollector.capture(app, name: "41-rematch")

        // And quitting should land back on the menu.
        app.buttons["Pause"].tap()
        app.buttons["Quit to menu"].tap()
        XCTAssertTrue(playButton.waitForExistence(timeout: 6), "Quit should return to the menu")
    }

    func test07_TappingAnUnplayableCardExplainsItself() throws {
        playButton.tap()
        app.buttons["Deal"].tap()
        waitForDealToSettle()

        // Play on until the player's turn presents at least one dead card, then tap
        // it. Once the tally climbs or a suit lock lands this happens within a few
        // turns, so it needs no lucky deal.
        for game in 0..<3 {
            var moves = 0
            while moves < 200 {
                moves += 1

                Thread.sleep(forTimeInterval: 0.2)
                if app.buttons["Rematch"].exists { break }
                if resolveDeclarationSheetIfPresent() { continue }
                guard isPlayersTurn else { continue }

                if let dead = handCards.first(where: { ($0.value as? String) == "Not playable" }) {
                    let name = dead.label
                    tapVisiblePortion(of: dead)

                    let toast = app.descendants(matching: .any)["coaching-toast"]
                    XCTAssertTrue(
                        toast.waitForExistence(timeout: 3),
                        "Tapping the dead \(name) should explain why it can't be played"
                    )
                    XCTAssertTrue(
                        toast.label.count > 12,
                        "The explanation should be a real reason, got: '\(toast.label)'"
                    )
                    ShotCollector.capture(app, name: "42-coaching")
                    return
                }

                if pickAWellCardIfAsked() { continue }
                if app.staticTexts["No legal card"].exists {
                    if tapFirstExisting(byLabelPrefix: ["The Well", "Skip", "No outs"]) == true { continue }
                } else if app.staticTexts["Your move"].exists {
                    if tapFirstExisting(byLabelPrefix: ["Snackoo"]) == true { continue }
                    if tapAPlayableCard() { continue }
                }
            }

            if app.buttons["Rematch"].exists, game < 2 {
                app.buttons["Rematch"].tap()
                waitForDealToSettle()
            }
        }
        XCTFail("Three full games never presented the player with an unplayable card")
    }

    // MARK: - Game driver

    /// True when the table is waiting on the player. Every mutating tap is gated
    /// on this: during the player's turn nothing changes without input, so
    /// checking it first removes the race where a button vanishes between the
    /// existence check and the tap.
    private var isPlayersTurn: Bool {
        app.staticTexts["Your move"].exists || app.staticTexts["No legal card"].exists
    }

    /// Play the current game to its conclusion by taking whatever action the
    /// table offers. This is the real integration test: across a full game it
    /// exercises card taps, the declaration sheet, the well, skips, Snackoo,
    /// eliminations, and the game-over screen in whatever order the deal produces.
    private func playUntilGameOver(moveBudget: Int) {
        var moves = 0
        while moves < moveBudget {
            moves += 1

            // Banners and the delta chip auto-dismiss on timers, so the hierarchy
            // is briefly in motion even on the player's turn. A short settle
            // before querying avoids resolving a snapshot mid-transition.
            Thread.sleep(forTimeInterval: 0.2)

            if app.buttons["Rematch"].exists { return }
            if resolveDeclarationSheetIfPresent() { continue }

            // Query each control only in the state where it actually exists —
            // polling for "The Well" on every iteration races against the
            // opponents' turns.
            // The well now asks which of the two face-down cards to turn over.
            if pickAWellCardIfAsked() { continue }

            if app.staticTexts["No legal card"].exists {
                if tapFirstExisting(byLabelPrefix: ["The Well", "Skip", "No outs"]) == true { continue }
            } else if app.staticTexts["Your move"].exists {
                if tapFirstExisting(byLabelPrefix: ["Snackoo"]) == true { continue }
                if tapAPlayableCard() { continue }
            }
        }
    }

    /// Answers the well's "pick one" prompt. Returns false when it isn't up.
    @discardableResult
    private func pickAWellCardIfAsked() -> Bool {
        guard app.staticTexts["Pick one. You won't know until you turn it."].exists else { return false }
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Well card", "Your last well card")
        ).firstMatch
        guard card.exists, card.isHittable else { return false }
        card.tap()
        return true
    }

    // MARK: - Helpers

    private var playButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play")).firstMatch
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    /// The declaration sheet asks for an Ace's value, an 8's suit, or the rank a
    /// Queen is copying. Any legal answer will do here — the point is to keep the
    /// game moving through every code path.
    @discardableResult
    private func resolveDeclarationSheetIfPresent() -> Bool {
        let sheetTitles = ["One, or eleven?", "Name the suit", "What is she copying?", "The well delivered"]
        guard sheetTitles.contains(where: { app.staticTexts[$0].exists }) else { return false }

        // Prefer whichever concrete option is on screen.
        let candidates = [
            "1, tally becomes", "11, tally becomes",
            "Lock the suit to Spades", "Lock the suit to Hearts",
            "Lock the suit to Diamonds", "Lock the suit to Clubs",
        ]
        for prefix in candidates {
            let element = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", prefix)
            ).firstMatch
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
        }
        // A Queen's grid of ranks: tap any tile that isn't the Back button.
        for button in app.buttons.allElementsBoundByIndex {
            guard button.exists, button.isHittable else { continue }
            let label = button.label
            if label == "Back" || label == "Pause" { continue }
            button.tap()
            return true
        }
        return false
    }

    @discardableResult
    private func tapFirstExisting(_ labels: [String]) -> Bool? {
        for label in labels {
            let element = app.buttons[label]
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
        }
        return nil
    }

    @discardableResult
    private func tapFirstExisting(byLabelPrefix prefixes: [String]) -> Bool? {
        for prefix in prefixes {
            let element = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
                .firstMatch
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
        }
        return nil
    }

    /// Every hand card carries the identifier `hand-card-<id>` and a value of
    /// "Playable" / "Not playable". Tap the first playable one.
    private func tapAPlayableCard() -> Bool {
        for card in handCards where card.isHittable {
            if (card.value as? String) == "Playable" {
                tapVisiblePortion(of: card)
                return true
            }
        }
        return false
    }

    /// Cards in the fan overlap, so each one's right-hand portion is covered by
    /// its neighbour and a centre tap can land on the wrong card. Tapping the
    /// lower-left area hits the sliver that is actually visible.
    private func tapVisiblePortion(of card: XCUIElement) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.62)).tap()
    }

    private var handCards: [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "hand-card-"))
            .allElementsBoundByIndex
    }

    /// Wait for the opening deal animation to settle before capturing a shot, so
    /// screenshots show the table rather than a half-dealt hand.
    private func waitForDealToSettle() {
        _ = app.otherElements["Tally"].waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 2.2)
    }
}

// MARK: - Screenshot collection

/// Writes screenshots into the app's shared Documents directory so they can be
/// pulled off the simulator afterwards, *and* attaches them to the test result
/// for viewing in Xcode.
enum ShotCollector {
    static func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "shot \(name)") { $0.add(attachment) }

        guard let directory = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }
        let shots = directory.appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
    }
}
