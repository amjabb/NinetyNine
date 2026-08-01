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

// MARK: - Shuffling the well before you pick

/// Shaking the phone mixes the two face-down well cards, the way people do it at
/// a table. Because the pick is blind, a fake shuffle would be undetectable —
/// which is exactly why it isn't one. It goes through the seeded source and into
/// the action log like everything else that touches the game.
final class WellShuffleTests: XCTestCase {

    private func stuck(seed: UInt32) throws -> GameEngine? {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human)],
            dealerIndex: 1, cardsDealt: 7, seed: seed
        )
        engine._finishWellSelectionForTesting()

        var state = engine.state
        guard let seat = state.index(of: state.currentPlayer.id) else { return nil }
        // A hand with nothing legal, so the well is the only way on.
        state.tally = 99
        state.players[seat].hand = [Card(id: 700, rank: .king, suit: .spades)]
        engine._replaceStateForTesting(state)
        return engine
    }

    func testShufflingReordersTheWellAndIsAnnounced() throws {
        let engine = try XCTUnwrap(try stuck(seed: 31337))
        let id = engine.state.currentPlayer.id
        let seat = try XCTUnwrap(engine.state.index(of: id))
        let before = engine.state.players[seat].well.map(\.id)
        XCTAssertEqual(before.count, 2)

        // A two-card shuffle is a coin flip, so shuffle until it lands the other
        // way — the point is that it *can* change, not that it always does.
        var swapped = false
        var events: [GameEvent] = []
        for _ in 0..<20 {
            events = try engine.shuffleWell(by: id)
            if engine.state.players[seat].well.map(\.id) != before { swapped = true; break }
        }
        XCTAssertTrue(swapped, "Twenty shuffles never changed the order — it isn't shuffling")
        XCTAssertEqual(events, [.wellShuffled(by: id)], "The table should be told")
        XCTAssertEqual(
            Set(engine.state.players[seat].well.map(\.id)), Set(before),
            "A shuffle reorders; it must not change which cards they are"
        )
    }

    /// Once a card is face up it cannot be un-seen, so there is nothing left to
    /// shuffle. Asserted against the pending reveal directly rather than by
    /// drawing — a real draw usually eliminates the player here, and the test
    /// would be measuring that instead.
    func testShufflingIsRefusedOnceACardIsTurnedOver() throws {
        let engine = try XCTUnwrap(try stuck(seed: 31337))
        let id = engine.state.currentPlayer.id
        var state = engine.state
        let seat = try XCTUnwrap(state.index(of: id))
        state.pendingWell = PendingWell(
            playerID: id, card: state.players[seat].well[0], isPlayable: true
        )
        engine._replaceStateForTesting(state)

        XCTAssertThrowsError(try engine.shuffleWell(by: id)) {
            XCTAssertEqual($0 as? GameError, .noPendingWell)
        }
    }

    func testOnlyTheCurrentPlayerMayShuffle() throws {
        let engine = try XCTUnwrap(try stuck(seed: 31337))
        let other = try XCTUnwrap(engine.state.players.first { $0.id != engine.state.currentPlayer.id })
        XCTAssertThrowsError(try engine.shuffleWell(by: other.id)) {
            XCTAssertEqual($0 as? GameError, .notYourTurn)
        }
    }

    /// One card is not a shuffle.
    func testASpentWellCannotBeShuffled() throws {
        let engine = try XCTUnwrap(try stuck(seed: 31337))
        let id = engine.state.currentPlayer.id
        var state = engine.state
        let seat = try XCTUnwrap(state.index(of: id))
        state.players[seat].well = Array(state.players[seat].well.prefix(1))
        engine._replaceStateForTesting(state)

        XCTAssertThrowsError(try engine.shuffleWell(by: id)) {
            XCTAssertEqual($0 as? GameError, .wellEmpty)
        }
    }

    /// It must never be offered during the opening bury — a shake there would
    /// reorder cards the player is in the middle of choosing between.
    func testShufflingIsRefusedWhileWellsAreStillBeingChosen() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human)],
            dealerIndex: 1, cardsDealt: 7, seed: 4242
        )
        XCTAssertTrue(engine.state.isChoosingWells)
        XCTAssertThrowsError(try engine.shuffleWell(by: "a")) {
            XCTAssertEqual($0 as? GameError, .notChoosingWells)
        }
    }

    /// The whole reason it's a real shuffle rather than an animation: every
    /// client has to end up with the same well, or one of them draws a different
    /// card and the match silently forks.
    func testAShuffleReplaysToTheSameWellOnEveryClient() throws {
        let seats: [(String, String, PlayerState.PlayerKind)] = [
            ("a", "A", .human), ("b", "B", .human),
        ]
        let source = try GameEngine(seats: seats, dealerIndex: 1, cardsDealt: 7, seed: 8675309)

        var log: [SubmittedAction] = []
        var sequence = 0
        for id in ["a", "b"] {
            let action = PlayerAction.chooseWell(slots: [0, 1])
            let submitted = SubmittedAction(playerID: id, action: action, sequence: sequence)
            sequence += 1
            try source.apply(submitted)
            log.append(submitted)
        }

        // Shuffle a few times, so a replay that ignored them would diverge.
        let actor = source.state.currentPlayer.id
        for _ in 0..<3 {
            let submitted = SubmittedAction(playerID: actor, action: .shuffleWell, sequence: sequence)
            sequence += 1
            try source.apply(submitted)
            log.append(submitted)
        }

        let replay = try GameEngine(seats: seats, dealerIndex: 1, cardsDealt: 7, seed: 8675309)
        for entry in log { try replay.apply(entry) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(
            try encoder.encode(replay.state), try encoder.encode(source.state),
            "A peer replaying the log ended up with a different well"
        )
    }

    /// And it must survive the wire, since it crosses it.
    func testTheShuffleActionRoundTripsAndCarriesNothingSecret() throws {
        let action = PlayerAction.shuffleWell
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(PlayerAction.self, from: data), action)

        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("card"), "A shuffle names no cards: \(json)")
    }
}

// MARK: - Seeing the card you didn't pick

/// Going out on the well without being shown the other card is the one moment
/// the game owes an answer: everybody asks "what was the one I didn't take?".
/// The card has to survive elimination long enough to be shown, which it very
/// nearly didn't — elimination shuffles a player's whole holding back into the
/// deck as its first act.
final class UnspentWellRevealTests: XCTestCase {

    private func stuckWithTwoWellCards(seed: UInt32) throws -> GameEngine? {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human), ("c", "C", .human)],
            dealerIndex: 2, cardsDealt: 7, seed: seed
        )
        engine._finishWellSelectionForTesting()

        var state = engine.state
        guard let seat = state.index(of: state.currentPlayer.id) else { return nil }
        guard state.players[seat].well.count == 2 else { return nil }
        // Nothing legal in hand, and a ceiling that no well card can clear.
        state.tally = 99
        state.players[seat].hand = [Card(id: 770, rank: .king, suit: .spades)]
        engine._replaceStateForTesting(state)
        return engine
    }

    func testEliminationCarriesTheWellCardTheyDidntPick() throws {
        var checked = 0
        for seed in UInt32(1)...200 {
            guard let engine = try stuckWithTwoWellCards(seed: seed) else { continue }
            let id = engine.state.currentPlayer.id
            let seat = try XCTUnwrap(engine.state.index(of: id))
            let well = engine.state.players[seat].well
            let unchosen = well[1]

            let events = try engine.drawFromWell(by: id, slot: 0)
            // Only interested in the seeds where the draw actually ended them.
            guard let elimination = events.first(where: {
                if case .playerEliminated = $0 { return true }
                return false
            }) else { continue }

            guard case .playerEliminated(let who, _, _, let unspent) = elimination else {
                XCTFail("Unexpected event shape")
                return
            }
            XCTAssertEqual(who, id)
            XCTAssertEqual(
                unspent.map(\.id), [unchosen.id],
                "The card they didn't pick has to come with the elimination"
            )
            // And it's genuinely gone from their well by then — the event is the
            // only place left holding it.
            XCTAssertTrue(engine.state.players[seat].well.isEmpty)
            checked += 1
            break
        }
        XCTAssertGreaterThan(checked, 0, "No seed produced an elimination on the well")
    }

    /// Going out any other way carries nothing, because there was nothing left
    /// buried to show.
    func testAnEliminationWithNoWellLeftCarriesNothing() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human), ("c", "C", .human)],
            dealerIndex: 2, cardsDealt: 7, seed: 4242
        )
        engine._finishWellSelectionForTesting()

        let id = engine.state.currentPlayer.id
        var state = engine.state
        let seat = try XCTUnwrap(state.index(of: id))
        state.players[seat].well = []
        engine._replaceStateForTesting(state)

        let events = try engine.forfeit(by: id)
        guard case .playerEliminated(_, _, _, let unspent)? = events.first(where: {
            if case .playerEliminated = $0 { return true }
            return false
        }) else {
            XCTFail("Expected an elimination")
            return
        }
        XCTAssertTrue(unspent.isEmpty, "Nothing buried, nothing to show")
    }
}

// MARK: - Blind from the deal, not from your turn

/// Reported on a rematch: "it shows you your cards for like half a second
/// before having you pick your well."
///
/// Wells are banked in seat order. On a rematch the dealer changes, so somebody
/// else often banks first — and redaction only applied to whoever was *currently*
/// choosing. Every player waiting their turn could read their own deal. Blind
/// has to mean blind from the moment the cards land.
final class BlindFromTheDealTests: XCTestCase {

    private func dealt(players: Int = 3, dealerIndex: Int = 2) throws -> GameEngine {
        let ids = ["a", "b", "c", "d"].prefix(players)
        return try GameEngine(
            seats: ids.map { ($0, $0.uppercased(), .human) },
            dealerIndex: dealerIndex, cardsDealt: 7, seed: 1234
        )
    }

    func testNobodyCanSeeTheirOwnDealUntilTheyHaveBanked() throws {
        let engine = try dealt()
        let queue = engine.state.wellSelectionQueue
        XCTAssertEqual(queue.count, 3)

        // Including the two who aren't choosing yet — this is the case that
        // leaked.
        for id in queue {
            let view = engine.state.view(for: id)
            XCTAssertTrue(
                view.yourHand.isEmpty,
                "\(id) can read their deal while waiting to bank"
            )
            XCTAssertTrue(view.youOweAWell)
        }
    }

    func testYourHandAppearsAsSoonAsYouHaveBanked() throws {
        let engine = try dealt()
        let first = try XCTUnwrap(engine.state.wellChooserID)
        try engine.chooseWell(slots: [0, 1], by: first)

        let mine = engine.state.view(for: first)
        XCTAssertEqual(mine.yourHand.count, 5, "Banked, so the rest is yours to see")
        XCTAssertFalse(mine.youOweAWell)

        // And everybody still waiting is still blind.
        for id in engine.state.wellSelectionQueue {
            XCTAssertTrue(engine.state.view(for: id).yourHand.isEmpty)
            XCTAssertTrue(engine.state.view(for: id).youOweAWell)
        }
    }

    /// The specific shape of the report: a dealer change puts somebody else
    /// first, and the player who is *not* first must still see nothing.
    func testAWaitingPlayerSeesNothingWhenSomebodyElseBanksFirst() throws {
        let engine = try dealt(dealerIndex: 0)
        let chooser = try XCTUnwrap(engine.state.wellChooserID)
        let waiting = try XCTUnwrap(engine.state.wellSelectionQueue.last)
        XCTAssertNotEqual(chooser, waiting)

        let theirs = engine.state.view(for: waiting)
        XCTAssertTrue(theirs.yourHand.isEmpty, "This is the leak that was reported")
        XCTAssertEqual(theirs.wellChoiceCount, 0, "It isn't their turn to choose yet")
        XCTAssertTrue(theirs.youOweAWell)
    }

    func testOnceEveryoneHasBankedNobodyOwesOne() throws {
        let engine = try dealt()
        engine._finishWellSelectionForTesting()
        for player in engine.state.players {
            XCTAssertFalse(engine.state.view(for: player.id).youOweAWell)
        }
    }
}
