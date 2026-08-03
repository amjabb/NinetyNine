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
    /// How many cards the dealer deals — *including* the two each player banks
    /// as their well. Deal 7 and you open with five, playing down to three.
    ///
    /// The storage key deliberately changed with the meaning: the old
    /// "settings.handSize" held a number that counted only the hand, and
    /// silently reusing it would have quietly shrunk everyone's opening hand by
    /// two.
    @AppStorage("settings.cardsDealt") var cardsDealt: Int = 7
    @AppStorage("settings.playerName") var playerName: String = "You"
    /// Shows the running "why is this illegal" coaching on dead cards.
    @AppStorage("settings.coaching") var coachingEnabled: Bool = true
    @AppStorage("settings.hasSeenTutorial") var hasSeenTutorial: Bool = false
    /// Pass-and-play seat count, kept separate from the solo opponent count so
    /// switching modes doesn't clobber the other's setup.
    @AppStorage("settings.localPlayers") var localPlayerCount: Int = 3
    /// Comma-separated names for pass-and-play seats.
    @AppStorage("settings.localNames") private var localNamesRaw: String = ""
    /// Bank everyone's well automatically instead of passing the device around
    /// the table before a card has been played.
    ///
    /// Costs nothing in fairness: the well is chosen face down, so a player
    /// picking positions is guessing exactly as hard as the app is.
    @AppStorage("settings.autoWell") var autoAssignWells: Bool = false

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
    func validLocalDeal() -> Int {
        let maximum = Rules.maxCardsDealt(forPlayerCount: localPlayerCount)
        return min(max(cardsDealt, Rules.minCardsDealt), maximum)
    }

    private init() {
        SoundEngine.shared.isEnabled = soundEnabled
        Haptics.shared.isEnabled = hapticsEnabled
    }

    /// Clamp the stored hand size into the range the current table allows —
    /// switching from 2 opponents to 5 can invalidate a previously fine choice.
    func validDeal() -> Int {
        let players = opponentCount + 1
        let maximum = Rules.maxCardsDealt(forPlayerCount: players)
        return min(max(cardsDealt, Rules.minCardsDealt), maximum)
    }
}
