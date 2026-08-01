//
//  QueenMomentTests.swift
//  The turn queens go bad, as the view model sees it.
//
//  This used to be a UI test that played real games until a queen came off the
//  deck. It worked — it produced the screenshot the design was checked against —
//  but it took eight minutes and its result depended on the shuffle, which is
//  everything a suite doesn't want. The behaviour worth pinning is what the view
//  model builds out of the event, so that's what's pinned here.
//

import XCTest
@testable import NinetyNine

@MainActor
final class QueenMomentTests: XCTestCase {

    private func table() async -> GameViewModel {
        let model = GameViewModel.solo(
            difficulty: .sharp, opponentCount: 2, cardsDealt: 6,
            playerName: "You", dealerID: nil, seed: 1
        )
        await model.begin()
        return model
    }

    private let queen = Card(id: 901, rank: .queen, suit: .hearts)

    /// Absorbing the timeline *blocks* on the moment — that's the point of it,
    /// the game waits while the player reads. So the assertion has to happen
    /// while it's on screen: start the absorb, catch the state, then dismiss.
    @discardableResult
    private func showMoment(
        _ model: GameViewModel, _ events: [GameEvent]
    ) async throws -> GameViewModel.QueenPoisoning {
        let absorbing = Task { await model._absorbForTesting(events) }
        let deadline = Date().addingTimeInterval(3)
        while model.queenPoisoning == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let moment = try XCTUnwrap(model.queenPoisoning, "The moment should be on screen")
        model.dismissQueenPoisoning()
        await absorbing.value
        return moment
    }

    func testTheMomentNamesWhoDrewItAndWhatItCostsYou() async throws {
        let model = await table()
        let you = try XCTUnwrap(model.viewingPlayerID)

        let moment = try await showMoment(model, [
            .queensBecamePoisonous(card: queen, trigger: you),
            .queenPoisoned(card: Card(id: 902, rank: .queen, suit: .spades), owner: you, newHandCap: 4),
            .queenPoisoned(card: Card(id: 903, rank: .queen, suit: .clubs), owner: "ai0", newHandCap: 4),
        ])

        XCTAssertEqual(moment.card, queen, "It should show the queen that did it")
        XCTAssertTrue(moment.itWasYou)
        XCTAssertEqual(moment.yourExiledCount, 1, "Only your own exiles count")
        XCTAssertEqual(moment.yourNewCap, 4)
    }

    /// Someone else drawing it still changes the rules for you, and the copy has
    /// to say whose fault it was.
    func testAnotherPlayerDrawingItIsAttributedToThem() async throws {
        let model = await table()
        let you = try XCTUnwrap(model.viewingPlayerID)

        let moment = try await showMoment(model, [
            .queensBecamePoisonous(card: queen, trigger: "ai0"),
            .queenPoisoned(card: Card(id: 902, rank: .queen, suit: .spades), owner: you, newHandCap: 4),
            .queenPoisoned(card: Card(id: 904, rank: .queen, suit: .diamonds), owner: you, newHandCap: 3),
        ])

        XCTAssertFalse(moment.itWasYou)
        XCTAssertFalse(moment.triggerName.isEmpty)
        XCTAssertNotEqual(moment.triggerName, you, "It should read as a name, not an ID")
        XCTAssertEqual(moment.yourExiledCount, 2, "Both of your queens went")
        XCTAssertEqual(moment.yourNewCap, 3, "The cap should be where it ended up")
    }

    /// A poisoning that costs this player nothing still has to be shown — the
    /// rule changed for everybody.
    func testTheMomentAppearsEvenWhenYouHeldNoQueens() async throws {
        let model = await table()

        let moment = try await showMoment(model, [
            .queensBecamePoisonous(card: queen, trigger: "ai1"),
            .queenPoisoned(card: Card(id: 905, rank: .queen, suit: .clubs), owner: "ai0", newHandCap: 4),
        ])

        XCTAssertEqual(moment.yourExiledCount, 0)
        XCTAssertNil(moment.yourNewCap)
    }

    /// The previous beat's banner is cleared, because the overlay's scrim sits
    /// over it and the two read on top of each other.
    func testTheMomentClearsWhateverBannerWasUp() async throws {
        let model = await table()
        model.announcement = GameViewModel.Announcement(
            headline: "Clockwise", detail: "Turn order reversed.", tone: .neutral
        )

        let absorbing = Task {
            await model._absorbForTesting([.queensBecamePoisonous(card: queen, trigger: "ai0")])
        }
        let deadline = Date().addingTimeInterval(3)
        while model.queenPoisoning == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(model.queenPoisoning)
        XCTAssertNil(model.announcement, "A stale banner would read through the overlay")

        model.dismissQueenPoisoning()
        await absorbing.value
    }

    func testDismissingClearsItAndLetsPlayResume() async throws {
        let model = await table()
        try await showMoment(model, [.queensBecamePoisonous(card: queen, trigger: "ai0")])
        XCTAssertNil(model.queenPoisoning, "Dismissing should clear it")
    }

    /// Left alone — an unattended device, or a table of nothing but AI — the
    /// moment has to time out rather than wedge the game.
    func testItGivesUpWaitingRatherThanBlockingForever() async throws {
        let model = await table()
        let started = Date()
        // Nobody taps. Absorb has to return on its own.
        await model._absorbForTesting([.queensBecamePoisonous(card: queen, trigger: "ai0")])
        XCTAssertNil(model.queenPoisoning, "The backstop should have cleared it")
        XCTAssertLessThan(
            Date().timeIntervalSince(started), 12,
            "The backstop should be seconds, not minutes"
        )
    }
}

// MARK: - Watching someone else go to the well

/// The well is the most dramatic thing that happens in a round, and it used to
/// be invisible from every seat but the one it was happening to — the overlay
/// was only ever driven by the local player's own draw, so an opponent quietly
/// survived or quietly vanished. The whole table watches now.
@MainActor
final class WatchingTheWellTests: XCTestCase {

    private func table() async -> GameViewModel {
        let model = GameViewModel.solo(
            difficulty: .sharp, opponentCount: 2, cardsDealt: 7,
            playerName: "You", dealerID: nil, seed: 1
        )
        await model.begin()
        var guardCount = 0
        while model.view?.youAreChoosingYourWell == true && guardCount < 8 {
            guardCount += 1
            model.chooseWell(slots: [0, 1])
            try? await Task.sleep(for: .milliseconds(150))
        }
        return model
    }

    /// Collect the phases the overlay passes through while absorbing a timeline.
    private func phases(
        _ model: GameViewModel, absorbing events: [GameEvent]
    ) async -> [GameViewModel.WellRevealPhase] {
        var seen: [GameViewModel.WellRevealPhase] = []
        let absorbing = Task { await model._absorbForTesting(events) }
        let deadline = Date().addingTimeInterval(8)
        while !absorbing.isCancelled, Date() < deadline {
            let phase = model.wellReveal
            if seen.last != phase { seen.append(phase) }
            if absorbing.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(40))
            if case .idle = model.wellReveal, seen.count > 1 { break }
        }
        await absorbing.value
        return seen
    }

    func testAnOpponentSurvivingTheWellIsShownToEveryone() async throws {
        let model = await table()
        let card = Card(id: 910, rank: .three, suit: .clubs)

        let seen = await phases(model, absorbing: [
            .wellRevealed(card: card, by: "ai0", playable: true)
        ])

        XCTAssertTrue(
            seen.contains { if case .rolling(let id) = $0 { return id == "ai0" }; return false },
            "The table should see them reach for it: \(seen)"
        )
        XCTAssertTrue(
            seen.contains { if case .revealed(let c, let ok, let id) = $0 {
                return c == card && ok && id == "ai0"
            }; return false },
            "…and see the card turn over: \(seen)"
        )
        XCTAssertTrue(
            seen.contains { if case .survived(_, let id) = $0 { return id == "ai0" }; return false },
            "…and see them get away with it: \(seen)"
        )
    }

    func testAnOpponentLosingToTheWellIsAlsoShown() async throws {
        let model = await table()
        let card = Card(id: 911, rank: .king, suit: .spades)

        let seen = await phases(model, absorbing: [
            .wellRevealed(card: card, by: "ai1", playable: false)
        ])

        XCTAssertTrue(
            seen.contains { if case .revealed(_, let ok, let id) = $0 { return !ok && id == "ai1" }
                            return false },
            "A losing draw should be shown too: \(seen)"
        )
        XCTAssertFalse(
            seen.contains { if case .survived = $0 { return true }; return false },
            "Nobody survived that one"
        )
    }

    /// It has to hand the table back afterwards, or play stops.
    func testTheOverlayClearsWhenItsDone() async throws {
        let model = await table()
        await model._absorbForTesting([
            .wellRevealed(card: Card(id: 912, rank: .four, suit: .hearts), by: "ai0", playable: true)
        ])
        XCTAssertEqual(model.wellReveal, .idle)
    }

    /// Your own draw is driven by your own action, with its own pacing — this
    /// path must not fire for it as well, or the reveal happens twice.
    func testYourOwnDrawIsNotDrivenFromTheTimeline() async throws {
        let model = await table()
        let you = try XCTUnwrap(model.viewingPlayerID)
        await model._absorbForTesting([
            .wellRevealed(card: Card(id: 913, rank: .two, suit: .clubs), by: you, playable: true)
        ])
        XCTAssertEqual(model.wellReveal, .idle, "The local draw has its own path")
    }
}
