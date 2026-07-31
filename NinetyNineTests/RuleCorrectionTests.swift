//
//  RuleCorrectionTests.swift
//  Regression cover for rules that were wrong in the first release.
//
//  Each of these is a reported defect or clarification, pinned so it can't come
//  back. The comments record what the behaviour used to be, because that is the
//  part that gets lost.
//

import XCTest
@testable import NinetyNine

final class HandCapTests: XCTestCase {

    private func engine(cardsDealt: Int, seed: UInt32 = 4242) throws -> GameEngine {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 1, cardsDealt: cardsDealt, seed: seed
        )
        engine._finishWellSelectionForTesting()
        return engine
    }

    /// The bug: hand cap was set to the deal size, so a 12-card deal refilled to
    /// twelve forever. The deal is a *starting position*, not a standing
    /// allowance — the rulebook's poisoned-queen sequence "5 → 4 → 3" only makes
    /// sense if the base cap is five.
    func testHandCapIsAlwaysFiveRegardlessOfDealSize() throws {
        var checked = 0
        for cardsDealt in [5, 6, 8, 12] {
            let engine = try engine(cardsDealt: cardsDealt)
            // The opening top-up draws from the deck, so it can turn up a queen
            // and poison everyone before a card is played. That is the rule
            // working, but it moves the caps — so those deals aren't what this
            // test is measuring.
            guard !engine.state.queensArePoisonous else { continue }
            checked += 1

            let leader = engine.state.currentPlayer.id
            for player in engine.state.players {
                XCTAssertEqual(
                    player.handCap, 5,
                    "Dealt \(cardsDealt) — cap should still be 5"
                )
                // Two of the deal went to the well. Whoever leads has already
                // been topped up to the cap; nobody else has yet.
                let expected = player.id == leader
                    ? max(cardsDealt - Rules.wellSize, Rules.sustainingHandCap)
                    : cardsDealt - Rules.wellSize
                XCTAssertEqual(
                    player.hand.count, expected,
                    "Dealt \(cardsDealt) — opening hand should be \(expected)"
                )
            }
        }
        XCTAssertGreaterThan(checked, 0, "Every deal poisoned queens — the test measured nothing")
    }

    func testALargeHandPlaysDownToFiveAndHoldsThere() throws {
        let engine = try engine(cardsDealt: 9)
        let me = engine.state.currentPlayer.id
        XCTAssertEqual(engine.state.player(id: me)?.hand.count, 7, "Nine dealt, two banked")

        // Play until the hand reaches the cap, then confirm it stops falling.
        var counts: [Int] = []
        var guardCount = 0
        while !engine.state.isOver && guardCount < 60 {
            guardCount += 1
            let current = engine.state.currentPlayer
            let ai = AIPlayer(difficulty: .sharp)
            guard let move = ai.nextMove(for: current.id, engine: engine) else { break }
            switch move.kind {
            case .play(let cardID, let declaration):
                if engine.state.pendingWell?.card.id == cardID {
                    try engine.resolveWell(by: current.id, declaration: declaration)
                } else {
                    try engine.play(cardID: cardID, by: current.id, declaration: declaration)
                }
            case .useWell: try engine.drawFromWell(by: current.id, slot: 0)
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
            if let hand = engine.state.player(id: me)?.hand.count { counts.append(hand) }
        }

        // A hand dealt above the cap must shrink toward it, never be topped back
        // up to the deal size.
        XCTAssertTrue(counts.contains { $0 <= 9 }, "The hand should have been played down")
        XCTAssertFalse(
            counts.contains { $0 > 9 + 2 },
            "Nothing should push a hand far above its deal size except well bonuses"
        )
    }

    func testRefillTopsUpToFiveButNeverRemovesCards() throws {
        let engine = try engine(cardsDealt: 7)
        let me = engine.state.currentPlayer.id
        // Play one card; the refill should bring it straight back to five.
        let playable = try XCTUnwrap(
            engine.state.currentPlayer.hand.first { Rules.isPlayable($0, in: engine.state) }
        )
        let declaration = try XCTUnwrap(Rules.legalDeclarations(for: playable, in: engine.state).first)
        try engine.play(cardID: playable.id, by: me, declaration: declaration)
        XCTAssertEqual(engine.state.player(id: me)?.hand.count, 5)
    }

    /// Each poisoned queen costs a card of capacity, all the way down: three
    /// queens down means a hand of two. The floor exists only so a player can
    /// never be left unable to hold a card at all.
    func testEachPoisonedQueenCostsACardOfCapacity() throws {
        var state = GameState(
            players: [PlayerState(id: "a", name: "A", kind: .human, handCap: Rules.sustainingHandCap)],
            currentPlayerIndex: 0, dealerID: "a", cardsDealt: 5
        )
        XCTAssertEqual(state.players[0].handCap, 5)
        for expected in [4, 3, 2, 1, 1] {
            state.players[0].handCap = max(Rules.poisonedHandCapFloor, state.players[0].handCap - 1)
            XCTAssertEqual(state.players[0].handCap, expected)
        }
    }
}

final class PoisonedQueenTests: XCTestCase {

    /// The bug: when queens turned poisonous, held queens were exiled from every
    /// hand *except* the triggering player's — so the one person who caused it
    /// was the one person it didn't touch.
    func testEveryHeldQueenIsExiledIncludingTheTriggeringPlayers() throws {
        // Search seeds for a deal where the player who first draws a queen is
        // also holding one, which is the case the bug hid in.
        var checked = 0
        for seed in UInt32(1)...400 {
            let engine = try GameEngine(
                seats: [("a", "A", .ai(.casual)), ("b", "B", .ai(.casual)), ("c", "C", .ai(.casual))],
                dealerIndex: 2, cardsDealt: 8, seed: seed
            )
            engine._finishWellSelectionForTesting()
            var guardCount = 0
            while !engine.state.isOver && !engine.state.queensArePoisonous && guardCount < 200 {
                guardCount += 1
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
                case .useWell: try engine.drawFromWell(by: current.id, slot: 0)
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
            guard engine.state.queensArePoisonous else { continue }
            checked += 1

            // Once poisonous, no living player may still be holding a queen.
            for player in engine.state.players where !player.isEliminated {
                XCTAssertFalse(
                    player.hand.contains { $0.rank == .queen },
                    "Seed \(seed): \(player.id) still holds a queen after poisoning"
                )
            }
            if checked >= 8 { break }
        }
        XCTAssertGreaterThan(checked, 0, "No seed reached the poisonous state")
    }

    /// An exiled queen has to be *kept*, not discarded — three of them are a
    /// Snackoo.
    func testExiledQueensAccumulateAndEnableASnackoo() throws {
        var player = PlayerState(id: "a", name: "A", kind: .human, handCap: 5)
        XCTAssertFalse(Rules.canSnackooPoison(player))
        player.poisonPile = [
            Card(id: 1, rank: .queen, suit: .spades),
            Card(id: 2, rank: .queen, suit: .hearts),
        ]
        XCTAssertFalse(Rules.canSnackooPoison(player), "Two isn't enough")
        player.poisonPile.append(Card(id: 3, rank: .queen, suit: .clubs))
        XCTAssertTrue(Rules.canSnackooPoison(player), "Three exiled queens is a Snackoo")
    }

    func testPoisonSnackooClearsThreeAndDrawsThree() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 1, cardsDealt: 5, seed: 909
        )
        engine._finishWellSelectionForTesting()
        // Force three exiled queens onto the player.
        let seat = try XCTUnwrap(engine.state.index(of: "a"))
        let before = engine.state.players[seat].hand.count
        var seeded = engine.state
        seeded.players[seat].poisonPile = [
            Card(id: 400, rank: .queen, suit: .spades),
            Card(id: 401, rank: .queen, suit: .hearts),
            Card(id: 402, rank: .queen, suit: .clubs),
        ]
        engine._replaceStateForTesting(seeded)

        try engine.declareSnackoo(by: "a", kind: .threeQueens)

        XCTAssertTrue(engine.state.players[seat].poisonPile.isEmpty, "The pile should clear")
        XCTAssertEqual(
            engine.state.players[seat].hand.count, before + 3,
            "Snackoo draws three replacements"
        )
    }
}

final class WellChoiceTests: XCTestCase {

    private func stuckEngine(seed: UInt32) throws -> GameEngine? {
        // Find a position where a player is genuinely stuck, so the well is legal.
        let engine = try GameEngine(
            seats: [("a", "A", .ai(.casual)), ("b", "B", .ai(.casual))],
            dealerIndex: 1, cardsDealt: 6, seed: seed
        )
        engine._finishWellSelectionForTesting()
        var guardCount = 0
        while !engine.state.isOver && guardCount < 300 {
            guardCount += 1
            let current = engine.state.currentPlayer
            if !Rules.hasLegalPlay(playerID: current.id, in: engine.state),
               !current.well.isEmpty,
               engine.state.pendingWell == nil {
                return engine
            }
            let ai = AIPlayer(difficulty: .casual)
            guard let move = ai.nextMove(for: current.id, engine: engine) else { break }
            switch move.kind {
            case .play(let cardID, let declaration):
                if engine.state.pendingWell?.card.id == cardID {
                    try engine.resolveWell(by: current.id, declaration: declaration)
                } else {
                    try engine.play(cardID: cardID, by: current.id, declaration: declaration)
                }
            case .useWell: try engine.drawFromWell(by: current.id, slot: 0)
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
        return nil
    }

    /// The change: the engine used to pick a well card at random. The player
    /// picks now — still blind, since both are face down, but it's their call.
    func testTheChosenSlotIsTheCardRevealed() throws {
        for seed in UInt32(1)...200 {
            guard let engine = try stuckEngine(seed: seed) else { continue }
            let player = engine.state.currentPlayer
            guard player.well.count == 2 else { continue }

            let expected = player.well[1]
            let events = try engine.drawFromWell(by: player.id, slot: 1)

            guard case .wellRevealed(let revealed, _, let playable) = events.first else {
                XCTFail("Expected a reveal event")
                return
            }
            XCTAssertEqual(
                revealed.id, expected.id,
                "Slot 1 should reveal the second well card, not a random one"
            )
            // The unchosen card stays for later — but only if its owner survived.
            // An unplayable well card eliminates them, and elimination returns
            // every card they held, well included, to the draw pile.
            let after = try XCTUnwrap(engine.state.player(id: player.id))
            if playable {
                XCTAssertEqual(after.well.count, 1, "The card they didn't pick should remain")
                XCTAssertNotEqual(after.well[0].id, revealed.id)
            } else if engine.state.pendingWell?.snackooRank != nil {
                // The third outcome: unplayable, but the third of its rank, so
                // the Snackoo is offered before they're told they're out. They
                // are still very much in the game.
                XCTAssertFalse(after.isEliminated, "The rescue must be offered before elimination")
            } else {
                XCTAssertTrue(after.isEliminated)
                XCTAssertTrue(after.well.isEmpty, "An eliminated player's well returns to the deck")
            }
            return
        }
        throw XCTSkip("No seed in 1...200 produced a stuck player with a full well")
    }

    func testAnOutOfRangeSlotIsClampedRatherThanRejected() throws {
        // A spent well leaves one card; asking for slot 1 should still work.
        for seed in UInt32(1)...200 {
            guard let engine = try stuckEngine(seed: seed) else { continue }
            let player = engine.state.currentPlayer
            guard player.well.count == 2 else { continue }
            XCTAssertNoThrow(try engine.drawFromWell(by: player.id, slot: 99))
            return
        }
        throw XCTSkip("No suitable seed")
    }

    func testWellActionsAreOfferedPerSlot() throws {
        for seed in UInt32(1)...200 {
            guard let engine = try stuckEngine(seed: seed) else { continue }
            let player = engine.state.currentPlayer
            guard player.well.count == 2 else { continue }

            let actions = engine.availableActions(for: player.id)
            let wellActions = actions.filter {
                if case .drawFromWell = $0 { return true }
                return false
            }
            XCTAssertEqual(wellActions.count, 2, "Both well cards should be offered")
            XCTAssertTrue(wellActions.contains(.drawFromWell(slot: 0)))
            XCTAssertTrue(wellActions.contains(.drawFromWell(slot: 1)))
            return
        }
        throw XCTSkip("No suitable seed")
    }

    /// Surviving the well pays two bonus cards, and if those complete a
    /// three-of-a-kind the player may Snackoo for three more on top.
    func testSurvivingTheWellPaysTwoAndCanStillFeedASnackoo() throws {
        for seed in UInt32(1)...300 {
            guard let engine = try stuckEngine(seed: seed) else { continue }
            let player = engine.state.currentPlayer
            let handBefore = player.hand.count

            let events = try engine.drawFromWell(by: player.id, slot: 0)
            guard case .wellRevealed(let card, _, true) = events.first else { continue }

            let declarations = Rules.legalDeclarations(for: card, in: engine.state)
            guard let declaration = declarations.first else { continue }
            try engine.resolveWell(by: player.id, declaration: declaration)

            let after = try XCTUnwrap(engine.state.player(id: player.id))
            XCTAssertGreaterThanOrEqual(
                after.hand.count, handBefore + 2,
                "A survived well should pay two bonus cards on top of the refill"
            )
            // Bonus cards are allowed to push a hand above the sustaining cap —
            // that reward would be meaningless otherwise.
            XCTAssertGreaterThan(after.hand.count, Rules.sustainingHandCap - 1)

            // And if the new cards happen to complete a trio, Snackoo is offered.
            let trios = Rules.snackooRanksInHand(for: after)
            if let rank = trios.first {
                let sizeBefore = after.hand.count
                try engine.declareSnackoo(by: player.id, kind: .threeOfAKind(rank))
                let final = try XCTUnwrap(engine.state.player(id: player.id))
                XCTAssertEqual(
                    final.hand.count, sizeBefore,
                    "Snackoo discards three and draws three"
                )
            }
            return
        }
        throw XCTSkip("No seed produced a survivable well draw")
    }
}

// MARK: - The well rescue

final class WellSnackooRescueTests: XCTestCase {

    /// Reported from real play: two 6s in hand, the last well card a third 6.
    /// The card is unplayable, but three of a kind is a Snackoo — the player
    /// should be offered it *before* being told they've lost. The first release
    /// eliminated them on the spot.
    private func stuckWithTrio() throws -> (GameEngine, String, Rank) {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 1, cardsDealt: 5, seed: 31337
        )
        engine._finishWellSelectionForTesting()
        var seeded = engine.state
        let seat = try XCTUnwrap(seeded.players.firstIndex { $0.id == "a" })

        // Two sixes in hand, a third in the well, and a tally that makes the
        // six unplayable.
        seeded.tally = 99
        seeded.players[seat].hand = [
            Card(id: 800, rank: .six, suit: .spades),
            Card(id: 801, rank: .six, suit: .hearts),
            Card(id: 802, rank: .king, suit: .clubs),
        ]
        seeded.players[seat].well = [Card(id: 803, rank: .six, suit: .diamonds)]
        seeded.currentPlayerIndex = seat
        engine._replaceStateForTesting(seeded)
        return (engine, "a", .six)
    }

    func testAnUnplayableWellCardThatCompletesATrioDoesNotEliminate() throws {
        let (engine, player, _) = try stuckWithTrio()

        let events = try engine.drawFromWell(by: player, slot: 0)

        XCTAssertFalse(
            events.contains { if case .playerEliminated = $0 { return true }; return false },
            "Being offered a Snackoo must come before being eliminated"
        )
        let pending = try XCTUnwrap(engine.state.pendingWell)
        XCTAssertFalse(pending.isPlayable)
        XCTAssertEqual(pending.snackooRank, .six, "The rescue rank should be offered")
        XCTAssertFalse(try XCTUnwrap(engine.state.player(id: player)).isEliminated)
    }

    func testTakingTheRescueDiscardsThreeAndDrawsThree() throws {
        let (engine, player, _) = try stuckWithTrio()
        try engine.drawFromWell(by: player, slot: 0)

        let before = try XCTUnwrap(engine.state.player(id: player)).hand.count
        try engine.snackooWellCard(by: player)

        let after = try XCTUnwrap(engine.state.player(id: player))
        XCTAssertFalse(after.isEliminated, "The rescue should keep them in the game")
        // Assert on identity, not on rank: a fourth six may legitimately arrive
        // as one of the three replacements.
        XCTAssertFalse(after.hand.contains { $0.id == 800 }, "The first six leaves the hand")
        XCTAssertFalse(after.hand.contains { $0.id == 801 }, "The second six leaves the hand")
        // Two out of hand, three in.
        XCTAssertEqual(after.hand.count, before - 2 + 3)
        XCTAssertNil(engine.state.pendingWell)
        // All three sixes end up on the discard pile, the well card included.
        for id in [800, 801, 803] {
            XCTAssertTrue(
                engine.state.discardPile.contains { $0.id == id },
                "All three sixes should be on the discard pile, the well card included"
            )
        }
    }

    func testTheRescueIsFreeAndDoesNotCountAsTheTurnsPlay() throws {
        let (engine, player, _) = try stuckWithTrio()
        try engine.drawFromWell(by: player, slot: 0)
        let owedBefore = engine.state.playsRemainingThisTurn

        try engine.snackooWellCard(by: player)

        XCTAssertEqual(engine.state.currentPlayer.id, player, "Still their turn")
        XCTAssertEqual(
            engine.state.playsRemainingThisTurn, owedBefore,
            "Snackoo is a free action — it buys a fresh hand, not a free pass"
        )
    }

    func testDecliningTheRescueStillEliminates() throws {
        let (engine, player, _) = try stuckWithTrio()
        try engine.drawFromWell(by: player, slot: 0)

        let events = try engine.concedeWellCard(by: player)

        XCTAssertTrue(events.contains { if case .playerEliminated = $0 { return true }; return false })
        XCTAssertTrue(try XCTUnwrap(engine.state.player(id: player)).isEliminated)
    }

    func testAnUnplayableWellCardWithNoTrioStillEliminatesImmediately() throws {
        // The rescue must not accidentally spare everyone.
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 1, cardsDealt: 5, seed: 31337
        )
        engine._finishWellSelectionForTesting()
        var seeded = engine.state
        let seat = try XCTUnwrap(seeded.players.firstIndex { $0.id == "a" })
        seeded.tally = 99
        seeded.players[seat].hand = [Card(id: 810, rank: .king, suit: .clubs)]
        seeded.players[seat].well = [Card(id: 811, rank: .six, suit: .diamonds)]
        seeded.currentPlayerIndex = seat
        engine._replaceStateForTesting(seeded)

        let events = try engine.drawFromWell(by: "a", slot: 0)
        XCTAssertTrue(events.contains { if case .playerEliminated = $0 { return true }; return false })
        XCTAssertTrue(try XCTUnwrap(engine.state.player(id: "a")).isEliminated)
    }

    func testBothOptionsAreOfferedToTheUI() throws {
        let (engine, player, _) = try stuckWithTrio()
        try engine.drawFromWell(by: player, slot: 0)

        let actions = engine.availableActions(for: player)
        XCTAssertTrue(actions.contains(.snackooWellCard), "The way out must be offered")
        XCTAssertTrue(actions.contains(.concedeWellCard), "So must accepting the loss")
    }

    /// Queens keep their own route out (the poison pile), so a queen well card
    /// is not a hand-trio rescue — consistent with hand Snackoo.
    func testAQueenWellCardIsNotAHandTrioRescue() throws {
        var player = PlayerState(id: "a", name: "A", kind: .human, handCap: 5)
        player.hand = [
            Card(id: 820, rank: .queen, suit: .spades),
            Card(id: 821, rank: .queen, suit: .hearts),
        ]
        XCTAssertNil(
            Rules.rankCompletedInHand(by: Card(id: 822, rank: .queen, suit: .clubs), for: player)
        )
        // But an ordinary rank is.
        player.hand = [
            Card(id: 823, rank: .four, suit: .spades),
            Card(id: 824, rank: .four, suit: .hearts),
        ]
        XCTAssertEqual(
            Rules.rankCompletedInHand(by: Card(id: 825, rank: .four, suit: .clubs), for: player),
            .four
        )
    }
}

// MARK: - Playing a set

final class CardSetTests: XCTestCase {

    private func board(tally: Int, hand: [Card], players: Int = 3) -> GameState {
        var seats = [PlayerState(id: "a", name: "A", kind: .human, handCap: 5)]
        seats[0].hand = hand
        for index in 1..<players {
            seats.append(PlayerState(id: "p\(index)", name: "P\(index)", kind: .ai(.sharp), handCap: 5))
        }
        var state = GameState(players: seats, currentPlayerIndex: 0, dealerID: "a", cardsDealt: 5)
        state.tally = tally
        return state
    }

    private func cards(_ rank: Rank, _ suits: [Suit]) -> [Card] {
        suits.enumerated().map { Card(id: 700 + $0.offset, rank: rank, suit: $0.element) }
    }

    func testASetSumsItsValues() {
        let set = cards(.five, [.spades, .hearts, .clubs])
        let state = board(tally: 10, hand: set)
        switch Rules.resolveSet(cards: set, declaration: .plain, in: state) {
        case .success(let effect):
            XCTAssertEqual(effect.newTally, 25, "Three fives is fifteen")
            XCTAssertEqual(effect.tallyDelta, 15)
        case .failure(let reason): XCTFail(reason.explanation)
        }
    }

    /// Confirmed by the author: the set is illegal if the running total busts,
    /// exactly as if the cards were played one at a time.
    func testASetIsIllegalIfTheRunningTotalBusts() {
        let set = cards(.five, [.spades, .hearts, .clubs])
        let state = board(tally: 90, hand: set)
        // 90 → 95 → 100. The third card is what kills it.
        switch Rules.resolveSet(cards: set, declaration: .plain, in: state) {
        case .success(let effect): XCTFail("Expected a bust, got \(effect.newTally)")
        case .failure(let reason): XCTAssertEqual(reason, .wouldExceed99(resulting: 100))
        }
        // Two of them from 85 is fine — the rule is about the running total,
        // not about sets being special.
        switch Rules.resolveSet(cards: Array(set.prefix(2)), declaration: .plain, in: board(tally: 85, hand: set)) {
        case .success(let effect): XCTAssertEqual(effect.newTally, 95)
        case .failure(let reason): XCTFail(reason.explanation)
        }
    }

    /// Confirmed by the author: fours compound, so an even number cancels out.
    func testFoursReverseOncePerCardSoTwoCancelOut() {
        let two = cards(.four, [.spades, .hearts])
        let state = board(tally: 20, hand: two)
        switch Rules.resolveSet(cards: two, declaration: .plain, in: state) {
        case .success(let effect):
            XCTAssertFalse(effect.reversesDirection, "Two fours cancel each other out")
            XCTAssertEqual(effect.newTally, 20, "Fours are worth nothing")
        case .failure(let reason): XCTFail(reason.explanation)
        }

        let three = cards(.four, [.spades, .hearts, .clubs])
        switch Rules.resolveSet(cards: three, declaration: .plain, in: board(tally: 20, hand: three)) {
        case .success(let effect):
            XCTAssertTrue(effect.reversesDirection, "Three fours flip it once")
        case .failure(let reason): XCTFail(reason.explanation)
        }
    }

    func testASetOfEightsLocksOnceToTheChosenSuit() {
        let set = cards(.eight, [.spades, .hearts])
        let state = board(tally: 10, hand: set)
        switch Rules.resolveSet(cards: set, declaration: .lock(.diamonds), in: state) {
        case .success(let effect):
            XCTAssertEqual(effect.newTally, 26, "Both eights count")
            XCTAssertEqual(effect.locksSuit, .diamonds, "The lock is a state, not a toggle")
        case .failure(let reason): XCTFail(reason.explanation)
        }
    }

    func testASetOfAcesTakesOneValueForAllOfThem() {
        let set = cards(.ace, [.spades, .hearts, .clubs])
        let state = board(tally: 0, hand: set)
        switch Rules.resolveSet(cards: set, declaration: .ace(.eleven), in: state) {
        case .success(let effect): XCTAssertEqual(effect.newTally, 33)
        case .failure(let reason): XCTFail(reason.explanation)
        }
        switch Rules.resolveSet(cards: set, declaration: .ace(.one), in: state) {
        case .success(let effect): XCTAssertEqual(effect.newTally, 3)
        case .failure(let reason): XCTFail(reason.explanation)
        }
    }

    func testQueensCannotBePlayedAsASet() {
        let set = cards(.queen, [.spades, .hearts])
        let state = board(tally: 10, hand: set)
        switch Rules.resolveSet(cards: set, declaration: .queen(as: .king), in: state) {
        case .success: XCTFail("Queens should be excluded from set play")
        case .failure: break
        }
    }

    func testOnlyRanksWithALegalSetAreOffered() {
        let hand = cards(.five, [.spades, .hearts]) + [Card(id: 750, rank: .king, suit: .clubs)]
        let state = board(tally: 10, hand: hand)
        let player = try! XCTUnwrap(state.player(id: "a"))
        XCTAssertEqual(Rules.playableSetRanks(for: player, in: state), [.five])

        // At 95 the pair would bust, so it isn't offered at all.
        let tight = board(tally: 95, hand: hand)
        let tightPlayer = try! XCTUnwrap(tight.player(id: "a"))
        XCTAssertTrue(Rules.playableSetRanks(for: tightPlayer, in: tight).isEmpty)
    }

    func testPlayingASetCountsAsOnePlayAndDiscardsEveryCard() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 1, cardsDealt: 5, seed: 4242
        )
        engine._finishWellSelectionForTesting()
        var seeded = engine.state
        let seat = try XCTUnwrap(seeded.players.firstIndex { $0.id == "a" })
        let set = cards(.three, [.spades, .hearts, .clubs])
        seeded.tally = 10
        seeded.players[seat].hand = set
        seeded.currentPlayerIndex = seat
        engine._replaceStateForTesting(seeded)

        try engine.playSet(cardIDs: set.map(\.id), by: "a", declaration: .plain)

        XCTAssertEqual(engine.state.tally, 19, "Three threes")
        for card in set {
            XCTAssertTrue(engine.state.discardPile.contains { $0.id == card.id }, "Every card lands on the pile")
        }
        XCTAssertNotEqual(engine.state.currentPlayer.id, "a", "One play, so the turn passes")
    }
}

// MARK: - Moving a suit lock

/// The lock is set by an 8, and the author's ruling is that it can only be
/// *moved* by an 8 played directly on another 8. Anything else landing in
/// between makes the lock binding again.
final class MovingTheLockTests: XCTestCase {

    private func board(lock: Suit, topIsEight: Bool, tally: Int = 20) -> GameState {
        var state = GameState(
            players: [
                PlayerState(id: "a", name: "A", kind: .human, handCap: 5),
                PlayerState(id: "b", name: "B", kind: .human, handCap: 5),
            ],
            currentPlayerIndex: 0, dealerID: "b", cardsDealt: 7
        )
        state.tally = tally
        state.suitLock = SuitLock(suit: lock, setByPlayerID: "b")
        state.topPlayedAsEight = topIsEight
        return state
    }

    private func card(_ rank: Rank, _ suit: Suit) -> Card { Card(id: 1, rank: rank, suit: suit) }

    func testAnEightOfAnySuitMayTakeOverALockWhenPlayedOnAnEight() {
        let state = board(lock: .hearts, topIsEight: true)
        switch Rules.resolve(card: card(.eight, .diamonds), declaration: .lock(.clubs), in: state) {
        case .success(let effect):
            XCTAssertEqual(effect.locksSuit, .clubs, "The off-suit 8 moves the lock")
            XCTAssertEqual(effect.newTally, 28)
        case .failure(let reason):
            XCTFail("An 8 on an 8 should be legal: \(reason.explanation)")
        }
    }

    /// The narrowing the author asked for: once something else is on top, an
    /// off-suit 8 is as dead as any other off-suit card.
    func testAnOffSuitEightIsBlockedWhenTheTopCardIsNotAnEight() {
        let state = board(lock: .hearts, topIsEight: false)
        switch Rules.resolve(card: card(.eight, .diamonds), declaration: .lock(.clubs), in: state) {
        case .success:
            XCTFail("An off-suit 8 should not move a lock it wasn't played onto")
        case .failure(let reason):
            XCTAssertEqual(reason, .suitLocked(.hearts))
        }
    }

    /// An 8 that *does* follow the lock is legal either way — it's an on-suit
    /// card like any other.
    func testAnOnSuitEightIsAlwaysLegal() {
        for topIsEight in [true, false] {
            let state = board(lock: .hearts, topIsEight: topIsEight)
            switch Rules.resolve(card: card(.eight, .hearts), declaration: .lock(.spades), in: state) {
            case .success(let effect): XCTAssertEqual(effect.locksSuit, .spades)
            case .failure(let reason): XCTFail("top-is-eight=\(topIsEight): \(reason.explanation)")
            }
        }
    }

    /// The author's other route: a Queen is never blocked, so she can be played
    /// under any lock, declared an 8, and used to move it.
    func testAQueenCanBeDeclaredAnEightToSeizeALock() {
        let state = board(lock: .hearts, topIsEight: false)
        switch Rules.resolve(
            card: card(.queen, .spades),
            declaration: .queen(as: .eight, lockSuit: .diamonds),
            in: state
        ) {
        case .success(let effect):
            XCTAssertEqual(effect.locksSuit, .diamonds)
            XCTAssertEqual(effect.effectiveRank, .eight)
        case .failure(let reason):
            XCTFail("A Queen is never blocked by a lock: \(reason.explanation)")
        }
    }

    /// And having done so she leaves an 8 face up, so the next player gets the
    /// same opportunity she just took.
    func testAQueenPlayedAsAnEightLeavesAnEightFaceUp() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human)],
            dealerIndex: 1, cardsDealt: 7, seed: 909
        )
        engine._finishWellSelectionForTesting()

        var seeded = engine.state
        let seat = try XCTUnwrap(seeded.players.firstIndex { $0.id == seeded.currentPlayer.id })
        let queen = Card(id: 800, rank: .queen, suit: .spades)
        seeded.players[seat].hand = [queen]
        seeded.tally = 10
        seeded.suitLock = SuitLock(suit: .hearts, setByPlayerID: "b")
        seeded.topPlayedAsEight = false
        engine._replaceStateForTesting(seeded)

        try engine.play(
            cardID: queen.id,
            by: engine.state.currentPlayer.id,
            declaration: .queen(as: .eight, lockSuit: .diamonds)
        )

        XCTAssertEqual(engine.state.suitLock?.suit, .diamonds)
        XCTAssertTrue(
            engine.state.topPlayedAsEight,
            "She's an 8 now, so the next player may play an 8 of any suit on her"
        )
    }

    /// A plain card resets it, which is the whole point of the narrowing.
    func testAnyOtherCardClosesTheDoor() throws {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human)],
            dealerIndex: 1, cardsDealt: 7, seed: 909
        )
        engine._finishWellSelectionForTesting()

        var seeded = engine.state
        let seat = try XCTUnwrap(seeded.players.firstIndex { $0.id == seeded.currentPlayer.id })
        let three = Card(id: 801, rank: .three, suit: .hearts)
        seeded.players[seat].hand = [three]
        seeded.tally = 10
        seeded.suitLock = SuitLock(suit: .hearts, setByPlayerID: "b")
        seeded.topPlayedAsEight = true
        engine._replaceStateForTesting(seeded)

        try engine.play(cardID: three.id, by: engine.state.currentPlayer.id, declaration: .plain)
        XCTAssertFalse(engine.state.topPlayedAsEight)
    }
}

// MARK: - A Queen played as an 8 must ask which suit

/// Reported from a real game: an opponent locked the suit, the player answered
/// with a Queen declared as an 8, and was never asked where to point the lock.
///
/// The engine was never the problem — it offers every suit. The sheet resolved
/// the Queen's options by picking whichever produced the lowest tally, and every
/// lock suit produces the *same* tally, so the tie-break silently chose one.
/// These pin the engine half; the sheet now asks as a second step.
final class QueenAsEightDeclarationTests: XCTestCase {

    private func lockedBoard(_ lock: Suit, tally: Int = 20) -> GameState {
        var state = GameState(
            players: [
                PlayerState(id: "a", name: "A", kind: .human, handCap: 5),
                PlayerState(id: "b", name: "B", kind: .human, handCap: 5),
            ],
            currentPlayerIndex: 0, dealerID: "b", cardsDealt: 7
        )
        state.tally = tally
        state.suitLock = SuitLock(suit: lock, setByPlayerID: "b")
        // The lock was just set by an 8, which is the situation described.
        state.topPlayedAsEight = true
        return state
    }

    func testAQueenUnderALockIsOfferedEverySuitAsAnEight() {
        let queen = Card(id: 1, rank: .queen, suit: .spades)
        let declarations = Rules.legalDeclarations(for: queen, in: lockedBoard(.hearts))
        let asEight = declarations.filter { $0.queenAs == .eight }

        for suit in Suit.allCases {
            XCTAssertTrue(
                asEight.contains { $0.lockSuit == suit },
                "A Queen played as an 8 should be able to lock \(suit.displayName)"
            )
        }
        XCTAssertTrue(
            asEight.contains { $0.declinesLock },
            "…and to lock nothing at all"
        )
        XCTAssertEqual(asEight.count, 5, "Four suits plus declining")
    }

    /// Every one of those options is genuinely legal — so a UI that showed them
    /// all can't produce a refused move.
    func testEveryOfferedQueenAsEightOptionIsAccepted() throws {
        let queen = Card(id: 1, rank: .queen, suit: .spades)
        let state = lockedBoard(.hearts)
        let asEight = Rules.legalDeclarations(for: queen, in: state).filter { $0.queenAs == .eight }
        XCTAssertFalse(asEight.isEmpty)

        for declaration in asEight {
            switch Rules.resolve(card: queen, declaration: declaration, in: state) {
            case .success(let effect):
                XCTAssertEqual(effect.effectiveRank, .eight)
                XCTAssertEqual(effect.newTally, 28)
                if declaration.declinesLock {
                    XCTAssertNil(effect.locksSuit)
                    XCTAssertTrue(effect.liftsSuitLock, "Declining should free the table")
                } else {
                    XCTAssertEqual(effect.locksSuit, declaration.lockSuit)
                }
            case .failure(let reason):
                XCTFail("Offered but refused: \(reason.explanation)")
            }
        }
    }

    /// The tie-break that caused it: all five options land on the same tally, so
    /// "pick the lowest" cannot distinguish them and silently took the first.
    func testTheOptionsAreIndistinguishableByTallyWhichIsWhyItHadToAsk() {
        let queen = Card(id: 1, rank: .queen, suit: .spades)
        let state = lockedBoard(.hearts)
        let tallies = Rules.legalDeclarations(for: queen, in: state)
            .filter { $0.queenAs == .eight }
            .compactMap { declaration -> Int? in
                guard case .success(let effect) = Rules.resolve(
                    card: queen, declaration: declaration, in: state
                ) else { return nil }
                return effect.newTally
            }
        XCTAssertEqual(Set(tallies).count, 1, "All the same tally — nothing to sort on")
    }
}
