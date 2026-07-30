//
//  GameKitPayloadTests.swift
//  What actually crosses the wire in an online match.
//
//  A real two-player match can't be tested here — it needs two Game Center
//  accounts signing in interactively on two devices. What *can* be tested is the
//  payload, and that's where a silent bug would be worst: it's the one thing
//  every participant's device has to agree on, and a leak in it would hand an
//  opponent the whole game.
//

import XCTest
import GameKit
@testable import NinetyNine

@MainActor
final class GameKitPayloadTests: XCTestCase {

    private func payload(actions: [SubmittedAction] = []) -> GameKitTransport.MatchPayload {
        GameKitTransport.MatchPayload(
            seed: 20260730,
            handSize: 7,
            participantIDs: ["G:1", "G:2", "G:3"],
            participantNames: ["Ada", "Bo", "Cy"],
            actions: actions
        )
    }

    // MARK: - The wire format

    func testPayloadRoundTrips() throws {
        let original = payload(actions: [
            SubmittedAction(playerID: "G:1", action: .play(cardID: 4, declaration: .ace(.eleven)), sequence: 0),
            SubmittedAction(playerID: "G:2", action: .drawFromWell(slot: 1), sequence: 1),
            SubmittedAction(playerID: "G:2", action: .snackoo(kind: .threeQueens), sequence: 2),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameKitTransport.MatchPayload.self, from: data)

        XCTAssertEqual(decoded.seed, original.seed)
        XCTAssertEqual(decoded.handSize, original.handSize)
        XCTAssertEqual(decoded.participantIDs, original.participantIDs)
        XCTAssertEqual(decoded.actions, original.actions)
    }

    /// The payload carries the *seed and the action log*, never a GameState.
    /// A serialised state would contain every player's hand — handing the whole
    /// game to anyone who reads the blob.
    func testPayloadContainsNoCardIdentities() throws {
        let engine = try GameEngine(
            seats: [("G:1", "Ada", .human), ("G:2", "Bo", .human)],
            dealerIndex: 1, handSize: 7, seed: 20260730
        )
        // Record a few real moves.
        var actions: [SubmittedAction] = []
        var sequence = 0
        for _ in 0..<6 where !engine.state.isOver {
            let current = engine.state.currentPlayer
            let ai = AIPlayer(difficulty: .sharp)
            guard let move = ai.nextMove(for: current.id, engine: engine) else { break }
            guard case .play(let cardID, let declaration) = move.kind else { break }
            let submitted = SubmittedAction(
                playerID: current.id,
                action: .play(cardID: cardID, declaration: declaration),
                sequence: sequence
            )
            sequence += 1
            try engine.apply(submitted)
            actions.append(submitted)
        }

        let data = try JSONEncoder().encode(payload(actions: actions))
        let json = String(decoding: data, as: UTF8.self)

        // The blob may legitimately name cards that were *played* — those are
        // public, everyone watched them land. What it must never contain is a
        // hand or a draw pile, so the payload has no field that could hold one.
        let mirror = Mirror(reflecting: payload())
        let fields = Set(mirror.children.compactMap(\.label))
        XCTAssertEqual(
            fields, ["seed", "handSize", "participantIDs", "participantNames", "actions"],
            "A new payload field could leak hidden state — review before adding one"
        )
        XCTAssertFalse(json.contains("\"hand\""), "The payload must not carry hands")
        XCTAssertFalse(json.contains("\"well\""), "The payload must not carry wells")
        XCTAssertFalse(json.contains("\"drawPile\""), "The payload must not carry the deck")
    }

    /// GKTurnBasedMatch caps match data at 64KB. A whole game has to fit.
    func testAFullGameFitsInsideGameKitsMatchDataLimit() throws {
        let engine = try GameEngine(
            seats: [("G:1", "Ada", .ai(.sharp)), ("G:2", "Bo", .ai(.ruthless))],
            dealerIndex: 1, handSize: 7, seed: 4242
        )
        var actions: [SubmittedAction] = []
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
            case .concede: action = .concede
            }
            let submitted = SubmittedAction(playerID: current.id, action: action, sequence: sequence)
            sequence += 1
            try engine.apply(submitted)
            actions.append(submitted)
        }

        let data = try JSONEncoder().encode(payload(actions: actions))
        XCTAssertLessThan(
            data.count, 60_000,
            "A \(actions.count)-action game encodes to \(data.count) bytes — too close to GameKit's 64KB cap"
        )
    }

    /// Every participant replays the same log and must land in the same place.
    /// Without this, two players see different games and there is no way to tell
    /// which is right.
    func testEveryParticipantReplaysToTheSameState() throws {
        let seats: [(String, String, PlayerState.PlayerKind)] = [
            ("G:1", "Ada", .ai(.sharp)),
            ("G:2", "Bo", .ai(.casual)),
            ("G:3", "Cy", .ai(.ruthless)),
        ]
        let source = try GameEngine(seats: seats, dealerIndex: 2, handSize: 6, seed: 777)
        var actions: [SubmittedAction] = []
        var sequence = 0
        var guardCount = 0
        while !source.state.isOver && guardCount < 2000 {
            guardCount += 1
            let current = source.state.currentPlayer
            let ai = AIPlayer(difficulty: current.kind.difficulty ?? .sharp)
            guard let move = ai.nextMove(for: current.id, engine: source) else { break }
            let action: PlayerAction
            switch move.kind {
            case .play(let cardID, let declaration):
                action = source.state.pendingWell?.card.id == cardID
                    ? .resolveWell(declaration: declaration)
                    : .play(cardID: cardID, declaration: declaration)
            case .useWell: action = .drawFromWell(slot: 0)
            case .skip: action = .skip
            case .snackoo(let kind): action = .snackoo(kind: PlayerAction.SnackooKind(kind))
            case .concede: action = .concede
            }
            let submitted = SubmittedAction(playerID: current.id, action: action, sequence: sequence)
            sequence += 1
            try source.apply(submitted)
            actions.append(submitted)
        }

        // Round-trip the log through the wire format, as a peer would receive it.
        let data = try JSONEncoder().encode(payload(actions: actions))
        let received = try JSONDecoder().decode(GameKitTransport.MatchPayload.self, from: data)

        let replay = try GameEngine(seats: seats, dealerIndex: 2, handSize: 6, seed: 777)
        for action in received.actions { try replay.apply(action) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(
            try encoder.encode(replay.state),
            try encoder.encode(source.state),
            "A peer replaying the transmitted log reached a different state"
        )
    }

    // MARK: - Participants

    func testParticipantsFromThePayloadAreRemoteHumans() {
        let people = payload().participants
        XCTAssertEqual(people.count, 3)
        XCTAssertEqual(people.map(\.name), ["Ada", "Bo", "Cy"])
        for person in people {
            XCTAssertEqual(person.kind, .remoteHuman, "Seats arrive remote until localised")
        }
    }

    // MARK: - Session state

    func testOnlineIsUnavailableUntilSignedIn() {
        // The rest of the game must work without an account, so the unsigned
        // state is a reported condition rather than an error.
        let status = GameCenterSession.Status.unavailable(reason: "not signed in")
        XCTAssertFalse(status.isSignedIn)
        XCTAssertTrue(GameCenterSession.Status.signedIn(name: "Ada").isSignedIn)
        XCTAssertFalse(GameCenterSession.Status.signingIn.isSignedIn)
        XCTAssertFalse(GameCenterSession.Status.unknown.isSignedIn)
    }
}
