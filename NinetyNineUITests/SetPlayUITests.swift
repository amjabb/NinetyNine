//
//  SetPlayUITests.swift
//  Playing several of a rank at once, driven through a real long press.
//
//  This is the interaction most likely to be quietly broken by a change to the
//  hand: the long press shares a card with a drag and a tap, and gesture priority
//  is not something a unit test can see. So the whole path is exercised here —
//  press, adjust the run, play it, and confirm the table moved.
//
//  The shuffle is pinned with `-uitest-seed` so the opening hand is guaranteed to
//  hold a pair. SeedSearchTests is what keeps that seed honest.
//

import XCTest

final class SetPlayUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "YES", "-uitest-seed", "1"]
        app.launch()
    }

    // MARK: - The gesture

    func testLongPressOpensTheRunBuilderAndPlaysTheRun() throws {
        startAGame()

        try longPressACardWithCompany()

        let sheet = app.otherElements["set-play-sheet"]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 4),
            "A long press on a card with company should open the run builder"
        )
        ShotCollector.capture(app, name: "50-set-builder")

        // It opens with a pair already selected, so Play is live immediately.
        let play = app.buttons["set-play-confirm"]
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        XCTAssertTrue(play.isEnabled, "A pair should be playable the moment the sheet opens")

        // Which cards are going down, so we can confirm they actually left.
        let runIDs = selectedCardIDs()
        XCTAssertGreaterThanOrEqual(runIDs.count, 2)

        play.tap()

        XCTAssertTrue(waitForSheetToClose(), "Playing the run should dismiss the builder")
        // Every card in the run has to leave the hand. A run that dismisses the
        // sheet without reaching the engine is the failure this test exists for,
        // and it would look identical from the outside otherwise.
        XCTAssertTrue(
            waitFor { runIDs.isDisjoint(with: self.handCardIDs()) },
            "Cards \(runIDs.sorted()) should have left the hand"
        )
    }

    func testTheRunBuilderCanBeDismissedWithoutPlaying() throws {
        startAGame()
        let handBefore = handCards.count

        try longPressACardWithCompany()
        XCTAssertTrue(app.otherElements["set-play-sheet"].waitForExistence(timeout: 4))

        app.buttons["set-play-cancel"].tap()
        XCTAssertTrue(waitForSheetToClose(), "Back should close the builder")
        XCTAssertEqual(handCards.count, handBefore, "Backing out should not play anything")
    }

    /// Deselecting down to one card must disable Play rather than submit a
    /// single-card "run", which the engine would refuse.
    func testASingleCardIsNotAPlayableRun() throws {
        startAGame()
        try longPressACardWithCompany()
        XCTAssertTrue(app.otherElements["set-play-sheet"].waitForExistence(timeout: 4))

        let selected = setCards.filter { ($0.value as? String)?.hasPrefix("In the run") == true }
        XCTAssertGreaterThanOrEqual(selected.count, 2, "The builder should open with a pair")

        selected[0].tap()

        let play = app.buttons["set-play-confirm"]
        XCTAssertTrue(waitFor { !play.isEnabled }, "One card is not a run")
        XCTAssertEqual(play.label, "Pick two or more")
    }

    /// The long press must not steal the ordinary tap. This is the regression
    /// that would make the whole hand feel broken.
    func testAPlainTapStillPlaysASingleCard() throws {
        startAGame()

        var tapped: String?
        for card in handCards where card.isHittable {
            guard (card.value as? String) == "Playable" else { continue }
            tapped = card.identifier
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.62)).tap()
            break
        }
        let played = try XCTUnwrap(tapped, "The opening hand should hold a playable card")

        XCTAssertFalse(
            app.otherElements["set-play-sheet"].waitForExistence(timeout: 1.5),
            "A tap must never open the run builder"
        )
        // Assert on the card, not on the hand *size* — the hand refills to the
        // cap, so the count is back where it started a moment later and would
        // pass whether or not anything was played.
        XCTAssertTrue(
            waitFor {
                !self.app.buttons[played].exists || self.app.buttons["Back"].exists
            },
            "\(played) should have left the hand, or asked how to play it"
        )
    }

    // MARK: - Helpers

    private func startAGame() {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play")).firstMatch.tap()
        app.buttons["Deal"].tap()
        app.buildAllWells()
        _ = app.otherElements["Tally"].waitForExistence(timeout: 12)
        Thread.sleep(forTimeInterval: 2.2)
    }

    /// Press and hold the first card that shares its rank with another. The
    /// pinned seed guarantees one exists; if it doesn't, the seed has drifted and
    /// SeedSearchTests will say so.
    private func longPressACardWithCompany() throws {
        var byRank: [String: [XCUIElement]] = [:]
        for card in handCards where card.isHittable {
            // Labels read "Six of Hearts" — the rank is everything before " of ".
            let rank = String(card.label.split(separator: " of ").first ?? "")
            byRank[rank, default: []].append(card)
        }
        let pair = try XCTUnwrap(
            byRank.values.first { $0.count > 1 },
            "Seed 1 should deal a pair — see SeedSearchTests"
        )
        // Press the *leftmost* copy: cards overlap left-to-right, so its visible
        // sliver is the one guaranteed not to be covered by a neighbour.
        pair[0].coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.62))
            .press(forDuration: 0.9)
    }

    private var handCards: [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "hand-card-"))
            .allElementsBoundByIndex
    }

    private var setCards: [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "set-card-"))
            .allElementsBoundByIndex
    }

    /// Card IDs currently in the run, read off the builder.
    private func selectedCardIDs() -> Set<Int> {
        Set(
            setCards
                .filter { ($0.value as? String)?.hasPrefix("In the run") == true }
                .compactMap { Int($0.identifier.replacingOccurrences(of: "set-card-", with: "")) }
        )
    }

    private func handCardIDs() -> Set<Int> {
        Set(handCards.compactMap { Int($0.identifier.replacingOccurrences(of: "hand-card-", with: "")) })
    }

    private func waitForSheetToClose() -> Bool {
        waitFor { !self.app.otherElements["set-play-sheet"].exists }
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
