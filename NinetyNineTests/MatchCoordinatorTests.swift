//
//  MatchCoordinatorTests.swift
//  The match layer, exercised over the loopback transport.
//
//  These run with no network, no Game Center, and no developer account — which
//  is the entire reason the transport is abstracted. When GameKit arrives it
//  slots in behind the same protocol these tests already cover.
//

import XCTest
@testable import NinetyNine

@MainActor
final class MatchCoordinatorTests: XCTestCase {

    private func participants(
        humans: Int,
        ais: Int,
        difficulty: Difficulty = .sharp
    ) -> [MatchParticipant] {
        var all: [MatchParticipant] = (0..<humans).map {
            MatchParticipant(id: "h\($0)", name: "Human \($0 + 1)", kind: .localHuman)
        }
        all += (0..<ais).map {
            MatchParticipant(id: "ai\($0)", name: "Bot \($0 + 1)", kind: .ai(difficulty))
        }
        return all
    }

    private func makeMatch(
        humans: Int,
        ais: Int,
        mode: MatchCoordinator.MatchMode,
        seed: UInt32 = 2024,
        handSize: Int = 6
    ) -> (MatchCoordinator, LoopbackTransport) {
        let people = participants(humans: humans, ais: ais)
        let transport = LoopbackTransport(
            localPlayerID: people[0].id,
            participants: people,
            seed: seed,
            handSize: handSize
        )
        return (MatchCoordinator(transport: transport, mode: mode), transport)
    }

    /// The coordinator hands AI turns to a detached task; give them room to run.
    private func settle(_ seconds: Double = 0.35) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: - Starting

    func testStartingAMatchDealsAndProducesAView() async throws {
        let (match, _) = makeMatch(humans: 1, ais: 2, mode: .solo)
        try await match.start()

        let view = try XCTUnwrap(match.view)
        XCTAssertEqual(view.youID, "h0")
        XCTAssertEqual(view.yourHand.count, 6)
        XCTAssertEqual(view.opponents.count, 2)
        XCTAssertEqual(view.seatingOrder.count, 3)
        XCTAssertEqual(view.tally, 0)
    }

    func testTheLocalPlayerLeadsRatherThanWatching() async throws {
        // A match should never open by making you watch two bots.
        let (match, _) = makeMatch(humans: 1, ais: 2, mode: .solo)
        try await match.start()
        XCTAssertEqual(match.view?.currentPlayerID, "h0")
        XCTAssertTrue(try XCTUnwrap(match.view).isYourTurn)
    }

    // MARK: - Submitting moves

    func testSubmittingALegalMoveAdvancesTheMatch() async throws {
        let (match, transport) = makeMatch(humans: 1, ais: 1, mode: .solo)
        try await match.start()

        let view = try XCTUnwrap(match.view)
        let action = try XCTUnwrap(match.availableActions(for: "h0").first)
        await match.submit(action, by: "h0")
        await settle()

        XCTAssertEqual(transport.sent.count, 1, "The move should have gone over the transport")
        XCTAssertEqual(match.actionLog.count > 0, true)
        XCTAssertNil(match.lastError)
        XCTAssertNotEqual(match.view?.yourHand, view.yourHand, "The hand should have changed")
    }

    func testSubmittingAnIllegalMoveIsRefusedAndChangesNothing() async throws {
        let (match, transport) = makeMatch(humans: 1, ais: 1, mode: .solo)
        try await match.start()
        let before = try XCTUnwrap(match.view)

        // A card that exists but is not in this player's hand.
        await match.submit(.play(cardID: 9_999, declaration: .plain), by: "h0")
        await settle(0.1)

        XCTAssertNotNil(match.lastError, "A refused move must explain itself")
        XCTAssertTrue(transport.sent.isEmpty, "An illegal move shouldn't burn a round trip")
        XCTAssertEqual(match.view?.yourHand, before.yourHand, "State must be untouched")
        XCTAssertEqual(match.actionLog.count, 0)
    }

    func testAPlayerCannotMoveOnSomeoneElsesTurn() async throws {
        let (match, transport) = makeMatch(humans: 2, ais: 0, mode: .passAndPlay)
        try await match.start()

        // h0 leads; h1 tries to act.
        await match.submit(.skip, by: "h1")
        await settle(0.1)

        XCTAssertNotNil(match.lastError)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testTransportFailureSurfacesAndLeavesStateIntact() async throws {
        let (match, transport) = makeMatch(humans: 1, ais: 1, mode: .solo)
        try await match.start()
        let before = try XCTUnwrap(match.view)

        transport.failNextSend = true
        let action = try XCTUnwrap(match.availableActions(for: "h0").first)
        await match.submit(action, by: "h0")
        await settle(0.1)

        XCTAssertNotNil(match.lastError, "A delivery failure must be visible, not silent")
        XCTAssertEqual(match.view?.yourHand, before.yourHand, "A failed send must not half-apply")
        XCTAssertEqual(match.actionLog.count, 0)
    }

    // MARK: - AI participation

    func testAIOpponentsTakeTheirTurnsAutomatically() async throws {
        let (match, _) = makeMatch(humans: 1, ais: 2, mode: .solo)
        try await match.start()

        let action = try XCTUnwrap(match.availableActions(for: "h0").first)
        await match.submit(action, by: "h0")
        // AI turns are paced deliberately; wait long enough for two of them.
        await settle(4.0)

        XCTAssertGreaterThan(match.actionLog.count, 1, "The AI seats should have played")
        XCTAssertEqual(match.view?.currentPlayerID, "h0", "The turn should come back around")
    }

    // MARK: - Pass and play

    func testPassAndPlayShowsTheHandoffScreenBetweenPlayers() async throws {
        let (match, _) = makeMatch(humans: 2, ais: 0, mode: .passAndPlay)
        try await match.start()

        // h0 is holding the device and leads — no hand-off yet.
        match.acknowledgeHandoff()
        XCTAssertFalse(match.awaitingHandoff)
        XCTAssertEqual(match.view?.youID, "h0")

        let action = try XCTUnwrap(match.availableActions(for: "h0").first)
        await match.submit(action, by: "h0")
        await settle()

        // Now it's h1's turn, and the device must be covered before it shows
        // their hand — otherwise h0 simply reads it.
        XCTAssertTrue(match.awaitingHandoff, "The device must be covered between players")
        XCTAssertEqual(match.handoffTargetName, "Human 2")
    }

    func testTheViewDoesNotFollowTheTurnBeforeTheHandoffIsAcknowledged() async throws {
        // The regression this exists for: an earlier version refreshed the view
        // to whoever's turn it was, which swapped the screen to the next
        // player's hand while the previous player was still holding the device.
        // The hand-off prompt was drawn over a view that had already changed.
        let (match, _) = makeMatch(humans: 2, ais: 0, mode: .passAndPlay)
        try await match.start()
        match.acknowledgeHandoff()
        XCTAssertEqual(match.view?.youID, "h0")

        let action = try XCTUnwrap(match.availableActions(for: "h0").first)
        await match.submit(action, by: "h0")
        await settle()

        XCTAssertTrue(match.awaitingHandoff)
        XCTAssertEqual(
            match.view?.youID, "h0",
            "The view must stay with the player still holding the device until hand-off is confirmed"
        )
    }

    func testHandoffRevealsTheNextPlayersOwnHand() async throws {
        let (match, _) = makeMatch(humans: 2, ais: 0, mode: .passAndPlay)
        try await match.start()
        match.acknowledgeHandoff()

        let firstHand = try XCTUnwrap(match.view).yourHand
        let action = try XCTUnwrap(match.availableActions(for: "h0").first)
        await match.submit(action, by: "h0")
        await settle()

        match.acknowledgeHandoff()
        let secondView = try XCTUnwrap(match.view)

        XCTAssertEqual(secondView.youID, "h1", "The view should now belong to the second player")
        XCTAssertNotEqual(secondView.yourHand, firstHand)
        XCTAssertFalse(match.awaitingHandoff)
    }

    func testPassAndPlayNeverLeaksTheOtherPlayersHand() async throws {
        // The whole risk of one shared screen.
        let (match, _) = makeMatch(humans: 2, ais: 0, mode: .passAndPlay)
        try await match.start()
        match.acknowledgeHandoff()

        let view = try XCTUnwrap(match.view)
        XCTAssertEqual(view.youID, "h0")
        for opponent in view.opponents {
            XCTAssertEqual(opponent.id, "h1")
            // Counts, never cards.
            XCTAssertEqual(opponent.handCount, 6)
        }
        // And nothing in the encoded view carries the opponent's cards.
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(PlayerView.self, from: data)
        XCTAssertEqual(decoded.yourHand.count, 6)
        XCTAssertEqual(Set(decoded.yourHand.map(\.id)).count, 6)
    }

    func testSoloModeNeverAsksForAHandoff() async throws {
        let (match, _) = makeMatch(humans: 1, ais: 2, mode: .solo)
        try await match.start()
        XCTAssertFalse(match.awaitingHandoff)

        let action = try XCTUnwrap(match.availableActions(for: "h0").first)
        await match.submit(action, by: "h0")
        await settle(3.0)
        XCTAssertFalse(match.awaitingHandoff, "There's nobody to hand the device to in solo")
    }

    // MARK: - Leaving

    func testAParticipantLeavingForfeitsTheirSeat() async throws {
        let people = participants(humans: 1, ais: 2)
        let transport = LoopbackTransport(
            localPlayerID: "h0", participants: people, seed: 99, handSize: 6
        )
        let match = MatchCoordinator(transport: transport, mode: .online)
        try await match.start()

        transport.onUpdate?(.participantLeft(playerID: "ai0"))
        await settle(0.15)

        let view = try XCTUnwrap(match.view)
        let left = try XCTUnwrap(view.opponent(id: "ai0"))
        XCTAssertTrue(left.isEliminated, "A player who leaves should be out of the game")
    }

    func testDisconnectSurfacesAsAnError() async throws {
        let (match, transport) = makeMatch(humans: 1, ais: 1, mode: .online)
        try await match.start()

        transport.onUpdate?(.disconnected(reason: "Connection lost"))
        await settle(0.15)
        XCTAssertEqual(match.lastError, "Connection lost")
    }

    // MARK: - The log

    func testTheActionLogReplaysToTheSameState() async throws {
        // What every device in an online match relies on.
        let (match, _) = makeMatch(humans: 1, ais: 2, mode: .solo, seed: 8888)
        try await match.start()

        for _ in 0..<3 {
            guard let action = match.availableActions(for: "h0").first else { break }
            await match.submit(action, by: "h0")
            await settle(3.5)
            if match.isOver { break }
        }

        XCTAssertFalse(match.actionLog.isEmpty)

        let replay = try GameEngine(
            seats: match.participants.map { ($0.id, $0.name, $0.enginePlayerKind) },
            dealerIndex: match.participants.count - 1,
            handSize: 6,
            seed: 8888
        )
        for entry in match.actionLog { try replay.apply(entry) }

        XCTAssertEqual(replay.state.tally, match.view?.tally, "Replay diverged from the live match")
        XCTAssertEqual(replay.state.currentPlayer.id, match.view?.currentPlayerID)
    }

    func testLatencyDoesNotBreakTheMatch() async throws {
        // GameKit will not be instantaneous. Make sure the layers above cope.
        let (match, transport) = makeMatch(humans: 1, ais: 1, mode: .online)
        transport.artificialLatency = .milliseconds(120)
        try await match.start()

        let action = try XCTUnwrap(match.availableActions(for: "h0").first)
        await match.submit(action, by: "h0")
        await settle(0.6)

        XCTAssertEqual(match.actionLog.count >= 1, true)
        XCTAssertNil(match.lastError)
    }
}

// MARK: - Participant modelling

final class MatchParticipantTests: XCTestCase {

    func testParticipantKindMapsOntoEngineSeats() {
        XCTAssertEqual(
            MatchParticipant(id: "a", name: "A", kind: .localHuman).enginePlayerKind,
            .human
        )
        // A remote human is still a human seat to the engine — the engine has no
        // concept of where a player is sitting, and shouldn't.
        XCTAssertEqual(
            MatchParticipant(id: "b", name: "B", kind: .remoteHuman).enginePlayerKind,
            .human
        )
        XCTAssertEqual(
            MatchParticipant(id: "c", name: "C", kind: .ai(.ruthless)).enginePlayerKind,
            .ai(.ruthless)
        )
    }

    func testOnlyLocalHumansHoldTheDevice() {
        XCTAssertTrue(MatchParticipant.Kind.localHuman.isLocalHuman)
        XCTAssertFalse(MatchParticipant.Kind.remoteHuman.isLocalHuman)
        XCTAssertFalse(MatchParticipant.Kind.ai(.casual).isLocalHuman)
    }

    func testParticipantsRoundTripForTheWire() throws {
        let people = [
            MatchParticipant(id: "a", name: "Ada", kind: .localHuman),
            MatchParticipant(id: "b", name: "Bo", kind: .remoteHuman),
            MatchParticipant(id: "c", name: "Cy", kind: .ai(.sharp)),
        ]
        let data = try JSONEncoder().encode(people)
        XCTAssertEqual(try JSONDecoder().decode([MatchParticipant].self, from: data), people)
    }
}
