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
        // And wait for *everyone* to finish burying, not just us. Nothing is
        // playable until the match has actually started, which is the whole
        // point of the gate this used to run ahead of.
        var settleGuard = 0
        while model.view?.wellChooserID != nil && settleGuard < 40 {
            settleGuard += 1
            try? await Task.sleep(for: .milliseconds(100))
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
            seen.contains { if case .rolling(let id, _) = $0 { return id == "ai0" }; return false },
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

// MARK: - A surviving well card still has to be played

/// Reported from play: "I got a queen from the well but it didn't ask me what
/// card I wanted it to be. This worries me that well cards aren't actually
/// being played."
///
/// They were right, and it was a regression: the survival celebration was added
/// in front of the code that resolves the card, and returned before reaching it.
/// The card was revealed, cheered, and then left face up and uncommitted — the
/// turn simply stopped.
///
/// Nothing caught it because every existing well test asserted on the *engine*,
/// where resolveWell works perfectly. The break was entirely in the order the
/// view model does things, so that is where these look.
@MainActor
final class WellCardIsActuallyPlayedTests: XCTestCase {

    private func tableWithWell(_ well: [Card], hand: [Card], tally: Int) async throws -> GameViewModel {
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
        // And wait for *everyone* to finish burying, not just us. Nothing is
        // playable until the match has actually started, which is the whole
        // point of the gate this used to run ahead of.
        var settleGuard = 0
        while model.view?.wellChooserID != nil && settleGuard < 40 {
            settleGuard += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Wait for the table to stop moving before forcing a position. The AI
        // turn loop started by `begin()` is still running, and a state written
        // under it gets played over — which looked exactly like the bug being
        // tested. A fixed sleep passed alone and failed under suite load.
        await model._settleForTesting()
        model._forceWellForTesting(well, hand: hand, tally: tally)
        return model
    }

    /// A Queen off the well must ask what it is, exactly as one from the hand
    /// would. This is the reported case.
    func testAQueenFromTheWellAsksWhatItIs() async throws {
        let queen = Card(id: 940, rank: .queen, suit: .hearts)
        let model = try await tableWithWell(
            [queen, Card(id: 941, rank: .two, suit: .clubs)],
            hand: [Card(id: 942, rank: .king, suit: .spades)],
            tally: 95
        )

        await model._drawWellForTesting(slot: 0)

        let choice = try XCTUnwrap(
            model.pendingChoice,
            "A Queen from the well has to be declared, like any other Queen"
        )
        XCTAssertEqual(choice.card.id, queen.id)
        XCTAssertTrue(choice.isFromWell)
        XCTAssertGreaterThan(choice.options.count, 1, "She can be many things")
    }

    /// A card with only one legal reading is played outright — no sheet, but it
    /// must actually land.
    func testAPlainWellCardIsPlayedWithoutAsking() async throws {
        let three = Card(id: 950, rank: .three, suit: .clubs)
        let model = try await tableWithWell(
            [three, Card(id: 951, rank: .two, suit: .hearts)],
            hand: [Card(id: 952, rank: .king, suit: .spades)],
            tally: 90
        )

        await model._drawWellForTesting(slot: 0)

        XCTAssertNil(model.pendingChoice, "Nothing to ask about a three")
        let view = try XCTUnwrap(model.view)
        XCTAssertNil(view.pendingWell, "It should be resolved, not left face up")
        XCTAssertEqual(view.tally, 93, "And it should have moved the tally")
    }

    /// The failure mode that was shipping: revealed, celebrated, then nothing.
    func testTheTurnDoesNotStallAfterSurvivingTheWell() async throws {
        let four = Card(id: 960, rank: .four, suit: .spades)
        let model = try await tableWithWell(
            [four, Card(id: 961, rank: .two, suit: .hearts)],
            hand: [Card(id: 962, rank: .king, suit: .spades)],
            tally: 96
        )

        await model._drawWellForTesting(slot: 0)

        let view = try XCTUnwrap(model.view)
        XCTAssertNil(view.pendingWell, "A survived well card must not be left dangling")
        XCTAssertEqual(model.wellReveal, .idle, "And the overlay must hand the table back")
    }
}

// MARK: - The well shows what's actually in it

/// Reported twice, in two different screens. The pick shows one card when one
/// is left; then the draw animation came up with two before flipping.
///
/// Both were the same shape of mistake — a count that was written down once and
/// never asked again — and the second survived the first fix because the phases
/// are separate views with separate assumptions.
@MainActor
final class WellCardCountTests: XCTestCase {

    private func table(well: [Card]) async throws -> GameViewModel {
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
        // And wait for *everyone* to finish burying, not just us. Nothing is
        // playable until the match has actually started, which is the whole
        // point of the gate this used to run ahead of.
        var settleGuard = 0
        while model.view?.wellChooserID != nil && settleGuard < 40 {
            settleGuard += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
        await model._settleForTesting()
        // Nothing legal in hand, so the well is the only way on.
        model._forceWellForTesting(well, hand: [Card(id: 880, rank: .king, suit: .spades)], tally: 99)
        return model
    }

    func testTheChoiceOffersOnlyTheCardsThatAreThere() async throws {
        let model = try await table(well: [Card(id: 881, rank: .four, suit: .hearts)])
        model.useWell()

        guard case .choosing(_, let slots) = model.wellReveal else {
            XCTFail("Expected the pick prompt, got \(model.wellReveal)")
            return
        }
        XCTAssertEqual(slots, 1, "One card left means one card offered")
    }

    /// The one that was still wrong: the draw animation.
    func testTheDrawAnimationShowsOnlyTheCardsThatAreThere() async throws {
        let model = try await table(well: [Card(id: 882, rank: .four, suit: .hearts)])
        let started = Task { await model._drawWellForTesting(slot: 0) }

        var sawRolling = false
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if case .rolling(_, let slots) = model.wellReveal {
                sawRolling = true
                XCTAssertEqual(
                    slots, 1,
                    "A spent well was animating two cards — the game appeared to invent one"
                )
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(sawRolling, "Never saw the draw animation")
        await started.value
    }

    func testAFullWellStillAnimatesBoth() async throws {
        let model = try await table(well: [
            Card(id: 883, rank: .four, suit: .hearts),
            Card(id: 884, rank: .three, suit: .clubs),
        ])
        let started = Task { await model._drawWellForTesting(slot: 0) }

        var seen: Int?
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if case .rolling(_, let slots) = model.wellReveal { seen = slots; break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(seen, 2)
        await started.value
    }
}

// MARK: - The Snackoo shows its cards

/// Reported: the celebration didn't show the cards. It had been built to, and
/// the view model was passing them — but the table constructed the view without
/// them, and the parameter had a default of `[]`, so it compiled and quietly
/// celebrated nothing.
///
/// The parameter no longer has a default. These check the half that a type
/// can't: that the cards reach the moment at all.
@MainActor
final class SnackooShowsItsCardsTests: XCTestCase {

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
        // And wait for *everyone* to finish burying, not just us. Nothing is
        // playable until the match has actually started, which is the whole
        // point of the gate this used to run ahead of.
        var settleGuard = 0
        while model.view?.wellChooserID != nil && settleGuard < 40 {
            settleGuard += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
        return model
    }

    private func moment(
        _ model: GameViewModel, absorbing events: [GameEvent]
    ) async -> GameViewModel.SnackooMoment? {
        let absorbing = Task { await model._absorbForTesting(events) }
        var captured: GameViewModel.SnackooMoment?
        let deadline = Date().addingTimeInterval(4)
        while captured == nil, Date() < deadline {
            captured = model.snackooMoment
            try? await Task.sleep(for: .milliseconds(30))
        }
        await absorbing.value
        return captured
    }

    func testTheThreeCardsReachTheCelebration() async throws {
        let model = await table()
        let jacks = [Suit.spades, .hearts, .clubs].enumerated().map {
            Card(id: 970 + $0.offset, rank: .jack, suit: $0.element)
        }

        let captured = await moment(
            model, absorbing: [.snackoo(by: "ai0", kind: .threeOfAKind(.jack), cards: jacks)]
        )
        let shown = try XCTUnwrap(captured, "No celebration appeared")
        XCTAssertEqual(
            shown.cards.map(\.id), jacks.map(\.id),
            "The celebration has to carry the cards being declared"
        )
        XCTAssertFalse(shown.isYours)
    }

    func testAQueenSnackooShowsTheQueens() async throws {
        let model = await table()
        let queens = [Suit.spades, .hearts, .diamonds].enumerated().map {
            Card(id: 980 + $0.offset, rank: .queen, suit: $0.element)
        }

        let captured = await moment(
            model, absorbing: [.snackoo(by: "ai1", kind: .threeQueens, cards: queens)]
        )
        let shown = try XCTUnwrap(captured)
        XCTAssertEqual(shown.cards.count, 3)
        XCTAssertTrue(shown.cards.allSatisfy { $0.rank == .queen })
    }

    /// And the engine actually fills them in — the event is where they come from.
    func testTheEngineNamesTheCardsItDiscarded() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human), ("c", "C", .human)],
            dealerIndex: 2, cardsDealt: 7, seed: 313
        )
        engine._finishWellSelectionForTesting()

        var state = engine.state
        let id = state.currentPlayer.id
        let seat = try XCTUnwrap(state.index(of: id))
        let sevens = [Suit.spades, Suit.hearts, Suit.clubs].enumerated().map {
            Card(id: 990 + $0.offset, rank: .seven, suit: $0.element)
        }
        state.players[seat].hand = sevens
        engine._replaceStateForTesting(state)

        let events = try engine.declareSnackoo(by: id, kind: .threeOfAKind(.seven))
        guard case .snackoo(_, _, let cards)? = events.first(where: {
            if case .snackoo = $0 { return true }
            return false
        }) else {
            XCTFail("Expected a Snackoo event")
            return
        }
        XCTAssertEqual(Set(cards.map(\.id)), Set(sevens.map(\.id)))
    }
}
