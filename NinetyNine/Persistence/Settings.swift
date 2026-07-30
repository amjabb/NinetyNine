//
//  Settings.swift
//  Player preferences, persisted to UserDefaults.
//

import SwiftUI

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @AppStorage("settings.sound") var soundEnabled: Bool = true {
        didSet { SoundEngine.shared.isEnabled = soundEnabled }
    }
    @AppStorage("settings.haptics") var hapticsEnabled: Bool = true {
        didSet { Haptics.shared.isEnabled = hapticsEnabled }
    }
    @AppStorage("settings.difficulty") var difficulty: Difficulty = .sharp
    @AppStorage("settings.opponents") var opponentCount: Int = 2
    @AppStorage("settings.handSize") var handSize: Int = 6
    @AppStorage("settings.playerName") var playerName: String = "You"
    /// Shows the running "why is this illegal" coaching on dead cards.
    @AppStorage("settings.coaching") var coachingEnabled: Bool = true
    @AppStorage("settings.hasSeenTutorial") var hasSeenTutorial: Bool = false
    /// Pass-and-play seat count, kept separate from the solo opponent count so
    /// switching modes doesn't clobber the other's setup.
    @AppStorage("settings.localPlayers") var localPlayerCount: Int = 3
    /// Comma-separated names for pass-and-play seats.
    @AppStorage("settings.localNames") private var localNamesRaw: String = ""

    /// Raw entered names, padded to the seat count. Entries may be empty — the
    /// field shows "Player 3" as a *placeholder*, not as literal text the player
    /// has to select and delete before typing their own name.
    var localPlayerNames: [String] {
        get {
            let stored = localNamesRaw.components(separatedBy: "\u{1}")
            return (0..<localPlayerCount).map { index in
                index < stored.count ? stored[index] : ""
            }
        }
        set { localNamesRaw = newValue.joined(separator: "\u{1}") }
    }

    /// Names to actually deal with, with defaults filled in for blank seats.
    var resolvedLocalPlayerNames: [String] {
        localPlayerNames.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        }
    }

    /// Hand-size ceiling for the pass-and-play table.
    func validLocalHandSize() -> Int {
        let maximum = Rules.maxHandSize(forPlayerCount: localPlayerCount)
        return min(max(handSize, Rules.minHandSize), maximum)
    }

    private init() {
        SoundEngine.shared.isEnabled = soundEnabled
        Haptics.shared.isEnabled = hapticsEnabled
    }

    /// Clamp the stored hand size into the range the current table allows —
    /// switching from 2 opponents to 5 can invalidate a previously fine choice.
    func validHandSize() -> Int {
        let players = opponentCount + 1
        let maximum = Rules.maxHandSize(forPlayerCount: players)
        return min(max(handSize, Rules.minHandSize), maximum)
    }
}
