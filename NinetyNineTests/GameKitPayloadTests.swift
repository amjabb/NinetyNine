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
            cardsDealt: 7,
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
        XCTAssertEqual(decoded.cardsDealt, original.cardsDealt)
        XCTAssertEqual(decoded.participantIDs, original.participantIDs)
        XCTAssertEqual(decoded.actions, original.actions)
    }

    /// The payload carries the *seed and the action log*, never a GameState.
    /// A serialised state would contain every player's hand — handing the whole
    /// game to anyone who reads the blob.
    func testPayloadContainsNoCardIdentities() throws {
        let engine = try GameEngine(
            seats: [("G:1", "Ada", .human), ("G:2", "Bo", .human)],
            dealerIndex: 1, cardsDealt: 7, seed: 20260730
        )
        engine._finishWellSelectionForTesting()
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
        // `autoAssignWells` is a Bool: a rule every player is entitled to know,
        // carrying no card identity. Reviewed on the way in, which is what this
        // assertion is for.
        XCTAssertEqual(
            fields,
            [
                "rulesVersion", "seed", "cardsDealt",
                "participantIDs", "participantNames", "autoAssignWells", "actions",
            ],
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
            dealerIndex: 1, cardsDealt: 7, seed: 4242
        )
        engine._finishWellSelectionForTesting()
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
            case .snackooWell: action = .snackooWellCard
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
            ("G:2", "Bo", .ai(.sharp)),
            ("G:3", "Cy", .ai(.ruthless)),
        ]
        let source = try GameEngine(seats: seats, dealerIndex: 2, cardsDealt: 6, seed: 777)
        source._finishWellSelectionForTesting()
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
            case .snackooWell: action = .snackooWellCard
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

        let replay = try GameEngine(seats: seats, dealerIndex: 2, cardsDealt: 6, seed: 777)
        replay._finishWellSelectionForTesting()
        for action in received.actions { try replay.apply(action) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(
            try encoder.encode(replay.state),
            try encoder.encode(source.state),
            "A peer replaying the transmitted log reached a different state"
        )
    }

    /// A run is one action carrying several card IDs. If it didn't survive the
    /// wire it would desync every peer the moment someone played a pair — and
    /// silently, since the log would still apply cleanly up to that point.
    func testARunOfCardsSurvivesTheWireAndReplaysIdentically() throws {
        let seats: [(String, String, PlayerState.PlayerKind)] = [
            ("G:1", "Ada", .human), ("G:2", "Bo", .human),
        ]
        let source = try GameEngine(seats: seats, dealerIndex: 1, cardsDealt: 7, seed: 31337)
        source._finishWellSelectionForTesting()

        // Force a hand that holds a run, so the test doesn't depend on the deal.
        var seeded = source.state
        let seat = try XCTUnwrap(seeded.players.firstIndex { $0.id == "G:1" })
        let run = [Suit.spades, .hearts, .clubs].enumerated().map {
            Card(id: 900 + $0.offset, rank: .three, suit: $0.element)
        }
        seeded.players[seat].hand = run
        seeded.currentPlayerIndex = seat
        seeded.tally = 12
        source._replaceStateForTesting(seeded)

        let submitted = SubmittedAction(
            playerID: "G:1",
            action: .playSet(cardIDs: run.map(\.id), declaration: .plain),
            sequence: 0
        )
        try source.apply(submitted)
        XCTAssertEqual(source.state.tally, 21)

        let data = try JSONEncoder().encode(payload(actions: [submitted]))
        let received = try JSONDecoder().decode(GameKitTransport.MatchPayload.self, from: data)
        XCTAssertEqual(received.actions, [submitted], "The card IDs have to arrive in order")

        let replay = try GameEngine(seats: seats, dealerIndex: 1, cardsDealt: 7, seed: 31337)
        replay._finishWellSelectionForTesting()
        replay._replaceStateForTesting(seeded)
        for action in received.actions { try replay.apply(action) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(replay.state), try encoder.encode(source.state))
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

// MARK: - Rules versioning

/// The failure this guards against is the quiet one. A match log written by an
/// older build still *applies* cleanly to newer code — every action is valid —
/// it just replays into a different game, because the deal changed. Two players
/// end up looking at contradictory tables with nothing reported.
@MainActor
final class MatchCompatibilityTests: XCTestCase {

    private func payload(version: Int) -> GameKitTransport.MatchPayload {
        GameKitTransport.MatchPayload(
            rulesVersion: version,
            seed: 7,
            cardsDealt: 7,
            participantIDs: ["G:1", "G:2"],
            participantNames: ["Ada", "Bo"],
            actions: []
        )
    }

    func testAPayloadFromThisBuildIsReplayable() {
        XCTAssertTrue(payload(version: GameKitTransport.MatchPayload.currentRules).isReplayable)
    }

    func testAPayloadFromAnOlderRulesVersionIsRefused() {
        XCTAssertFalse(payload(version: 1).isReplayable)
    }

    /// A newer build's match is equally unusable here — this device would replay
    /// it wrongly in the other direction.
    func testAPayloadFromANewerRulesVersionIsAlsoRefused() {
        XCTAssertFalse(payload(version: GameKitTransport.MatchPayload.currentRules + 1).isReplayable)
    }

    /// Payloads written before versioning existed carry no field at all, and are
    /// version 1 by definition rather than "current".
    func testAPayloadWithNoVersionFieldIsTreatedAsTheOldestRules() throws {
        let legacy = """
        {"seed":7,"cardsDealt":7,"participantIDs":["G:1","G:2"],\
        "participantNames":["Ada","Bo"],"actions":[]}
        """
        let decoded = try JSONDecoder().decode(
            GameKitTransport.MatchPayload.self,
            from: Data(legacy.utf8)
        )
        XCTAssertEqual(decoded.rulesVersion, 1)
        XCTAssertFalse(decoded.isReplayable, "An unversioned match predates the new deal")
    }

    func testTheVersionSurvivesARoundTrip() throws {
        // Against whatever this build's version is, not a hardcoded number —
        // otherwise this test starts failing every time the rules move, which
        // is exactly when it needs to still be measuring something.
        let current = GameKitTransport.MatchPayload.currentRules
        let data = try JSONEncoder().encode(payload(version: current))
        let decoded = try JSONDecoder().decode(GameKitTransport.MatchPayload.self, from: data)
        XCTAssertEqual(decoded.rulesVersion, current)
        XCTAssertTrue(decoded.isReplayable)
    }

    /// Every version before this one is refused. Shuffling the well became an
    /// action in rules 3, and an older client can't decode a case it has never
    /// heard of — its match would quietly stop updating rather than fail loudly.
    func testEveryEarlierRulesVersionIsRefused() {
        for version in 1..<GameKitTransport.MatchPayload.currentRules {
            XCTAssertFalse(
                payload(version: version).isReplayable,
                "A rules-\(version) match should be refused"
            )
        }
    }

    func testTheRefusalExplainsItselfToThePlayer() {
        let message = MatchError.incompatibleRules.localizedDescription
        XCTAssertTrue(message.contains("older version"), "Got: \(message)")
        XCTAssertTrue(message.contains("update"), "It should say what to do about it")
    }
}
