//
//  WellBuildingHelper.swift
//  Shared ways past the screens that stand between a test and a table.
//
//  Since 1.3 a game doesn't deal straight to a table: everything goes to the
//  hand and each player buries two of it as their well. That's now the first
//  thing on screen in every mode, so every UI test has to walk through it —
//  including pass-and-play, where each seat builds its own behind a hand-off.
//
//  Shared rather than copied into each file, because a test that silently fails
//  to get past this looks identical to a test whose feature is broken.
//

import XCTest

extension XCUIApplication {

    /// Build a well for every local player who's asked to, dismissing hand-offs
    /// on the way. Returns how many wells were built.
    ///
    /// The two screens have to be handled *together*, not in sequence. In
    /// pass-and-play the well builder is deliberately not in the hierarchy while
    /// the hand-off covers the device — that's the privacy property — so a
    /// helper that checks for a hand-off once and then blocks on the well screen
    /// waits forever for something that can't appear yet.
    @discardableResult
    func buildAllWells(timeout: TimeInterval = 20) -> Int {
        var built = 0
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if otherElements["well-selection"].exists {
                guard bankTwoCards() else { break }
                built += 1
                continue
            }
            if dismissHandoffIfPresent() { continue }
            // Neither is up: either the table is ready, or something is still
            // animating. Stop as soon as the table exists.
            if otherElements["Tally"].exists && built > 0 { break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return built
    }

    /// Wait for the well builder specifically, then bank two cards.
    @discardableResult
    func buildOneWell(timeout: TimeInterval = 12) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if otherElements["well-selection"].exists { return bankTwoCards() }
            if dismissHandoffIfPresent() { continue }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// Tap candidates until the confirm button goes live, then confirm.
    private func bankTwoCards() -> Bool {
        let confirm = buttons["well-confirm"]
        guard confirm.waitForExistence(timeout: 4) else { return false }

        var guardCount = 0
        while !confirm.isEnabled && guardCount < 12 {
            guardCount += 1
            let candidates = descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "well-candidate-"))
                .allElementsBoundByIndex
            guard let next = candidates.first(where: { $0.isHittable }) else { break }
            next.tap()
        }
        guard confirm.isEnabled else { return false }
        confirm.tap()
        Thread.sleep(forTimeInterval: 0.5)
        return true
    }

    /// The pass-and-play cover screen. Tapping through it is a precondition for
    /// the next seat's well, not a separate concern.
    @discardableResult
    func dismissHandoffIfPresent() -> Bool {
        // The cover button is "I'm <name>" — matched by prefix because the name
        // is whatever the players typed.
        let ready = buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "I'm ")
        ).firstMatch
        guard ready.exists, ready.isHittable else { return false }
        ready.tap()
        Thread.sleep(forTimeInterval: 0.4)
        return true
    }
}

// MARK: - The declaration sheet

extension XCUIApplication {

    /// Answer whatever the declaration sheet is asking, if it's up.
    ///
    /// Any legal answer will do — these callers are driving a game forward, not
    /// testing the sheet. What matters is that the helper *recognises* the sheet
    /// and never taps its way backwards: an earlier version fell through to
    /// "tap any button that isn't Back", which started tapping "Pick a different
    /// card" once the Queen gained a second step, and looped until the move
    /// budget ran out.
    @discardableResult
    func resolveDeclarationSheet() -> Bool {
        let titles = [
            "One, or eleven?",       // an Ace
            "Lock a suit?",          // an 8
            "What is she copying?",  // a Queen, first step
            "The well delivered",
        ]
        let isUp = titles.contains { staticTexts[$0].exists }
            || staticTexts.containing(
                NSPredicate(format: "label BEGINSWITH %@", "She's an")
            ).firstMatch.exists
        guard isUp else { return false }

        // Concrete answers, most specific first.
        let answers = [
            "1, tally becomes", "11, tally becomes",
            "Lock the suit to", "Leave the suit open",
        ]
        for prefix in answers where tapButton(labelPrefix: prefix) { return true }

        // A Queen's rank grid: anything but the ways out.
        let forbidden: Set<String> = ["Back", "Pause", "Pick a different card"]
        for button in buttons.allElementsBoundByIndex {
            guard button.exists, button.isHittable, !forbidden.contains(button.label) else { continue }
            button.tap()
            // Picking a rank can open a second step (an 8 needs a suit, an Ace a
            // value). Answer that too, so one call always leaves the sheet.
            Thread.sleep(forTimeInterval: 0.4)
            for prefix in answers where tapButton(labelPrefix: prefix) { break }
            return true
        }
        return false
    }

    @discardableResult
    private func tapButton(labelPrefix: String) -> Bool {
        let element = buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", labelPrefix)).firstMatch
        guard element.exists, element.isHittable else { return false }
        element.tap()
        return true
    }
}
