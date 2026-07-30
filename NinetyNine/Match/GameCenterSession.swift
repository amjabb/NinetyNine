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

@MainActor
final class GameCenterSession: ObservableObject {
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

    private var hasStartedAuthentication = false

    private init() {}

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
}
