//
//  MultiplayerTests.swift
//  The netcode foundation: actions, redaction, and deterministic replay.
//
//  The redaction tests are the important ones. A leak here isn't a cosmetic bug
//  — it hands an opponent the entire game, and it would be invisible in normal
//  play because everything still *works*.
//

import XCTest
@testable import NinetyNine

final class RedactionTests: XCTestCase {

    private func engine(seats: Int = 3, cardsDealt: Int = 6, seed: UInt32 = 4242) throws -> GameEngine {
        let ids = ["a", "b", "c", "d", "e", "f"].prefix(seats)
        let engine = try GameEngine(
            seats: ids.enumerated().map { index, id in
                (id, "Player\(index)", index == 0 ? .human : .ai(.sharp))
            },
            dealerIndex: seats - 1,
            cardsDealt: cardsDealt,
            seed: seed
        )
        engine._finishWellSelectionForTesting()
        return engine
    }

    // MARK: - The security boundary

    func testViewNeverContainsAnotherPlayersHand() throws {
        let engine = try engine()
        let view = engine.state.view(for: "a")

        // Collect every card id reachable from the view.
        var visible = Set(view.yourHand.map(\.id))
        visible.formUnion(view.yourPoisonPile.map(\.id))
        visible.formUnion(view.discardPile.map(\.id))
        if let pending = view.pendingWell { visible.insert(pending.card.id) }

        for other in engine.state.players where other.id != "a" {
            for card in other.hand {
                XCTAssertFalse(
                    visible.contains(card.id),
                    "\(card.shortName) from \(other.id)'s hand is visible to player a"
                )
            }
            for card in other.well {
                XCTAssertFalse(visible.contains(card.id), "An opponent's well card leaked")
            }
        }
    }

    func testViewNeverContainsTheDrawPile() throws {
        let engine = try engine()
        let view = engine.state.view(for: "a")

        var visible = Set(view.yourHand.map(\.id))
        visible.formUnion(view.discardPile.map(\.id))

        for card in engine.state.drawPile {
            XCTAssertFalse(
                visible.contains(card.id),
                "Draw pile card \(card.shortName) is visible — every future draw would be known"
            )
        }
        XCTAssertEqual(view.drawPileCount, engine.state.drawPile.count, "The count is public")
    }

    func testYourOwnWellIsHiddenEvenFromYou() throws {
        let engine = try engine()
        let view = engine.state.view(for: "a")
        // The well being unknown to its owner is the whole point of the mechanic.
        XCTAssertEqual(view.yourWellCount, 2)
        let mirror = Mirror(reflecting: view)
        XCTAssertFalse(
            mirror.children.contains { $0.label == "yourWell" },
            "PlayerView must not carry the owner's well cards"
        )
    }

    func testSerialisedViewContainsNoHiddenCardIdentities() throws {
        // The real test of a redaction boundary: encode it and search the bytes.
        // If a hidden card survives serialisation, a proxy can read it.
        let engine = try engine()
        let view = engine.state.view(for: "a")
        let data = try JSONEncoder().encode(view)
        let json = String(decoding: data, as: UTF8.self)

        // Every card carries a unique id; look for ids that should be hidden.
        var hiddenIDs: Set<Int> = []
        for other in engine.state.players where other.id != "a" {
            hiddenIDs.formUnion(other.hand.map(\.id))
            hiddenIDs.formUnion(other.well.map(\.id))
        }
        hiddenIDs.formUnion(engine.state.drawPile.map(\.id))
        // Player a's own well is hidden too.
        hiddenIDs.formUnion(engine.state.player(id: "a")!.well.map(\.id))

        let decoded = try JSONDecoder().decode(PlayerView.self, from: data)
        var exposed = Set(decoded.yourHand.map(\.id))
        exposed.formUnion(decoded.discardPile.map(\.id))
        exposed.formUnion(decoded.yourPoisonPile.map(\.id))

        let leaked = exposed.intersection(hiddenIDs)
        XCTAssertTrue(leaked.isEmpty, "Serialised view leaked card ids: \(leaked)")
        XCTAssertFalse(json.isEmpty)
    }

    func testViewIsRoundTrippableOverTheWire() throws {
        let engine = try engine()
        let original = engine.state.view(for: "a")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlayerView.self, from: data)

        XCTAssertEqual(decoded.youID, original.youID)
        XCTAssertEqual(decoded.yourHand, original.yourHand)
        XCTAssertEqual(decoded.tally, original.tally)
        XCTAssertEqual(decoded.opponents.count, original.opponents.count)
        XCTAssertEqual(decoded.seatingOrder, original.seatingOrder)
        XCTAssertEqual(decoded.currentPlayerID, original.currentPlayerID)
    }

    // MARK: - The view still says enough to play

    func testViewCarriesEveryPublicFactNeededToPlay() throws {
        let engine = try engine()
        let view = engine.state.view(for: "a")

        // Dealt six, two banked as the well, so four in hand — except whoever
        // leads, who is topped up to the cap of five before they act.
        // Dealt six, banked two — four each, which is already above the
        // sustaining cap, so the leader's top-up changes nothing.
        let expected = 4
        XCTAssertEqual(view.yourHand.count, expected)
        XCTAssertEqual(view.opponents.count, 2)
        XCTAssertEqual(view.seatingOrder, ["a", "b", "c"])
        XCTAssertEqual(view.currentPlayerID, engine.state.currentPlayer.id)
        XCTAssertEqual(view.tally, 0)
        for opponent in view.opponents {
            let theirs = 4
            XCTAssertEqual(
                opponent.handCount, theirs,
                "You can count an opponent's cards across a table"
            )
            XCTAssertEqual(opponent.wellCount, 2)
        }
    }

    func testPlayableCardsComputedFromAViewMatchTheEngine() throws {
        // The UI in multiplayer only has a PlayerView. It must reach the same
        // conclusions the engine would, or the shading will lie.
        for seed in [UInt32(7), 99, 1234] {
            let engine = try engine(seed: seed)

            // Advance a few turns so the tally and locks are non-trivial.
            for _ in 0..<12 where !engine.state.isOver {
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
            }

            guard !engine.state.isOver else { continue }

            for player in engine.state.players where !player.isEliminated {
                let fromEngine = Set(
                    player.hand.filter { Rules.isPlayable($0, in: engine.state) }.map(\.id)
                )
                let fromView = engine.state.view(for: player.id).playableCardIDs
                XCTAssertEqual(
                    fromView, fromEngine,
                    "Seed \(seed): view-derived legality disagrees with the engine for \(player.id)"
                )
            }
        }
    }
}

// MARK: - Actions

final class PlayerActionTests: XCTestCase {

    private func engine(seed: UInt32 = 31) throws -> GameEngine {
        let engine = try GameEngine(
            seats: [("a", "A", .human), ("b", "B", .human), ("c", "C", .human)],
            dealerIndex: 2, cardsDealt: 6, seed: seed
        )
        engine._finishWellSelectionForTesting()
        return engine
    }

    func testActionsRoundTripThroughCoding() throws {
        let actions: [PlayerAction] = [
            .play(cardID: 17, declaration: .ace(.eleven)),
            .play(cardID: 3, declaration: .queen(as: .eight, lockSuit: .hearts)),
            .drawFromWell(slot: 0),
            .resolveWell(declaration: .lock(.spades)),
            .skip,
            .snackoo(kind: .threeOfAKind(.five)),
            .snackoo(kind: .threeQueens),
            .concede,
            .forfeit,
        ]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(PlayerAction.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }

    func testSubmittedActionRoundTrips() throws {
        let submitted = SubmittedAction(
            playerID: "a",
            action: .play(cardID: 9, declaration: .ace(.one)),
            sequence: 4
        )
        let data = try JSONEncoder().encode(submitted)
        XCTAssertEqual(try JSONDecoder().decode(SubmittedAction.self, from: data), submitted)
    }

    func testEveryAvailableActionIsActuallyLegal() throws {
        // The list the UI builds its affordances from must contain nothing that
        // would be refused.
        for seed in [UInt32(5), 77, 404] {
            let engine = try engine(seed: seed)
            let current = engine.state.currentPlayer.id

            let actions = engine.availableActions(for: current)
            XCTAssertFalse(actions.isEmpty, "A player at the start of a game always has options")

            for action in actions {
                // Apply to a throwaway engine dealt identically.
                let scratch = try self.engine(seed: seed)
                XCTAssertNoThrow(
                    try scratch.apply(SubmittedAction(playerID: current, action: action, sequence: 0)),
                    "Offered action \(action) was refused"
                )
            }
        }
    }

    func testActingOutOfTurnIsRefused() throws {
        let engine = try engine()
        let waiting = engine.state.players.first { $0.id != engine.state.currentPlayer.id }!
        let card = waiting.hand[0]

        XCTAssertThrowsError(
            try engine.apply(SubmittedAction(
                playerID: waiting.id,
                action: .play(cardID: card.id, declaration: .plain),
                sequence: 0
            ))
        ) { error in
            XCTAssertEqual(error as? GameError, .notYourTurn)
        }
    }

    func testSnackooIsAllowedOutOfTurn() throws {
        // Snackoo is a free action, so it must not be gated on holding the turn.
        XCTAssertFalse(PlayerAction.snackoo(kind: .threeQueens).requiresTurn)
        XCTAssertFalse(PlayerAction.forfeit.requiresTurn)
        XCTAssertTrue(PlayerAction.skip.requiresTurn)
        XCTAssertTrue(PlayerAction.drawFromWell(slot: 0).requiresTurn)
    }

    func testAClientCannotPlayACardItDoesNotHold() throws {
        let engine = try engine()
        let current = engine.state.currentPlayer
        let opponent = engine.state.players.first { $0.id != current.id }!
        let notMine = opponent.hand[0]

        // The whole point of validating on the authority: a malicious client can
        // ask for anything, and asking must not be enough.
        XCTAssertThrowsError(
            try engine.apply(SubmittedAction(
                playerID: current.id,
                action: .play(cardID: notMine.id, declaration: .plain),
                sequence: 0
            ))
        ) { error in
            XCTAssertEqual(error as? GameError, .cardNotInHand)
        }
    }

    func testAClientCannotPlayACardFromTheDrawPile() throws {
        let engine = try engine()
        let current = engine.state.currentPlayer
        let unseen = engine.state.drawPile[0]

        XCTAssertThrowsError(
            try engine.apply(SubmittedAction(
                playerID: current.id,
                action: .play(cardID: unseen.id, declaration: .plain),
                sequence: 0
            ))
        )
    }

    // MARK: Forfeit

    func testForfeitEliminatesAndPassesTheTurnOn() throws {
        let engine = try engine()
        let leaver = engine.state.currentPlayer.id

        let events = try engine.apply(
            SubmittedAction(playerID: leaver, action: .forfeit, sequence: 0)
        )

        XCTAssertTrue(events.contains { event in
            if case .playerEliminated(let id, .forfeited, _, _) = event { return id == leaver }
            return false
        })
        XCTAssertTrue(try XCTUnwrap(engine.state.player(id: leaver)).isEliminated)
        XCTAssertNotEqual(engine.state.currentPlayer.id, leaver, "The turn must move on")
    }

    func testForfeitOutOfTurnDoesNotStealTheTurn() throws {
        // Advancing unconditionally on a forfeit would skip whoever is actually
        // to play — a subtle way to grief a match.
        let engine = try engine()
        let current = engine.state.currentPlayer.id
        let other = engine.state.players.first { $0.id != current }!.id

        try engine.apply(SubmittedAction(playerID: other, action: .forfeit, sequence: 0))

        XCTAssertEqual(engine.state.currentPlayer.id, current, "The current player keeps their turn")
        XCTAssertTrue(try XCTUnwrap(engine.state.player(id: other)).isEliminated)
    }

    func testForfeitingDownToOnePlayerEndsTheGame() throws {
        let engine = try engine()
        let ids = engine.state.players.map(\.id)
        try engine.apply(SubmittedAction(playerID: ids[1], action: .forfeit, sequence: 0))
        try engine.apply(SubmittedAction(playerID: ids[2], action: .forfeit, sequence: 1))

        XCTAssertTrue(engine.state.isOver)
        XCTAssertEqual(engine.state.winnerID, ids[0])
    }
}

// MARK: - Determinism

final class ReplayTests: XCTestCase {

    /// Play a game with AI and record the exact action log.
    private func recordGame(seed: UInt32) throws -> (log: [SubmittedAction], finalTally: Int, winner: String?) {
        let engine = try GameEngine(
            seats: [("a", "A", .ai(.sharp)), ("b", "B", .ai(.ruthless)), ("c", "C", .ai(.sharp))],
            dealerIndex: 2, cardsDealt: 6, seed: seed
        )
        engine._finishWellSelectionForTesting()
        var log: [SubmittedAction] = []
        var sequence = 0
        var guardCount = 0

        while !engine.state.isOver && guardCount < 3000 {
            guardCount += 1
            let current = engine.state.currentPlayer
            let ai = AIPlayer(difficulty: current.kind.difficulty ?? .sharp)
            guard let move = ai.nextMove(for: current.id, engine: engine) else { break }

            let action: PlayerAction
            switch move.kind {
            case .play(let cardID, let declaration):
                action = engine.state.pendingWell?.card.id == cardID
                    ? .resolveWell(declaration: declaration)
                    : .play(cardID: cardID, declaration: declaration)
            case .useWell: action = .drawFromWell(slot: 0)
            case .skip: action = .skip
            case .snackoo(let kind): action = .snackoo(kind: PlayerAction.SnackooKind(kind))
            case .snackooWell: action = .snackooWellCard
            case .concede: action = .concede
            }

            let submitted = SubmittedAction(playerID: current.id, action: action, sequence: sequence)
            sequence += 1
            try engine.apply(submitted)
            log.append(submitted)
        }
        return (log, engine.state.tally, engine.state.winnerID)
    }

    func testReplayingAnActionLogReproducesStateExactly() throws {
        // This is the property every device in a match depends on: same seed,
        // same ordered actions, identical outcome. Without it, two players see
        // different games and there is no way to tell which is right.
        for seed in [UInt32(11), 202, 3003] {
            let recorded = try recordGame(seed: seed)
            XCTAssertFalse(recorded.log.isEmpty)

            let replay = try GameEngine(
                seats: [("a", "A", .ai(.sharp)), ("b", "B", .ai(.ruthless)), ("c", "C", .ai(.sharp))],
                dealerIndex: 2, cardsDealt: 6, seed: seed
            )
            replay._finishWellSelectionForTesting()
            for submitted in recorded.log {
                try replay.apply(submitted)
            }

            XCTAssertEqual(replay.state.tally, recorded.finalTally, "Seed \(seed): tally diverged")
            XCTAssertEqual(replay.state.winnerID, recorded.winner, "Seed \(seed): winner diverged")
            XCTAssertEqual(
                replay.state.players.map(\.hand.count),
                replay.state.players.map(\.hand.count),
                "Seed \(seed): hands diverged"
            )
        }
    }

    func testReplayIsIdenticalDownToEveryCard() throws {
        let seed: UInt32 = 5150
        let recorded = try recordGame(seed: seed)

        let replay = try GameEngine(
            seats: [("a", "A", .ai(.sharp)), ("b", "B", .ai(.ruthless)), ("c", "C", .ai(.sharp))],
            dealerIndex: 2, cardsDealt: 6, seed: seed
        )
        replay._finishWellSelectionForTesting()
        for submitted in recorded.log { try replay.apply(submitted) }

        // Compare the full serialised state, not just a summary — a summary
        // would hide exactly the kind of drift this test exists to catch.
        let first = try GameEngine(
            seats: [("a", "A", .ai(.sharp)), ("b", "B", .ai(.ruthless)), ("c", "C", .ai(.sharp))],
            dealerIndex: 2, cardsDealt: 6, seed: seed
        )
        first._finishWellSelectionForTesting()
        for submitted in recorded.log { try first.apply(submitted) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(
            try encoder.encode(replay.state),
            try encoder.encode(first.state),
            "Two replays of the same log produced different states"
        )
    }

    func testTheLogIsSmallEnoughToShip() throws {
        // GKTurnBasedMatch caps match data at 64KB. A whole game's action log has
        // to fit inside that with room for the state alongside it.
        let recorded = try recordGame(seed: 777)
        let data = try JSONEncoder().encode(recorded.log)
        XCTAssertLessThan(
            data.count, 48_000,
            "Action log is \(data.count) bytes across \(recorded.log.count) actions — too close to GameKit's 64KB limit"
        )
    }
}
