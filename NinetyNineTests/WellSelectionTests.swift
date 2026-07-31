//
//  WellSelectionTests.swift
//  Banking two of your own cards as the well.
//
//  The well used to be dealt face-down off the top of the deck — nobody chose
//  it, and it cost you nothing to have one. Now it comes out of your own deal,
//  which changes two things at once: what you bank is what you give up holding,
//  and the size of the deal is really a measure of how much *choice* you get.
//

import XCTest
@testable import NinetyNine

final class WellSelectionTests: XCTestCase {

    private func dealt(_ cardsDealt: Int = 7, players: Int = 3, seed: UInt32 = 4242) throws -> GameEngine {
        let ids = ["a", "b", "c", "d", "e", "f"].prefix(players)
        return try GameEngine(
            seats: ids.enumerated().map { ($0.element, "P\($0.offset)", .human) },
            dealerIndex: players - 1,
            cardsDealt: cardsDealt,
            seed: seed
        )
    }

    // MARK: - The phase

    func testEverythingIsDealtToTheHandAndNobodyStartsWithAWell() throws {
        let engine = try dealt(7)
        XCTAssertTrue(engine.state.isChoosingWells)
        for player in engine.state.players {
            XCTAssertEqual(player.hand.count, 7)
            XCTAssertTrue(player.well.isEmpty, "The well is chosen out of the deal, not dealt on top of it")
        }
        XCTAssertEqual(engine.state.drawPile.count, 52 - 3 * 7)
    }

    func testTheQueueRunsInDealOrderStartingLeftOfTheDealer() throws {
        let engine = try dealt(7, players: 3)   // dealer is "c"
        XCTAssertEqual(engine.state.wellSelectionQueue, ["a", "b", "c"])
        XCTAssertEqual(engine.state.wellChooserID, "a")
    }

    func testBankingTakesTheChosenCardsOutOfTheHand() throws {
        let engine = try dealt(7)
        let before = try XCTUnwrap(engine.state.player(id: "a")).hand
        let banked = [before[0].id, before[3].id]

        let events = try engine.chooseWell(cardIDs: banked, by: "a")

        let after = try XCTUnwrap(engine.state.player(id: "a"))
        XCTAssertEqual(after.hand.count, 5, "Seven dealt, two banked")
        XCTAssertEqual(Set(after.well.map(\.id)), Set(banked))
        for id in banked {
            XCTAssertFalse(after.hand.contains { $0.id == id }, "A banked card can't still be in hand")
        }
        XCTAssertTrue(events.contains(.wellChosen(by: "a", count: 2)))
    }

    func testPlayCannotBeginUntilEveryoneHasBanked() throws {
        let engine = try dealt(7)
        let a = try XCTUnwrap(engine.state.player(id: "a"))
        XCTAssertThrowsError(
            try engine.play(cardID: a.hand[0].id, by: "a", declaration: .plain)
        ) { XCTAssertEqual($0 as? GameError, .notChoosingWells) }

        for id in ["a", "b", "c"] {
            let hand = try XCTUnwrap(engine.state.player(id: id)).hand
            try engine.chooseWell(cardIDs: [hand[0].id, hand[1].id], by: id)
        }
        XCTAssertFalse(engine.state.isChoosingWells)
    }

    func testOnlyTheQueuedPlayerMayBank() throws {
        let engine = try dealt(7)
        let b = try XCTUnwrap(engine.state.player(id: "b"))
        XCTAssertThrowsError(
            try engine.chooseWell(cardIDs: [b.hand[0].id, b.hand[1].id], by: "b")
        ) { XCTAssertEqual($0 as? GameError, .notYourTurn) }
    }

    func testYouMustBankExactlyTwoDistinctCardsYouHold() throws {
        let engine = try dealt(7)
        let hand = try XCTUnwrap(engine.state.player(id: "a")).hand

        XCTAssertThrowsError(try engine.chooseWell(cardIDs: [hand[0].id], by: "a")) {
            XCTAssertEqual($0 as? GameError, .wrongWellSize(expected: 2))
        }
        XCTAssertThrowsError(
            try engine.chooseWell(cardIDs: [hand[0].id, hand[1].id, hand[2].id], by: "a")
        ) { XCTAssertEqual($0 as? GameError, .wrongWellSize(expected: 2)) }
        // The same card twice is not two cards.
        XCTAssertThrowsError(try engine.chooseWell(cardIDs: [hand[0].id, hand[0].id], by: "a")) {
            XCTAssertEqual($0 as? GameError, .wrongWellSize(expected: 2))
        }
        XCTAssertThrowsError(try engine.chooseWell(cardIDs: [hand[0].id, 9_999], by: "a")) {
            XCTAssertEqual($0 as? GameError, .cardNotInHand)
        }
        // And the hand is untouched by any of those refusals.
        XCTAssertEqual(try XCTUnwrap(engine.state.player(id: "a")).hand.count, 7)
    }

    func testBankingTwiceIsRefused() throws {
        let engine = try dealt(7)
        let hand = try XCTUnwrap(engine.state.player(id: "a")).hand
        try engine.chooseWell(cardIDs: [hand[0].id, hand[1].id], by: "a")
        XCTAssertThrowsError(
            try engine.chooseWell(cardIDs: [hand[2].id, hand[3].id], by: "a")
        ) { XCTAssertEqual($0 as? GameError, .notYourTurn) }
    }

    // MARK: - What the deal is really buying

    /// The author's example: deal five, bank two, open with three — and draw two
    /// on your first turn because the sustaining hand is five.
    func testASmallDealOpensShortAndIsToppedUpOnTheFirstTurn() throws {
        let engine = try dealt(5)
        for id in ["a", "b", "c"] {
            let hand = try XCTUnwrap(engine.state.player(id: id)).hand
            XCTAssertEqual(hand.count, 5)
            try engine.chooseWell(cardIDs: [hand[0].id, hand[1].id], by: id)
        }

        let leader = engine.state.currentPlayer
        XCTAssertEqual(
            leader.hand.count, Rules.sustainingHandCap,
            "The player on lead is topped up to five before they act"
        )
        for player in engine.state.players where player.id != leader.id {
            XCTAssertEqual(player.hand.count, 3, "The others still hold three until their turn")
        }
    }

    /// And when their turn arrives, they get theirs.
    func testEveryPlayerIsToppedUpWhenTheirTurnArrives() throws {
        let engine = try dealt(5)
        for id in ["a", "b", "c"] {
            let hand = try XCTUnwrap(engine.state.player(id: id)).hand
            try engine.chooseWell(cardIDs: [hand[0].id, hand[1].id], by: id)
        }
        let leader = engine.state.currentPlayer.id
        // Force the turn on without caring how.
        try engine.skip(by: leader)
        XCTAssertEqual(
            engine.state.currentPlayer.hand.count, Rules.sustainingHandCap,
            "The next player is topped up too"
        )
    }

    /// The smallest legal deal leaves no decision at all — you bank two of
    /// three. That's the cost of a tight deal, and it should be visible.
    func testTheSmallestDealLeavesNoChoice() throws {
        let engine = try dealt(3)
        let hand = try XCTUnwrap(engine.state.player(id: "a")).hand
        XCTAssertEqual(hand.count, 3)
        try engine.chooseWell(cardIDs: [hand[0].id, hand[1].id], by: "a")
        XCTAssertEqual(try XCTUnwrap(engine.state.player(id: "a")).hand.count, 1)
    }

    // MARK: - Determinism

    /// The choice is an action, so a peer replaying the log has to land on the
    /// same wells. If it weren't logged, every client would deal itself a
    /// different well and the match would diverge on the first draw.
    func testTheChoiceReplaysFromTheActionLog() throws {
        let seats: [(String, String, PlayerState.PlayerKind)] = [
            ("a", "A", .human), ("b", "B", .human), ("c", "C", .human),
        ]
        let source = try GameEngine(seats: seats, dealerIndex: 2, cardsDealt: 7, seed: 5150)

        var log: [SubmittedAction] = []
        var sequence = 0
        for id in ["a", "b", "c"] {
            let hand = try XCTUnwrap(source.state.player(id: id)).hand
            // Deliberately not the first two, so a replay that ignored the
            // action and guessed would land somewhere else.
            let action = PlayerAction.chooseWell(cardIDs: [hand[2].id, hand[4].id])
            let submitted = SubmittedAction(playerID: id, action: action, sequence: sequence)
            sequence += 1
            try source.apply(submitted)
            log.append(submitted)
        }

        let replay = try GameEngine(seats: seats, dealerIndex: 2, cardsDealt: 7, seed: 5150)
        for entry in log { try replay.apply(entry) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(replay.state), try encoder.encode(source.state))
    }

    // MARK: - The AI's choice

    func testEveryDifficultyBanksTwoCardsItActuallyHolds() throws {
        let engine = try dealt(9)
        let hand = try XCTUnwrap(engine.state.player(id: "a")).hand
        for difficulty in Difficulty.allCases {
            let chosen = AIPlayer(difficulty: difficulty).chooseWell(from: hand)
            XCTAssertEqual(chosen.count, 2, "\(difficulty) banked \(chosen.count)")
            XCTAssertEqual(Set(chosen).count, 2, "\(difficulty) banked the same card twice")
            for id in chosen {
                XCTAssertTrue(hand.contains { $0.id == id }, "\(difficulty) banked a card it doesn't hold")
            }
        }
    }

    func testAThinHandIsBankedWholeRatherThanCrashing() {
        let two = [Card(id: 1, rank: .king, suit: .spades), Card(id: 2, rank: .four, suit: .hearts)]
        for difficulty in Difficulty.allCases {
            XCTAssertEqual(Set(AIPlayer(difficulty: difficulty).chooseWell(from: two)), [1, 2])
        }
    }

    /// Sharp insures itself: it banks the cards most likely to still be legal
    /// when it's cornered, which is the whole point of having a well.
    func testSharpBanksTheCardsMostLikelyToRescueIt() {
        let hand = [
            Card(id: 1, rank: .king, suit: .spades),
            Card(id: 2, rank: .seven, suit: .hearts),
            Card(id: 3, rank: .jack, suit: .clubs),
            Card(id: 4, rank: .queen, suit: .diamonds),
            Card(id: 5, rank: .six, suit: .spades),
        ]
        let chosen = Set(AIPlayer(difficulty: .sharp).chooseWell(from: hand))
        XCTAssertEqual(chosen, [4, 3], "A Queen is never blocked and a Jack can't bust")
    }
}
