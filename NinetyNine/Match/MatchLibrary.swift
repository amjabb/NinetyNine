//
//  MatchLibrary.swift
//  The player's own list of Game Center matches, and the one operation Apple's
//  matchmaker will not reliably perform: removing them.
//
//  Why this exists at all, when `GKTurnBasedMatchmakerViewController` already
//  shows a list with swipe-to-delete:
//
//  Because that swipe calls `remove()` directly, and GameKit refuses to remove a
//  match the local player is still participating in. Its own list has no way to
//  say so, so the row animates away, the call fails, and the row comes back —
//  which is exactly "I'm trying to delete old games and it won't let me". The
//  documented order is *leave the match, then remove it*, and nothing in Apple's
//  UI does the first half for an open match.
//
//  So the list is ours, the delete is the two-step, and Apple's matchmaker stays
//  for what it is genuinely good at: finding people to play.
//

import Foundation
import GameKit

@MainActor
final class MatchLibrary: ObservableObject {
    /// Shared, like `Settings` and `Records`, so the list survives navigating
    /// away and back rather than re-fetching every time it appears.
    static let shared = MatchLibrary()

    private init() {}

    /// One row: the match, plus everything the list needs to describe it without
    /// re-deriving it in the view body.
    struct Entry: Identifiable {
        let match: GKTurnBasedMatch
        var id: String { match.matchID }
        var opponentNames: [String]
        var isYourTurn: Bool
        var isFinished: Bool
        /// Still waiting for Game Center to find somebody. These are the ones
        /// that pile up, because there is no game in them to finish.
        var isWaitingForPlayers: Bool
        var lastActivity: Date

        var opponentSummary: String {
            switch opponentNames.count {
            case 0: return "Waiting for players"
            case 1: return opponentNames[0]
            case 2: return "\(opponentNames[0]) and \(opponentNames[1])"
            default: return "\(opponentNames[0]) and \(opponentNames.count - 1) others"
            }
        }

        var statusLine: String {
            if isFinished { return "Finished" }
            if isWaitingForPlayers { return "Waiting for players" }
            return isYourTurn ? "Your turn" : "Their turn"
        }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isLoading = false
    /// The ids currently being removed, so their rows can show it rather than
    /// sitting there looking ignored while the round trip happens.
    @Published private(set) var deleting: Set<String> = []
    @Published var lastError: String?

    // MARK: - Loading

    func reload() async {
        guard GKLocalPlayer.local.isAuthenticated else {
            entries = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let matches = try await GKTurnBasedMatch.loadMatches()
            entries = matches.map(Self.entry(for:))
                .sorted { $0.lastActivity > $1.lastActivity }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func entry(for match: GKTurnBasedMatch) -> Entry {
        let localID = GKLocalPlayer.local.gamePlayerID
        let others = match.participants.filter { $0.player?.gamePlayerID != localID }
        return Entry(
            match: match,
            opponentNames: others.compactMap { $0.player?.displayName },
            isYourTurn: match.status == .open
                && match.currentParticipant?.player?.gamePlayerID == localID,
            isFinished: match.status == .ended,
            isWaitingForPlayers: match.status == .matching
                || others.contains { $0.player == nil },
            lastActivity: match.participants
                .compactMap(\.lastTurnDate)
                .max() ?? Date.distantPast
        )
    }

    // MARK: - Deleting

    /// Remove a match from this player's list for good.
    ///
    /// Optimistic about the row and honest about the result: it disappears
    /// immediately, and comes back with an explanation if GameKit refused —
    /// which beats the alternative the player has been living with, where it
    /// disappears, silently fails, and returns with no explanation at all.
    func delete(_ entry: Entry) async {
        deleting.insert(entry.id)
        defer { deleting.remove(entry.id) }
        do {
            try await Self.leaveAndRemove(entry.match)
            entries.removeAll { $0.id == entry.id }
        } catch {
            lastError = "That match couldn't be removed. \(error.localizedDescription)"
            // Re-read rather than guess: the quit half may well have succeeded.
            await reload()
        }
        await GameCenterSession.shared.refreshMatchCounts()
    }

    /// Leave the match if we're still in it, then remove it.
    ///
    /// The order matters and is the whole fix. `remove()` on a match the local
    /// player is still playing fails; the match has to be *ended for us* first,
    /// which means one of three calls depending on where the turn is.
    static func leaveAndRemove(_ match: GKTurnBasedMatch) async throws {
        let localID = GKLocalPlayer.local.gamePlayerID
        let local = match.participants.first { $0.player?.gamePlayerID == localID }

        // Already done with, from this player's side. Straight to the removal.
        let outcome = local?.matchOutcome ?? GKTurnBasedMatch.Outcome.none
        if match.status == .ended || outcome != .none {
            try await removeWithBackoff(match)
            return
        }

        // Carry the existing match data across. Quitting with `Data()` would
        // hand everyone still playing an empty match — their whole game, wiped,
        // because somebody else tidied their list.
        let data = await currentData(of: match)
        let others = match.participants.filter {
            $0.player?.gamePlayerID != localID && $0.matchOutcome == .none
        }

        if match.currentParticipant?.player?.gamePlayerID == localID {
            if others.isEmpty {
                // Nobody to hand the turn to — an abandoned match, or one that
                // never found an opponent. Ending it needs every participant to
                // carry an outcome or GameKit rejects the call outright.
                for participant in match.participants where participant.matchOutcome == .none {
                    participant.matchOutcome = .quit
                }
                try await match.endMatchInTurn(withMatch: data)
            } else {
                try await match.participantQuitInTurn(
                    with: .quit,
                    nextParticipants: others,
                    turnTimeout: GKTurnTimeoutDefault,
                    match: data
                )
            }
        } else {
            try await match.participantQuitOutOfTurn(with: .quit)
        }

        // Re-read before removing. The object in hand still believes we're
        // playing, and `remove()` is checked against the server's idea of the
        // match, not ours.
        let refreshed = (try? await GKTurnBasedMatch.load(withID: match.matchID)) ?? match
        try await removeWithBackoff(refreshed)
    }

    /// The match's data, loaded if it isn't attached.
    static func currentData(of match: GKTurnBasedMatch) async -> Data {
        if let data = match.matchData, !data.isEmpty { return data }
        return (try? await match.loadMatchData()) ?? Data()
    }

    /// Quitting and removing are two server round trips, and the second can
    /// arrive before the first has propagated — the same lag that makes turn
    /// events show up with stale data. Retrying beats reporting a failure that
    /// would have worked a second later.
    private static func removeWithBackoff(_ match: GKTurnBasedMatch) async throws {
        var failure: Error?
        for delay in [0.0, 0.75, 2.0] {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            do {
                try await match.remove()
                return
            } catch {
                failure = error
            }
        }
        throw failure ?? MatchError.deliveryFailed
    }
}
