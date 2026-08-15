//
//  GameCenterSession.swift
//  Sign-in state for Game Center, as one observable thing.
//
//  Authentication is not a one-shot: the handler can fire again when the player
//  signs out, switches account, or the system decides to re-prompt. Scattering
//  `GKLocalPlayer.local.isAuthenticated` checks through the UI would mean each
//  one silently going stale. This holds the state and republishes it.
//

import Foundation
import GameKit
import SwiftUI

/// Something that wants turn events for one particular match — in practice the
/// transport driving the table that is on screen.
@MainActor
protocol GameCenterMatchObserver: AnyObject {
    var observedMatchID: String? { get }
    func matchDidUpdate(_ match: GKTurnBasedMatch)
    func matchDidEnd(_ match: GKTurnBasedMatch)
    func playerWantsToQuit(_ playerID: String)
}

@MainActor
final class GameCenterSession: NSObject, ObservableObject {
    static let shared = GameCenterSession()

    enum Status: Equatable {
        case unknown
        case signingIn
        case signedIn(name: String)
        case unavailable(reason: String)

        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }
    }

    @Published private(set) var status: Status = .unknown

    /// A match GameKit has told us to open — an invitation accepted, a push
    /// tapped, or a row chosen in the matchmaker. The root view watches this and
    /// takes the app into the game.
    ///
    /// This is the *only* way into an online match. There used to be another,
    /// through the matchmaker's `didFindMatch:` delegate callback, except that
    /// was deprecated in iOS 9 and replaced by exactly this event — so the app
    /// awaited a callback the system stopped making in 2015. Picking a match
    /// dismissed the sheet and returned to the setup screen, and invitations had
    /// nowhere to arrive at all, because the listener below was registered only
    /// *after* a match had been obtained.
    @Published var matchToOpen: GKTurnBasedMatch?

    /// How many matches are waiting on this player, for the menu to say so.
    @Published private(set) var matchesAwaitingYou = 0
    @Published private(set) var totalMatches = 0

    /// The transport for the match currently on screen, if any. Turn events for
    /// that match belong to it rather than reopening the table.
    weak var activeObserver: GameCenterMatchObserver?

    private var hasStartedAuthentication = false
    private var hasRegisteredListener = false

    private override init() { super.init() }

    /// Kick off authentication. Safe to call repeatedly — only the first call
    /// installs the handler.
    func authenticateIfNeeded() {
        guard !hasStartedAuthentication else { return }
        hasStartedAuthentication = true
        status = .signingIn

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }

                if let viewController {
                    // Game Center wants to show its sign-in sheet.
                    GameKitTransport.topViewController()?.present(viewController, animated: true)
                    return
                }
                if GKLocalPlayer.local.isAuthenticated {
                    self.status = .signedIn(name: GKLocalPlayer.local.displayName)
                    // Register once, here, for the lifetime of the process.
                    // Invitations arrive whether or not a game is open, so the
                    // thing that receives them cannot be owned by a game.
                    if !self.hasRegisteredListener {
                        self.hasRegisteredListener = true
                        GKLocalPlayer.local.register(self)
                    }
                    await self.refreshMatchCounts()
                } else {
                    // A declined or failed sign-in is not an error state worth
                    // shouting about — online is simply unavailable, and the rest
                    // of the game works perfectly without it.
                    self.status = .unavailable(
                        reason: error?.localizedDescription
                            ?? "Sign in to Game Center in Settings to play online."
                    )
                }
            }
        }
    }

    /// Online play needs a signed-in player. Everything else in the app works
    /// without one, which is why this is a soft check rather than a gate at
    /// launch.
    var canPlayOnline: Bool { status.isSignedIn }

    var localPlayerName: String {
        if case .signedIn(let name) = status { return name }
        return "You"
    }

    /// Ask GameKit what's outstanding, so the menu can offer "your matches" with
    /// a number on it rather than a button that might open an empty list.
    func refreshMatchCounts() async {
        guard GKLocalPlayer.local.isAuthenticated else {
            matchesAwaitingYou = 0
            totalMatches = 0
            return
        }
        let matches = (try? await GKTurnBasedMatch.loadMatches()) ?? []
        totalMatches = matches.count
        matchesAwaitingYou = matches.filter { match in
            match.status == .open
                && match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        }.count
    }

    /// Open a specific match — used by the "your matches" list.
    func open(_ match: GKTurnBasedMatch) {
        matchToOpen = match
    }
}

// MARK: - Listener

extension GameCenterSession: GKLocalPlayerListener {

    /// Every route into a match funnels through here: an invitation accepted, a
    /// notification tapped, a row chosen in the matchmaker, or an opponent
    /// ending their turn.
    nonisolated func player(
        _ player: GKPlayer,
        receivedTurnEventFor match: GKTurnBasedMatch,
        didBecomeActive: Bool
    ) {
        // GameKit calls listeners on an arbitrary queue.
        Task { @MainActor in
            await self.refreshMatchCounts()

            // A turn in the match already on screen is that table's business.
            if let observer = self.activeObserver, observer.observedMatchID == match.matchID {
                observer.matchDidUpdate(match)
                return
            }
            // `didBecomeActive` means the player asked for this match — they
            // tapped it, or accepted an invitation. Anything else is a
            // background update, which should not yank them out of what they're
            // doing.
            if didBecomeActive {
                self.matchToOpen = match
            }
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        Task { @MainActor in
            await self.refreshMatchCounts()
            if let observer = self.activeObserver, observer.observedMatchID == match.matchID {
                observer.matchDidEnd(match)
            }
        }
    }

    nonisolated func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        Task { @MainActor in
            if let observer = self.activeObserver, observer.observedMatchID == match.matchID {
                observer.playerWantsToQuit(player.gamePlayerID)
            }
        }
    }

    /// An invitation to a *realtime* match. We don't play those, but the method
    /// is part of the protocol and silence here reads as a bug when testing.
    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        Task { @MainActor in await self.refreshMatchCounts() }
    }
}
