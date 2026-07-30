//
//  MatchTransport.swift
//  How a move gets from one player to the rest of the table.
//
//  Everything above this protocol — the game screen, the view model, the rules —
//  is identical whether the other players are AI in this process, humans passing
//  the phone around, or strangers on the other side of Game Center.
//
//  That's the whole point of the abstraction: GameKit becomes an adapter written
//  against a tested interface, rather than a rewrite of the game.
//

import Foundation

/// Who is sitting at the table, from the match's point of view.
struct MatchParticipant: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var kind: Kind

    enum Kind: Codable, Hashable, Sendable {
        /// A human on *this* device.
        case localHuman
        /// A human on another device.
        case remoteHuman
        /// Driven by the AI in this process.
        case ai(Difficulty)

        var isLocalHuman: Bool { self == .localHuman }
        var difficulty: Difficulty? {
            if case .ai(let value) = self { return value }
            return nil
        }
    }

    var enginePlayerKind: PlayerState.PlayerKind {
        switch kind {
        case .localHuman, .remoteHuman: return .human
        case .ai(let difficulty): return .ai(difficulty)
        }
    }
}

/// What a transport tells the game about.
enum MatchUpdate: Sendable {
    /// The match is ready; deal with this seating and seed.
    case started(participants: [MatchParticipant], seed: UInt32, handSize: Int)
    /// A participant submitted a move.
    case action(SubmittedAction)
    /// A participant left. The engine treats this as a forfeit.
    case participantLeft(playerID: String)
    /// The connection dropped. Not fatal for turn-based; fatal for real-time.
    case disconnected(reason: String)
}

/// Anything that can carry moves between seats.
///
/// Deliberately small. A transport moves `SubmittedAction`s and reports who is
/// present — it knows nothing about the rules, and cannot be a second place
/// where legality is decided.
protocol MatchTransport: AnyObject {
    /// The id of the player using this device.
    var localPlayerID: String { get }

    /// Called for each update. Set before `start()`.
    var onUpdate: ((MatchUpdate) -> Void)? { get set }

    /// Begin the match.
    func start() async throws

    /// Submit a move by the local player. Throws if the transport can't deliver.
    func send(_ action: SubmittedAction) async throws

    /// Leave the match.
    func leave() async
}

// MARK: - Loopback

/// An in-process transport: every seat is on this device.
///
/// Serves two real purposes rather than being test scaffolding:
///   * it is what pass-and-play and solo-vs-AI actually run on, and
///   * it lets the entire multiplayer path be tested with no network, no
///     account, and no simulator pairing.
///
/// It can also simulate latency and delivery failure, so the layers above get
/// exercised against a transport that isn't instantaneous and perfect — which
/// is the state GameKit will actually be in.
final class LoopbackTransport: MatchTransport {

    let localPlayerID: String
    var onUpdate: ((MatchUpdate) -> Void)?

    private let participants: [MatchParticipant]
    private let seed: UInt32
    private let handSize: Int

    /// Artificial delay applied to every delivery, for exercising the UI against
    /// a transport that isn't instant.
    var artificialLatency: Duration = .zero
    /// When set, the next `send` fails. Used to test that a refused move leaves
    /// the local game untouched rather than half-applied.
    var failNextSend: Bool = false

    private(set) var sent: [SubmittedAction] = []
    private var hasStarted = false

    init(
        localPlayerID: String,
        participants: [MatchParticipant],
        seed: UInt32,
        handSize: Int
    ) {
        self.localPlayerID = localPlayerID
        self.participants = participants
        self.seed = seed
        self.handSize = handSize
    }

    func start() async throws {
        guard !hasStarted else { return }
        hasStarted = true
        onUpdate?(.started(participants: participants, seed: seed, handSize: handSize))
    }

    func send(_ action: SubmittedAction) async throws {
        if failNextSend {
            failNextSend = false
            throw MatchError.deliveryFailed
        }
        if artificialLatency > .zero {
            try? await Task.sleep(for: artificialLatency)
        }
        sent.append(action)
        // Loopback: the local game is the authority, so the action comes
        // straight back as an accepted update.
        onUpdate?(.action(action))
    }

    func leave() async {
        onUpdate?(.participantLeft(playerID: localPlayerID))
    }
}

enum MatchError: Error, LocalizedError, Equatable {
    case deliveryFailed
    case notAuthenticated
    case matchmakingFailed(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .deliveryFailed:
            return "That move couldn't be sent. Check your connection and try again."
        case .notAuthenticated:
            return "Sign in to Game Center to play online."
        case .matchmakingFailed(let detail):
            return "Couldn't find a match: \(detail)"
        case .unsupported:
            return "Online play isn't available on this device."
        }
    }
}
