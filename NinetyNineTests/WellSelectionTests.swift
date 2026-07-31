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

    func testBankingTakesTheChosenPositionsOutOfTheHand() throws {
        let engine = try dealt(7)
        let before = try XCTUnwrap(engine.state.player(id: "a")).hand
        let expected = [before[0].id, before[3].id]

        let events = try engine.chooseWell(slots: [0, 3], by: "a")

        let after = try XCTUnwrap(engine.state.player(id: "a"))
        XCTAssertEqual(after.hand.count, 5, "Seven dealt, two banked")
        XCTAssertEqual(Set(after.well.map(\.id)), Set(expected))
        for id in expected {
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
            try engine.chooseWell(slots: [0, 1], by: id)
        }
        XCTAssertFalse(engine.state.isChoosingWells)
    }

    func testOnlyTheQueuedPlayerMayBank() throws {
        let engine = try dealt(7)
        XCTAssertThrowsError(
            try engine.chooseWell(slots: [0, 1], by: "b")
        ) { XCTAssertEqual($0 as? GameError, .notYourTurn) }
    }

    func testYouMustBankExactlyTwoDistinctPositionsYouWereDealt() throws {
        let engine = try dealt(7)

        XCTAssertThrowsError(try engine.chooseWell(slots: [0], by: "a")) {
            XCTAssertEqual($0 as? GameError, .wrongWellSize(expected: 2))
        }
        XCTAssertThrowsError(try engine.chooseWell(slots: [0, 1, 2], by: "a")) {
            XCTAssertEqual($0 as? GameError, .wrongWellSize(expected: 2))
        }
        // The same position twice is not two cards.
        XCTAssertThrowsError(try engine.chooseWell(slots: [0, 0], by: "a")) {
            XCTAssertEqual($0 as? GameError, .wrongWellSize(expected: 2))
        }
        XCTAssertThrowsError(try engine.chooseWell(slots: [0, 99], by: "a")) {
            XCTAssertEqual($0 as? GameError, .cardNotInHand)
        }
        XCTAssertThrowsError(try engine.chooseWell(slots: [0, -1], by: "a")) {
            XCTAssertEqual($0 as? GameError, .cardNotInHand)
        }
        // And the hand is untouched by any of those refusals.
        XCTAssertEqual(try XCTUnwrap(engine.state.player(id: "a")).hand.count, 7)
    }

    func testBankingTwiceIsRefused() throws {
        let engine = try dealt(7)
        try engine.chooseWell(slots: [0, 1], by: "a")
        XCTAssertThrowsError(
            try engine.chooseWell(slots: [0, 1], by: "a")
        ) { XCTAssertEqual($0 as? GameError, .notYourTurn) }
    }

    // MARK: - What the deal is really buying

    /// The author's example: deal five, bank two, open with three — and draw two
    /// on your first turn because the sustaining hand is five.
    func testASmallDealOpensShortAndIsToppedUpOnTheFirstTurn() throws {
        let engine = try dealt(5)
        for id in ["a", "b", "c"] {
            XCTAssertEqual(try XCTUnwrap(engine.state.player(id: id)).hand.count, 5)
            try engine.chooseWell(slots: [0, 1], by: id)
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
            try engine.chooseWell(slots: [0, 1], by: id)
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
        XCTAssertEqual(try XCTUnwrap(engine.state.player(id: "a")).hand.count, 3)
        try engine.chooseWell(slots: [0, 1], by: "a")
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
            // Deliberately not the first two, so a replay that ignored the
            // action and guessed would land somewhere else.
            let action = PlayerAction.chooseWell(slots: [2, 4])
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

    func testEveryDifficultyBanksTwoPositionsItWasDealt() {
        for difficulty in Difficulty.allCases {
            let chosen = AIPlayer(difficulty: difficulty).chooseWellSlots(dealtCount: 9)
            XCTAssertEqual(chosen.count, 2, "\(difficulty) banked \(chosen.count)")
            XCTAssertEqual(Set(chosen).count, 2, "\(difficulty) banked the same position twice")
            for slot in chosen {
                XCTAssertTrue((0..<9).contains(slot), "\(difficulty) picked slot \(slot) out of nine")
            }
        }
    }

    func testAThinDealIsBankedWholeRatherThanCrashing() {
        for difficulty in Difficulty.allCases {
            XCTAssertEqual(Set(AIPlayer(difficulty: difficulty).chooseWellSlots(dealtCount: 2)), [0, 1])
        }
    }

    /// The AI has to be as blind as the player. Its choice may only depend on
    /// how many cards it was dealt — if it could see the faces it would be
    /// cheating at the one decision nobody has information for.
    func testTheAICannotSeeWhatItIsBanking() {
        // The signature is the guarantee: a count goes in, positions come out,
        // and there is no way to pass it a card. This test exists so that adding
        // one has to be a deliberate act with a failing test attached.
        for difficulty in Difficulty.allCases {
            let first = AIPlayer(difficulty: difficulty).chooseWellSlots(dealtCount: 7)
            let second = AIPlayer(difficulty: difficulty).chooseWellSlots(dealtCount: 7)
            XCTAssertEqual(first, second, "Same deal size, same answer — nothing else can inform it")
        }
    }
}

// MARK: - The pick is blind

/// The well's whole value is that nobody knows what's in it, and that has to
/// hold for its owner too. Two separate ways it could leak, both pinned here:
/// the view a player is handed, and the action log every peer reads.
final class BlindWellTests: XCTestCase {

    private func dealt(_ cardsDealt: Int = 7) throws -> GameEngine {
        try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human), ("c", "C", .human)],
            dealerIndex: 2, cardsDealt: cardsDealt, seed: 2468
        )
    }

    func testYouCannotSeeYourOwnDealWhileChoosingYourWell() throws {
        let engine = try dealt(7)
        XCTAssertEqual(engine.state.wellChooserID, "a")

        let mine = engine.state.view(for: "a")
        XCTAssertTrue(
            mine.yourHand.isEmpty,
            "The chooser's own cards must not be in their view — they'd know their outs from turn one"
        )
        XCTAssertEqual(mine.wellChoiceCount, 7, "Only how many, not which")
        XCTAssertTrue(mine.youAreChoosingYourWell)
    }

    /// And it's given back the moment the well is banked.
    func testYourHandIsRevealedOnceYouveBanked() throws {
        let engine = try dealt(7)
        try engine.chooseWell(slots: [0, 1], by: "a")

        let mine = engine.state.view(for: "a")
        XCTAssertEqual(mine.yourHand.count, 5, "The five you kept are yours to see")
        XCTAssertEqual(mine.wellChoiceCount, 0)
        XCTAssertFalse(mine.youAreChoosingYourWell)
    }

    /// Nobody else can see a player's deal either, before or after.
    func testNobodyElseCanSeeTheDealBeingChosenFrom() throws {
        let engine = try dealt(7)
        for observer in ["b", "c"] {
            let view = engine.state.view(for: observer)
            XCTAssertEqual(view.wellChoiceCount, 0, "\(observer) shouldn't be shown a's pick")
            for opponent in view.opponents {
                XCTAssertEqual(opponent.wellCount, 0, "No wells exist yet")
            }
        }
    }

    /// The banked cards never appear in any view, including their owner's.
    func testABankedCardIsInvisibleToEveryone() throws {
        let engine = try dealt(7)
        let dealtToA = try XCTUnwrap(engine.state.player(id: "a")).hand
        let buried = Set([dealtToA[2].id, dealtToA[5].id])
        try engine.chooseWell(slots: [2, 5], by: "a")

        for observer in ["a", "b", "c"] {
            let view = engine.state.view(for: observer)
            let visible = Set(view.yourHand.map(\.id) + view.yourPoisonPile.map(\.id))
            XCTAssertTrue(
                visible.isDisjoint(with: buried),
                "\(observer) can see a buried card"
            )
        }
    }

    /// The action that crosses the wire carries positions, not identities. If it
    /// carried card IDs, every opponent could read two of your well straight out
    /// of the match log.
    func testTheActionLogCarriesNoCardIdentities() throws {
        let engine = try dealt(7)
        let dealtToA = try XCTUnwrap(engine.state.player(id: "a")).hand
        let action = PlayerAction.chooseWell(slots: [2, 5])

        let json = String(decoding: try JSONEncoder().encode(action), as: UTF8.self)
        for card in dealtToA {
            XCTAssertFalse(
                json.contains("\(card.id)") && card.id > 10,
                "The encoded action mentions card \(card.id) — well cards must not travel"
            )
        }
        // And it still replays.
        try engine.apply(SubmittedAction(playerID: "a", action: action, sequence: 0))
        XCTAssertEqual(try XCTUnwrap(engine.state.player(id: "a")).well.count, 2)
    }
}
