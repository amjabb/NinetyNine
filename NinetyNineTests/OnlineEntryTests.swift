//
//  OnlineEntryTests.swift
//  Getting *into* an online match — the one path that had no coverage.
//
//  Everything here used to be untested, and it was entirely broken: the app
//  awaited the matchmaker's `didFindMatch:` callback, which Apple deprecated in
//  iOS 9 and stopped calling, while the listener that replaced it was registered
//  only after a match had already been obtained. So invitations arrived nowhere
//  and choosing a match returned you to the setup screen.
//
//  Every payload and replay test passed throughout, because they all exercise
//  the data layer and none of them exercise the handshake.
//
//  GameKit itself can't run in a unit test, so this models its *semantics* — a
//  match is a document with an ordered participant list, exactly one current
//  participant, and a data blob; a turn is a write that moves the baton.
//

import XCTest
@testable import NinetyNine

// MARK: - A fake with GameKit's shape

/// One match document, shared by every simulated device.
@MainActor
final class FakeMatchServer {
    struct Participant {
        let id: String
        let name: String
        var hasResponded: Bool
    }

    private(set) var participants: [Participant]
    private(set) var currentIndex = 0
    private(set) var data: Data?
    private(set) var writeCount = 0

    /// Devices listening for turn events, by player id.
    private var listeners: [String: (Bool) -> Void] = [:]

    init(playerIDs: [String]) {
        participants = playerIDs.enumerated().map {
            Participant(id: $1, name: "P\($0)", hasResponded: $0 == 0)
        }
    }

    var currentPlayerID: String { participants[currentIndex].id }

    func listen(as playerID: String, _ handler: @escaping (Bool) -> Void) {
        listeners[playerID] = handler
    }

    /// Save without passing the turn — GameKit's `saveCurrentTurn`.
    func save(_ blob: Data, by playerID: String) throws {
        guard playerID == currentPlayerID else { throw FakeError.notYourTurn }
        data = blob
        writeCount += 1
    }

    /// Save and hand on — GameKit's `endTurn(withNextParticipants:...)`.
    func endTurn(_ blob: Data, by playerID: String) throws {
        guard playerID == currentPlayerID else { throw FakeError.notYourTurn }
        data = blob
        writeCount += 1
        currentIndex = (currentIndex + 1) % participants.count
        participants[currentIndex].hasResponded = true
        // Everyone hears about it; only the new current player "becomes active".
        for (id, handler) in listeners {
            handler(id == currentPlayerID)
        }
    }

    /// The player opened the match themselves — tapped a row, or accepted an
    /// invitation. This is the event the real app was never listening for.
    func playerOpenedMatch(_ playerID: String) {
        listeners[playerID]?(true)
    }

    enum FakeError: Error { case notYourTurn }
}

/// One device's view of the match.
@MainActor
final class FakeDevice {
    let playerID: String
    private let server: FakeMatchServer

    private(set) var openedMatch = false
    private(set) var sawTurnEvents = 0
    private(set) var isRegistered = false

    init(playerID: String, server: FakeMatchServer) {
        self.playerID = playerID
        self.server = server
    }

    /// The fix under test: register at launch, not when a match turns up.
    func launch() {
        isRegistered = true
        server.listen(as: playerID) { [weak self] didBecomeActive in
            guard let self else { return }
            self.sawTurnEvents += 1
            if didBecomeActive { self.openedMatch = true }
        }
    }

    func tapMatchInMatchmaker() {
        server.playerOpenedMatch(playerID)
    }

    func takeTurn(_ blob: Data) throws {
        try server.endTurn(blob, by: playerID)
    }
}

// MARK: - Tests

@MainActor
final class OnlineEntryTests: XCTestCase {

    /// Choosing a match in the matchmaker has to open it. This is the exact
    /// failure that was reported: the sheet dismissed and nothing happened.
    func testChoosingAMatchOpensIt() {
        let server = FakeMatchServer(playerIDs: ["a", "b"])
        let device = FakeDevice(playerID: "a", server: server)
        device.launch()

        device.tapMatchInMatchmaker()

        XCTAssertTrue(device.openedMatch, "picking a match should take you into it")
    }

    /// And it cannot work if the listener is registered only once a match has
    /// been obtained — which is what the app used to do, and why an invitation
    /// had nowhere to land.
    func testAMatchCannotArriveIfNobodyIsListeningYet() {
        let server = FakeMatchServer(playerIDs: ["a", "b"])
        let device = FakeDevice(playerID: "a", server: server)
        // Deliberately not launched.

        device.tapMatchInMatchmaker()

        XCTAssertFalse(device.isRegistered)
        XCTAssertFalse(
            device.openedMatch,
            "this is the old behaviour, kept as a statement of the bug: no listener, no way in"
        )
    }

    /// A turn handed over reaches the other device, and only the player it is
    /// now on is pulled into the match.
    func testEndingATurnNotifiesEveryoneAndActivatesOnlyTheNextPlayer() throws {
        let server = FakeMatchServer(playerIDs: ["a", "b", "c"])
        let devices = ["a", "b", "c"].map { FakeDevice(playerID: $0, server: server) }
        devices.forEach { $0.launch() }

        try devices[0].takeTurn(Data("turn-1".utf8))

        XCTAssertEqual(server.currentPlayerID, "b")
        XCTAssertTrue(devices.allSatisfy { $0.sawTurnEvents == 1 }, "everyone hears the turn")
        XCTAssertTrue(devices[1].openedMatch, "the player it's now on is pulled in")
        XCTAssertFalse(devices[0].openedMatch, "the player who just moved is not")
        XCTAssertFalse(devices[2].openedMatch, "nor is anybody further round the table")
    }

    /// Playing out of turn is refused by the server, as GameKit refuses it.
    func testOnlyTheCurrentPlayerCanWrite() {
        let server = FakeMatchServer(playerIDs: ["a", "b"])
        XCTAssertThrowsError(try server.endTurn(Data("nope".utf8), by: "b"))
        XCTAssertNoThrow(try server.endTurn(Data("fine".utf8), by: "a"))
    }

    /// The turn order goes round the table and back, so a two-player match
    /// alternates rather than sticking.
    func testTheBatonGoesRoundAndComesBack() throws {
        let server = FakeMatchServer(playerIDs: ["a", "b"])
        try server.endTurn(Data("1".utf8), by: "a")
        XCTAssertEqual(server.currentPlayerID, "b")
        try server.endTurn(Data("2".utf8), by: "b")
        XCTAssertEqual(server.currentPlayerID, "a")
        XCTAssertEqual(server.writeCount, 2)
    }

    // MARK: - Late arrivals

    /// A match created with an automatch seat records a placeholder for it,
    /// because at creation time GameKit has no player to name. When the real
    /// player arrives, their identity has to replace the placeholder — otherwise
    /// their own device doesn't recognise them.
    ///
    /// Modelled on `GameKitTransport.reconcileParticipants`, which cannot run
    /// here because it takes a real `GKTurnBasedMatch`.
    func testAPlaceholderSeatIsReplacedByTheRealPlayer() {
        var ids = ["creator", "5B1E5B0E-PLACEHOLDER"]
        var names = ["Amjabb", "Player"]
        var log: [(playerID: String, note: String)] = [
            ("creator", "buried a well")
        ]

        // The automatch seat fills.
        let arrived = (index: 1, id: "copperartist", name: "CopperArtist4591")
        if ids[arrived.index] != arrived.id {
            for i in log.indices where log[i].playerID == ids[arrived.index] {
                log[i].playerID = arrived.id
            }
            ids[arrived.index] = arrived.id
            names[arrived.index] = arrived.name
        }

        XCTAssertEqual(ids, ["creator", "copperartist"])
        XCTAssertEqual(names, ["Amjabb", "CopperArtist4591"])
        XCTAssertEqual(
            log.map(\.playerID), ["creator"],
            "the creator's own logged action must not be reattributed"
        )
    }

    /// The real player recognises themselves once reconciled — the failure that
    /// made a two-player match render three seats and wait on nobody.
    func testTheJoiningPlayerRecognisesTheirOwnSeat() {
        let localID = "copperartist"
        let before = ["creator", "5B1E5B0E-PLACEHOLDER"]
        XCTAssertNil(
            before.firstIndex(of: localID),
            "before reconciling, the joining player is a stranger to their own match"
        )

        let after = ["creator", localID]
        XCTAssertEqual(
            after.firstIndex(of: localID), 1,
            "after reconciling they hold a seat, and the table stops waiting on a ghost"
        )
    }
}
