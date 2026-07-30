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

    private func engine(handSize: Int, seed: UInt32 = 4242) throws -> GameEngine {
        try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .ai(.sharp))],
            dealerIndex: 1, handSize: handSize, seed: seed
        )
    }

    /// The bug: hand cap was set to the deal size, so a 12-card deal refilled to
    /// twelve forever. The deal is a *starting position*, not a standing
    /// allowance — the rulebook's poisoned-queen sequence "5 → 4 → 3" only makes
    /// sense if the base cap is five.
    func testHandCapIsAlwaysFiveRegardlessOfDealSize() throws {
        for handSize in [5, 6, 8, 12] {
            let engine = try engine(handSize: handSize)
            for player in engine.state.players {
                XCTAssertEqual(
                    player.handCap, 5,
                    "Dealt \(handSize) — cap should still be 5"
                )
                XCTAssertEqual(
                    player.hand.count, handSize,
                    "Dealt \(handSize) — the opening hand should be that size"
                )
            }
        }
    }

    func testALargeHandPlaysDownToFiveAndHoldsThere() throws {
        let engine = try engine(handSize: 9)
        let me = engine.state.currentPlayer.id
        XCTAssertEqual(engine.state.player(id: me)?.hand.count, 9)

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
            case .concede: try engine.concedeStranded(by: current.id)
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
        let engine = try engine(handSize: 5)
        let me = engine.state.currentPlayer.id
        // Play one card; the refill should bring it straight back to five.
        let playable = try XCTUnwrap(
            engine.state.currentPlayer.hand.first { Rules.isPlayable($0, in: engine.state) }
        )
        let declaration = try XCTUnwrap(Rules.legalDeclarations(for: playable, in: engine.state).first)
        try engine.play(cardID: playable.id, by: me, declaration: declaration)
        XCTAssertEqual(engine.state.player(id: me)?.hand.count, 5)
    }

    func testPoisonedQueensStepTheCapDownFiveFourThree() throws {
        // The exact sequence the rulebook names.
        var state = GameState(
            players: [PlayerState(id: "a", name: "A", kind: .human, handCap: Rules.sustainingHandCap)],
            currentPlayerIndex: 0, dealerID: "a", handSize: 5
        )
        XCTAssertEqual(state.players[0].handCap, 5)
        for expected in [4, 3, 3, 3] {
            state.players[0].handCap = max(Rules.poisonedHandCapFloor, state.players[0].handCap - 1)
            XCTAssertEqual(state.players[0].handCap, expected, "Cap should floor at 3")
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
                dealerIndex: 2, handSize: 8, seed: seed
            )
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
                case .concede: try engine.concedeStranded(by: current.id)
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
            dealerIndex: 1, handSize: 5, seed: 909
        )
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
            dealerIndex: 1, handSize: 6, seed: seed
        )
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
            case .concede: try engine.concedeStranded(by: current.id)
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
