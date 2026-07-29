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
