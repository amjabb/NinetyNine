//
//  EngineTests.swift
//  Rule-by-rule coverage of the 99 engine.
//
//  Tests build states directly where a specific board is needed — going through
//  a real deal to reach "tally is 99 and the last card was the 9 of hearts"
//  would be slow and fragile.
//

import XCTest
@testable import NinetyNine

final class EngineTests: XCTestCase {

    // MARK: - Helpers

    private func card(_ rank: Rank, _ suit: Suit, id: Int = 900) -> Card {
        Card(id: id, rank: rank, suit: suit)
    }

    /// A minimal two-player board with full control over tally and flags.
    private func board(
        tally: Int = 0,
        hand: [Card] = [],
        suitLock: Suit? = nil,
        forcedNegative: Bool = false,
        pendingNineSuit: Suit? = nil,
        well: [Card] = [],
        handCap: Int = 5
    ) -> GameState {
        var alice = PlayerState(id: "a", name: "Alice", kind: .human, handCap: handCap)
        alice.hand = hand
        alice.well = well
        let bob = PlayerState(id: "b", name: "Bob", kind: .ai(.sharp), handCap: handCap)

        var state = GameState(
            players: [alice, bob],
            currentPlayerIndex: 0,
            dealerID: "b",
            cardsDealt: handCap
        )
        state.tally = tally
        state.forcedNegativeNext = forcedNegative
        state.pendingNineSuit = pendingNineSuit
        if let suitLock { state.suitLock = SuitLock(suit: suitLock, setByPlayerID: "b") }
        return state
    }

    private func effect(_ rank: Rank, _ suit: Suit, _ declaration: Declaration = .plain, in state: GameState) -> Result<CardEffect, IllegalReason> {
        Rules.resolve(card: card(rank, suit), declaration: declaration, in: state)
    }

    private func assertLegal(
        _ result: Result<CardEffect, IllegalReason>,
        tally expected: Int,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success(let e):
            XCTAssertEqual(e.newTally, expected, message, file: file, line: line)
        case .failure(let reason):
            XCTFail("Expected legal (\(expected)) but got: \(reason.explanation). \(message)", file: file, line: line)
        }
    }

    private func assertIllegal(
        _ result: Result<CardEffect, IllegalReason>,
        _ expected: IllegalReason? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success(let e):
            XCTFail("Expected illegal but it resolved to \(e.newTally)", file: file, line: line)
        case .failure(let reason):
            if let expected { XCTAssertEqual(reason, expected, file: file, line: line) }
        }
    }

    // MARK: - Card values

    func testPlainNumberCardsAddFaceValue() {
        let state = board(tally: 40)
        assertLegal(effect(.two, .spades, in: state), tally: 42)
        assertLegal(effect(.seven, .clubs, in: state), tally: 47)
        assertLegal(effect(.king, .hearts, in: state), tally: 50)
    }

    func testJackIsZeroAndFourIsZeroButReverses() {
        let state = board(tally: 50)
        assertLegal(effect(.jack, .spades, in: state), tally: 50)

        switch effect(.four, .spades, in: state) {
        case .success(let e):
            XCTAssertEqual(e.newTally, 50)
            XCTAssertTrue(e.reversesDirection)
        case .failure(let r): XCTFail(r.explanation)
        }
    }

    func testAceIsOneOrEleven() {
        let state = board(tally: 50)
        assertLegal(effect(.ace, .spades, .ace(.one), in: state), tally: 51)
        assertLegal(effect(.ace, .spades, .ace(.eleven), in: state), tally: 61)
    }

    func testAceWithoutDeclarationIsRejected() {
        let state = board(tally: 50)
        assertIllegal(effect(.ace, .spades, .plain, in: state))
    }

    func testTenSubtractsTen() {
        let state = board(tally: 50)
        assertLegal(effect(.ten, .spades, in: state), tally: 40)
    }

    // MARK: - The 99 ceiling

    func testCardThatWouldExceed99IsIllegal() {
        let state = board(tally: 95)
        assertIllegal(effect(.six, .spades, in: state), .wouldExceed99(resulting: 101))
        assertLegal(effect(.four, .spades, in: state), tally: 95)
    }

    func testLandingExactlyOn99IsLegal() {
        let state = board(tally: 89)
        assertLegal(effect(.ten, .spades, in: state), tally: 79)
        assertLegal(effect(.king, .spades, in: state), tally: 99)
    }

    func testNineSlamsTallyTo99FromAnyPositiveTally() {
        assertLegal(effect(.nine, .spades, in: board(tally: 0)), tally: 99)
        assertLegal(effect(.nine, .spades, in: board(tally: 71)), tally: 99)
    }

    func testNineIsIllegalWhileNegative() {
        assertIllegal(effect(.nine, .spades, in: board(tally: -10)), .nineWhileNegative)
    }

    // MARK: - The 100 exception

    func testMatchingAceAfterNinePushesTo100() {
        let state = board(tally: 99, pendingNineSuit: .hearts)
        switch effect(.ace, .hearts, .ace(.one), in: state) {
        case .success(let e):
            XCTAssertEqual(e.newTally, 100)
            XCTAssertTrue(e.completesHundred)
            XCTAssertTrue(e.setsForcedNegativeNext)
        case .failure(let r): XCTFail(r.explanation)
        }
    }

    func testWrongSuitAceCannotReach100() {
        let state = board(tally: 99, pendingNineSuit: .hearts)
        assertIllegal(effect(.ace, .spades, .ace(.one), in: state), .wouldExceed99(resulting: 100))
    }

    func testAceAsElevenCannotReach100() {
        let state = board(tally: 99, pendingNineSuit: .hearts)
        assertIllegal(effect(.ace, .hearts, .ace(.eleven), in: state), .wouldExceed99(resulting: 110))
    }

    func test100ExceptionRequiresTheNineToBeImmediatelyPrior() {
        // Same tally, but no pending nine — the window has closed.
        let state = board(tally: 99, pendingNineSuit: nil)
        assertIllegal(effect(.ace, .hearts, .ace(.one), in: state), .wouldExceed99(resulting: 100))
    }

    // MARK: - Forced-negative slot

    func testForcedNegativeInvertsCardValues() {
        let state = board(tally: 100, forcedNegative: true)
        assertLegal(effect(.king, .spades, in: state), tally: 90)
        assertLegal(effect(.seven, .spades, in: state), tally: 93)
        assertLegal(effect(.ace, .spades, .ace(.eleven), in: state), tally: 89)
    }

    func testTenAndNineCannotTakeTheForcedNegativeSlot() {
        let state = board(tally: 100, forcedNegative: true)
        assertIllegal(effect(.ten, .spades, in: state), .tenInForcedNegativeSlot)
        assertIllegal(effect(.nine, .spades, in: state), .nineInForcedNegativeSlot)
    }

    func testZeroValueCardsCannotSitAt100() {
        // A Jack or 4 would leave the tally at 100, which stays over the ceiling.
        let state = board(tally: 100, forcedNegative: true)
        assertIllegal(effect(.jack, .spades, in: state), .wouldExceed99(resulting: 100))
        assertIllegal(effect(.four, .spades, in: state), .wouldExceed99(resulting: 100))
    }

    func testQueenCanImpersonateAnEightInTheForcedNegativeSlot() {
        let state = board(tally: 100, forcedNegative: true)
        switch effect(.queen, .clubs, .queen(as: .eight, lockSuit: .diamonds), in: state) {
        case .success(let e):
            XCTAssertEqual(e.newTally, 92)
            XCTAssertEqual(e.locksSuit, .diamonds)
        case .failure(let r): XCTFail(r.explanation)
        }
    }

    // MARK: - Negative play

    func testTenFromZeroGoesNegative() {
        assertLegal(effect(.ten, .spades, in: board(tally: 0)), tally: -10)
    }

    /// Zero is a one-way gate: you may drop through it from anywhere, but you
    /// have to land on it exactly to climb back out. Diving is cheap; leaving
    /// isn't.
    func testATenDropsBelowZeroFromAnyTally() {
        assertLegal(effect(.ten, .spades, in: board(tally: 8)), tally: -2)
        assertLegal(effect(.ten, .spades, in: board(tally: 3)), tally: -7)
        assertLegal(effect(.ten, .spades, in: board(tally: 55)), tally: 45)
    }

    func testClimbingOutOfTheNegativesStillHasToLandOnZero() {
        assertIllegal(
            effect(.five, .spades, in: board(tally: -2)),
            .mustLandOnZeroFirst(resulting: 3)
        )
        assertLegal(effect(.two, .spades, in: board(tally: -2)), tally: 0)
    }

    func testCanPushFurtherNegativeWithAnotherTen() {
        assertLegal(effect(.ten, .spades, in: board(tally: -10)), tally: -20)
    }

    func testMustLandExactlyOnZeroComingOutOfNegative() {
        let state = board(tally: -10)
        // A King is exactly the 10 needed to land on zero.
        assertLegal(effect(.king, .spades, in: state), tally: 0)
        // Overshooting zero into the positives is not allowed.
        assertIllegal(
            effect(.seven, .spades, in: board(tally: -5)),
            .mustLandOnZeroFirst(resulting: 2)
        )
        assertIllegal(
            effect(.ace, .spades, .ace(.eleven), in: state),
            .mustLandOnZeroFirst(resulting: 1)
        )
    }

    func testClimbingTowardZeroWithoutOvershootingIsLegal() {
        assertLegal(effect(.five, .spades, in: board(tally: -20)), tally: -15)
        assertLegal(effect(.jack, .spades, in: board(tally: -20)), tally: -20)
    }

    // MARK: - Suit lock

    func testOnlyLockedSuitIsLegal() {
        let state = board(tally: 20, suitLock: .hearts)
        assertLegal(effect(.three, .hearts, in: state), tally: 23)
        assertIllegal(effect(.three, .spades, in: state), .suitLocked(.hearts))
    }

    func testEightOfWrongSuitCannotBePlayedUnderALock() {
        let state = board(tally: 20, suitLock: .hearts)
        assertIllegal(effect(.eight, .spades, .lock(.clubs), in: state), .suitLocked(.hearts))
    }

    func testEightOfLockedSuitMayRenameTheLock() {
        let state = board(tally: 20, suitLock: .hearts)
        switch effect(.eight, .hearts, .lock(.clubs), in: state) {
        case .success(let e):
            XCTAssertEqual(e.newTally, 28)
            XCTAssertEqual(e.locksSuit, .clubs)
        case .failure(let r): XCTFail(r.explanation)
        }
    }

    /// Superseded rule. This test used to assert that a Queen obeyed the lock
    /// like any other card; the author's ruling is that a Queen is wild for
    /// *suit* as well as rank, so a lock never blocks one.
    func testAQueenIgnoresTheSuitLockWhateverItsPrintedSuit() {
        let state = board(tally: 20, suitLock: .hearts)
        assertLegal(effect(.queen, .hearts, .queen(as: .king), in: state), tally: 30)
        assertLegal(effect(.queen, .spades, .queen(as: .king), in: state), tally: 30)
        assertLegal(effect(.queen, .clubs, .queen(as: .king), in: state), tally: 30)
        // Every other card is still judged on its printed suit.
        assertIllegal(effect(.king, .spades, .plain, in: state), .suitLocked(.hearts))
    }

    func testSkippingLiftsTheLock() throws {
        let engine = try GameEngine(
            seats: [("a", "Alice", .human), ("b", "Bob", .ai(.sharp)), ("c", "Cara", .ai(.sharp))],
            dealerIndex: 0,
            cardsDealt: 5,
            seed: 4242
        )
        engine._finishWellSelectionForTesting()
        // Force a lock, then skip and confirm it lifts.
        let current = engine.state.currentPlayer.id
        let events = try engine.skip(by: current)
        XCTAssertTrue(events.contains(.turnSkipped(by: current)))
        XCTAssertNil(engine.state.suitLock)
    }

    // MARK: - Queen wildness

    func testQueenCanCopyAnyRank() {
        let state = board(tally: 50)
        assertLegal(effect(.queen, .spades, .queen(as: .king), in: state), tally: 60)
        assertLegal(effect(.queen, .spades, .queen(as: .ten), in: state), tally: 40)
        assertLegal(effect(.queen, .spades, .queen(as: .nine), in: state), tally: 99)
        assertLegal(effect(.queen, .spades, .queen(as: .ace, aceValue: .eleven), in: state), tally: 61)
    }

    func testQueenCannotCopyAQueen() {
        let state = board(tally: 50)
        assertIllegal(effect(.queen, .spades, .queen(as: .queen), in: state))
        assertIllegal(effect(.queen, .spades, .plain, in: state))
    }

    func testQueenCopyingFourReverses() {
        let state = board(tally: 50)
        switch effect(.queen, .spades, .queen(as: .four), in: state) {
        case .success(let e): XCTAssertTrue(e.reversesDirection)
        case .failure(let r): XCTFail(r.explanation)
        }
    }

    // MARK: - Legality enumeration

    func testLegalDeclarationsForAceCoversBothValues() {
        let state = board(tally: 50)
        XCTAssertEqual(Rules.legalDeclarations(for: card(.ace, .spades), in: state).count, 2)
    }

    func testLegalDeclarationsForAceNearCeilingDropsEleven() {
        let state = board(tally: 95)
        let declarations = Rules.legalDeclarations(for: card(.ace, .spades), in: state)
        XCTAssertEqual(declarations, [.ace(.one)])
    }

    func testLegalDeclarationsForEightCoverEverySuitPlusDecliningToLock() {
        let state = board(tally: 10)
        let declarations = Rules.legalDeclarations(for: card(.eight, .spades), in: state)
        XCTAssertEqual(declarations.count, 5, "Four suits, plus locking nothing")
        XCTAssertTrue(
            declarations.contains(.lockNothing),
            "Locking is an option, not an obligation"
        )
        for suit in Suit.allCases {
            XCTAssertTrue(declarations.contains(.lock(suit)), "Missing \(suit)")
        }
    }

    func testDeadCardHasNoLegalDeclarations() {
        let state = board(tally: 99)
        XCTAssertTrue(Rules.legalDeclarations(for: card(.two, .spades), in: state).isEmpty)
        XCTAssertFalse(Rules.isPlayable(card(.two, .spades), in: state))
    }

    func testBlockingReasonPrefersTheSuitLockExplanation() {
        let state = board(tally: 20, suitLock: .hearts)
        XCTAssertEqual(Rules.blockingReason(for: card(.two, .spades), in: state), .suitLocked(.hearts))
    }

    // MARK: - What the dealer may deal

    /// The well now comes *out* of the deal rather than on top of it, so the
    /// whole deck is available: players × cardsDealt ≤ 52.
    func testTheBiggestLegalDealIsWhatTheDeckCanCover() {
        XCTAssertEqual(Rules.maxCardsDealt(forPlayerCount: 2), 12)
        XCTAssertEqual(Rules.maxCardsDealt(forPlayerCount: 3), 12)
        XCTAssertEqual(Rules.maxCardsDealt(forPlayerCount: 4), 12)
        XCTAssertEqual(Rules.maxCardsDealt(forPlayerCount: 5), 10)
        XCTAssertEqual(Rules.maxCardsDealt(forPlayerCount: 6), 8)

        for count in 2...6 {
            XCTAssertLessThanOrEqual(
                count * Rules.maxCardsDealt(forPlayerCount: count), 52,
                "\(count) players at the maximum deal would need more than a deck"
            )
        }
    }

    /// Two of whatever you're dealt go to the well, so three is the smallest
    /// deal that leaves a hand at all.
    func testTheSmallestLegalDealStillLeavesAHand() {
        XCTAssertEqual(Rules.minCardsDealt, 3)
        XCTAssertEqual(Rules.minCardsDealt - Rules.wellSize, 1)
    }

    // MARK: - Dealing

    func testDealGivesEveryoneAHandAWellAndLeavesTheRestToDraw() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp)), ("c", "C", .ai(.sharp)), ("d", "D", .ai(.sharp))],
            dealerIndex: 0,
            cardsDealt: 7,
            seed: 99
        )
        // Before anyone chooses: it's all in hand, and nobody has a well.
        XCTAssertTrue(engine.state.isChoosingWells)
        for player in engine.state.players {
            XCTAssertEqual(player.hand.count, 7, "The whole deal starts in hand")
            XCTAssertTrue(player.well.isEmpty, "The well is chosen, not dealt")
        }

        engine._finishWellSelectionForTesting()
        let state = engine.state
        XCTAssertEqual(state.players.count, 4)
        XCTAssertFalse(state.isChoosingWells)
        for player in state.players {
            XCTAssertEqual(player.hand.count, 5, "Dealt seven, banked two, holding five")
            XCTAssertEqual(player.well.count, 2)
            XCTAssertTrue(player.poisonPile.isEmpty)
            // The cap is the *sustaining* size, not the deal size — dealt seven,
            // you play down to five and hold there.
            XCTAssertEqual(player.handCap, Rules.sustainingHandCap)
        }
        XCTAssertEqual(state.drawPile.count, 52 - 4 * 7)
        XCTAssertEqual(state.tally, 0)
        XCTAssertTrue(state.discardPile.isEmpty, "There is no starting discard in 99")
    }

    func testFirstTurnGoesToTheSeatAfterTheDealer() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp)), ("c", "C", .ai(.sharp))],
            dealerIndex: 0,
            cardsDealt: 5,
            seed: 1
        )
        engine._finishWellSelectionForTesting()
        XCTAssertEqual(engine.state.currentPlayer.id, "b")
    }

    func testEveryCardIsDealtExactlyOnce() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 0,
            cardsDealt: 12,
            seed: 7
        )
        engine._finishWellSelectionForTesting()
        let state = engine.state
        var ids: [Int] = state.drawPile.map(\.id)
        for player in state.players {
            ids += player.hand.map(\.id) + player.well.map(\.id)
        }
        XCTAssertEqual(ids.count, 52)
        XCTAssertEqual(Set(ids).count, 52, "No duplicate cards")
    }

    func testInvalidPlayerCountAndDealAreRejected() {
        XCTAssertThrowsError(try GameEngine(seats: [("a", "A", .human)], dealerIndex: 0, cardsDealt: 5))
        // Two cards would be all well and no hand.
        XCTAssertThrowsError(try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))], dealerIndex: 0, cardsDealt: 2
        ))
        XCTAssertThrowsError(try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))], dealerIndex: 0, cardsDealt: 13
        ))
        // Four is legal now — two to the well and a hand of two, topped up on
        // the first turn.
        XCTAssertNoThrow(try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))], dealerIndex: 0, cardsDealt: 4
        ))
    }

    func testSeededDealsAreReproducible() throws {
        func firstHand() throws -> [Int] {
            let engine = try GameEngine(
                seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
                dealerIndex: 0, cardsDealt: 6, seed: 20250729
            )
            engine._finishWellSelectionForTesting()
            return engine.state.players[0].hand.map(\.id)
        }
        XCTAssertEqual(try firstHand(), try firstHand())
    }

    // MARK: - Turn flow

    func testPlayingACardAdvancesTheTurnAndRefillsTheHand() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 0, cardsDealt: 5, seed: 3
        )
        engine._finishWellSelectionForTesting()
        let mover = engine.state.currentPlayer
        let playable = try XCTUnwrap(mover.hand.first { Rules.isPlayable($0, in: engine.state) })
        let declaration = try XCTUnwrap(Rules.legalDeclarations(for: playable, in: engine.state).first)

        try engine.play(cardID: playable.id, by: mover.id, declaration: declaration)

        XCTAssertNotEqual(engine.state.currentPlayer.id, mover.id, "Turn should pass")
        let refilled = try XCTUnwrap(engine.state.player(id: mover.id))
        XCTAssertEqual(
            refilled.hand.count, Rules.sustainingHandCap,
            "Hand refills to the sustaining cap"
        )
        XCTAssertEqual(engine.state.discardPile.count, 1)
    }

    func testPlayingOutOfTurnThrows() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 0, cardsDealt: 5, seed: 11
        )
        engine._finishWellSelectionForTesting()
        let waiting = engine.state.players.first { $0.id != engine.state.currentPlayer.id }!
        let anyCard = waiting.hand[0]
        XCTAssertThrowsError(try engine.play(cardID: anyCard.id, by: waiting.id, declaration: .plain)) { error in
            XCTAssertEqual(error as? GameError, .notYourTurn)
        }
    }

    func testSkipCreatesADoublePlayDebtOnTheNextTurn() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 0, cardsDealt: 5, seed: 5
        )
        engine._finishWellSelectionForTesting()
        let skipper = engine.state.currentPlayer.id
        try engine.skip(by: skipper)
        XCTAssertTrue(try XCTUnwrap(engine.state.player(id: skipper)).owesExtraPlay)

        // Return the turn to the skipper.
        let other = engine.state.currentPlayer
        if let playable = other.hand.first(where: { Rules.isPlayable($0, in: engine.state) }),
           let declaration = Rules.legalDeclarations(for: playable, in: engine.state).first {
            try engine.play(cardID: playable.id, by: other.id, declaration: declaration)
        } else {
            try engine.skip(by: other.id)
        }

        XCTAssertEqual(engine.state.currentPlayer.id, skipper)
        XCTAssertEqual(engine.state.playsRemainingThisTurn, 2, "Skip debt is two plays")
        XCTAssertTrue(engine.state.turnStartedWithDebt)
    }

    func testCannotSkipTwiceInARow() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 0, cardsDealt: 5, seed: 5
        )
        engine._finishWellSelectionForTesting()
        let skipper = engine.state.currentPlayer.id
        try engine.skip(by: skipper)
        let other = engine.state.currentPlayer.id
        try engine.skip(by: other)
        // Back to the first skipper, who now owes two and may not skip again.
        XCTAssertEqual(engine.state.currentPlayer.id, skipper)
        XCTAssertThrowsError(try engine.skip(by: skipper)) { error in
            XCTAssertEqual(error as? GameError, .cannotSkipWhileRepayingDebt)
        }
    }

    func testFourReversesDirectionWithThreePlayersButNotTwo() throws {
        var state = board(tally: 10)
        switch effect(.four, .spades, in: state) {
        case .success(let e): XCTAssertTrue(e.reversesDirection)
        case .failure(let r): XCTFail(r.explanation)
        }
        // The engine, not the resolver, applies the two-player no-op.
        state.players.append(PlayerState(id: "c", name: "C", kind: .ai(.sharp), handCap: 5))
        XCTAssertEqual(state.activePlayers.count, 3)
    }

    // MARK: - The well

    func testWellRequiresBeingStuck() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 0, cardsDealt: 5, seed: 8
        )
        engine._finishWellSelectionForTesting()
        // At tally 0 with a full hand there is certainly a legal play.
        XCTAssertTrue(Rules.hasLegalPlay(playerID: engine.state.currentPlayer.id, in: engine.state))
        XCTAssertThrowsError(try engine.drawFromWell(by: engine.state.currentPlayer.id)) { error in
            XCTAssertEqual(error as? GameError, .mustPlayFromHandFirst)
        }
    }

    func testTurnOptionsOfferWellAndSkipOnlyWhenStuck() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 0, cardsDealt: 5, seed: 8
        )
        engine._finishWellSelectionForTesting()
        let options = engine.currentPlayerOptions
        XCTAssertTrue(options.canPlayFromHand)
        XCTAssertFalse(options.canUseWell)
        XCTAssertFalse(options.canSkip)
        XCTAssertFalse(options.isStranded)
    }

    // MARK: - Snackoo

    func testSnackooDetectionIgnoresQueens() {
        var player = PlayerState(id: "a", name: "A", kind: .human, handCap: 6)
        player.hand = [
            card(.queen, .spades, id: 1), card(.queen, .hearts, id: 2), card(.queen, .clubs, id: 3),
            card(.five, .spades, id: 4), card(.five, .hearts, id: 5), card(.five, .clubs, id: 6),
        ]
        XCTAssertEqual(Rules.snackooRanksInHand(for: player), [.five])
    }

    func testPoisonSnackooNeedsThreeQueens() {
        var player = PlayerState(id: "a", name: "A", kind: .human, handCap: 5)
        player.poisonPile = [card(.queen, .spades, id: 1), card(.queen, .hearts, id: 2)]
        XCTAssertFalse(Rules.canSnackooPoison(player))
        player.poisonPile.append(card(.queen, .clubs, id: 3))
        XCTAssertTrue(Rules.canSnackooPoison(player))
    }

    func testSnackooDiscardsThreeAndDrawsThree() throws {
        // Search seeds for a deal containing a three-of-a-kind rather than
        // skipping — this rule deserves real coverage on every run.
        var found: (engine: GameEngine, seat: Int, rank: Rank)?
        for seed in UInt32(1)...200 {
            let engine = try GameEngine(
                seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
                dealerIndex: 0, cardsDealt: 12, seed: seed
            )
            engine._finishWellSelectionForTesting()
            if let seat = engine.state.players.firstIndex(where: { !Rules.snackooRanksInHand(for: $0).isEmpty }),
               let rank = Rules.snackooRanksInHand(for: engine.state.players[seat]).first {
                found = (engine, seat, rank)
                break
            }
        }
        let (engine, seat, rank) = try XCTUnwrap(found, "No seed in 1...200 dealt a three-of-a-kind")
        let player = engine.state.players[seat]
        let before = player.hand.count
        let beforeOfRank = player.hand.filter { $0.rank == rank }.count

        try engine.declareSnackoo(by: player.id, kind: .threeOfAKind(rank))

        let after = try XCTUnwrap(engine.state.player(id: player.id))
        XCTAssertEqual(after.hand.filter { $0.rank == rank }.count, beforeOfRank - 3)
        XCTAssertEqual(after.hand.count, before, "Three out, three in")
    }

    func testSnackooWithoutATrioThrows() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 0, cardsDealt: 5, seed: 31
        )
        engine._finishWellSelectionForTesting()
        XCTAssertThrowsError(try engine.declareSnackoo(by: "a", kind: .threeQueens)) { error in
            XCTAssertEqual(error as? GameError, .snackooNotAvailable)
        }
    }

    // MARK: - Pressure metric

    func testPressureTracksTheTally() {
        XCTAssertEqual(board(tally: 0).pressure, 0)
        XCTAssertEqual(board(tally: -20).pressure, 0)
        XCTAssertEqual(board(tally: 99).pressure, 1, accuracy: 0.001)
        XCTAssertEqual(board(tally: 50).pressure, 50.0 / 99.0, accuracy: 0.001)
    }

    // MARK: - AI

    func testAIAlwaysProducesALegalMove() throws {
        for seed in [UInt32(1), 17, 512, 9001] {
            let engine = try GameEngine(
                seats: [("a", "A", .ai(.sharp)), ("b", "B", .ai(.ruthless))],
                dealerIndex: 0, cardsDealt: 6, seed: seed
            )
            engine._finishWellSelectionForTesting()
            let ai = AIPlayer(difficulty: .sharp)
            let move = try XCTUnwrap(ai.nextMove(for: engine.state.currentPlayer.id, engine: engine))
            if case .play(let cardID, let declaration) = move.kind {
                let card = try XCTUnwrap(engine.state.currentPlayer.hand.first { $0.id == cardID })
                switch Rules.resolve(card: card, declaration: declaration, in: engine.state) {
                case .success: break
                case .failure(let r): XCTFail("AI chose an illegal play: \(r.explanation)")
                }
            }
        }
    }

    func testAIGamesAlwaysTerminateWithAWinner() throws {
        // The real regression net: full self-play games must never deadlock,
        // throw, or end without a winner.
        for seed in [UInt32(3), 42, 777, 12345, 88888] {
            let engine = try GameEngine(
                seats: [
                    ("a", "A", .ai(.casual)),
                    ("b", "B", .ai(.sharp)),
                    ("c", "C", .ai(.ruthless)),
                ],
                dealerIndex: 0, cardsDealt: 6, seed: seed
            )
            engine._finishWellSelectionForTesting()
            var turns = 0
            while !engine.state.isOver && turns < 4000 {
                turns += 1
                let current = engine.state.currentPlayer
                let ai = AIPlayer(difficulty: current.kind.difficulty ?? .sharp)
                guard let move = ai.nextMove(for: current.id, engine: engine) else {
                    XCTFail("AI returned no move for seed \(seed)")
                    break
                }
                switch move.kind {
                case .play(let cardID, let declaration):
                    if engine.state.pendingWell?.card.id == cardID {
                        try engine.resolveWell(by: current.id, declaration: declaration)
                    } else {
                        try engine.play(cardID: cardID, by: current.id, declaration: declaration)
                    }
                case .useWell:
                    try engine.drawFromWell(by: current.id)
                case .skip:
                    try engine.skip(by: current.id)
                case .snackoo(let kind):
                    try engine.declareSnackoo(by: current.id, kind: kind)
                case .snackooWell:
                    try engine.snackooWellCard(by: current.id)
                case .concede:
                    if engine.state.pendingWell != nil {
                        try engine.concedeWellCard(by: current.id)
                    } else {
                        try engine.concedeStranded(by: current.id)
                    }
                }
            }
            XCTAssertTrue(engine.state.isOver, "Seed \(seed) did not finish in \(turns) turns")
            XCTAssertNotNil(engine.state.winnerID)
            XCTAssertEqual(engine.state.activePlayers.count, 1)
            XCTAssertNotNil(engine.state.firstEliminatedID)
        }
    }

    func testTallyNeverLeavesLegalBoundsAcrossSelfPlay() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .ai(.ruthless)), ("b", "B", .ai(.ruthless))],
            dealerIndex: 0, cardsDealt: 8, seed: 606
        )
        engine._finishWellSelectionForTesting()
        var turns = 0
        while !engine.state.isOver && turns < 4000 {
            turns += 1
            XCTAssertLessThanOrEqual(engine.state.tally, 100)
            let current = engine.state.currentPlayer
            let ai = AIPlayer(difficulty: .ruthless)
            guard let move = ai.nextMove(for: current.id, engine: engine) else { break }
            switch move.kind {
            case .play(let cardID, let declaration):
                if engine.state.pendingWell?.card.id == cardID {
                    try engine.resolveWell(by: current.id, declaration: declaration)
                } else {
                    try engine.play(cardID: cardID, by: current.id, declaration: declaration)
                }
            case .useWell: try engine.drawFromWell(by: current.id)
            case .skip: try engine.skip(by: current.id)
            case .snackoo(let kind): try engine.declareSnackoo(by: current.id, kind: kind)
                case .snackooWell: try engine.snackooWellCard(by: current.id)
            case .concede:
                    if engine.state.pendingWell != nil {
                        try engine.concedeWellCard(by: current.id)
                    } else {
                        try engine.concedeStranded(by: current.id)
                    }
            }
            // The tally may only exceed 99 in the single 100 slot.
            if engine.state.tally == 100 {
                XCTAssertTrue(engine.state.forcedNegativeNext)
            }
        }
    }

    func testEliminationReturnsCardsToCirculation() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .ai(.casual)), ("b", "B", .ai(.casual)), ("c", "C", .ai(.casual))],
            dealerIndex: 0, cardsDealt: 5, seed: 4711
        )
        engine._finishWellSelectionForTesting()
        var turns = 0
        while engine.state.activePlayers.count == 3 && turns < 4000 {
            turns += 1
            let current = engine.state.currentPlayer
            let ai = AIPlayer(difficulty: .casual)
            guard let move = ai.nextMove(for: current.id, engine: engine) else { break }
            switch move.kind {
            case .play(let cardID, let declaration):
                if engine.state.pendingWell?.card.id == cardID {
                    try engine.resolveWell(by: current.id, declaration: declaration)
                } else {
                    try engine.play(cardID: cardID, by: current.id, declaration: declaration)
                }
            case .useWell: try engine.drawFromWell(by: current.id)
            case .skip: try engine.skip(by: current.id)
            case .snackoo(let kind): try engine.declareSnackoo(by: current.id, kind: kind)
                case .snackooWell: try engine.snackooWellCard(by: current.id)
            case .concede:
                    if engine.state.pendingWell != nil {
                        try engine.concedeWellCard(by: current.id)
                    } else {
                        try engine.concedeStranded(by: current.id)
                    }
            }
        }
        guard let out = engine.state.players.first(where: { $0.isEliminated }) else {
            throw XCTSkip("No elimination occurred for this seed")
        }
        XCTAssertTrue(out.hand.isEmpty)
        XCTAssertTrue(out.well.isEmpty)
        XCTAssertTrue(out.poisonPile.isEmpty)
        XCTAssertEqual(out.eliminationRank, 1)
        XCTAssertEqual(engine.state.firstEliminatedID, out.id)
    }
}
