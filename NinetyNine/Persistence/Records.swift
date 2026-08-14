//
//  Records.swift
//  Lifetime stats and achievements.
//
//  Stored as one JSON blob in UserDefaults. This is a few hundred bytes of
//  purely local data with no sync requirement, so anything heavier than this
//  would be overkill — and keeping it local means the app needs no account, no
//  network permission, and no privacy disclosure beyond "we store nothing".
//

import SwiftUI

// MARK: - Stats

struct Stats: Codable, Equatable {
    var gamesPlayed = 0
    var gamesWon = 0
    var currentStreak = 0
    var bestStreak = 0

    /// Fun counters that give the achievements something to hang off.
    var ninesPlayed = 0
    var hundredsReached = 0
    var wellsSurvived = 0
    var wellsFatal = 0
    var snackoosDeclared = 0
    var suitsLocked = 0
    var queensPoisoned = 0
    var opponentsEliminated = 0
    var tightestSurvival = 99   // lowest headroom the player ever played through
    var deepestNegative = 0     // most negative tally the player ever created

    var winRate: Double {
        gamesPlayed == 0 ? 0 : Double(gamesWon) / Double(gamesPlayed)
    }
}

// MARK: - Achievements

enum Achievement: String, Codable, CaseIterable, Identifiable {
    case firstWin
    case slammer
    case centurion
    case wellWalker
    case snackooArtist
    case lockSmith
    case belowZero
    case hatTrick
    case ruthlessVictor
    case cleanSweep
    case survivor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstWin: return "Last One Standing"
        case .slammer: return "Slammer"
        case .centurion: return "Centurion"
        case .wellWalker: return "Well Walker"
        case .snackooArtist: return "Snackoo!"
        case .lockSmith: return "Locksmith"
        case .belowZero: return "Below Zero"
        case .hatTrick: return "Hat Trick"
        case .ruthlessVictor: return "No Mercy"
        case .cleanSweep: return "Clean Sweep"
        case .survivor: return "One To Spare"
        }
    }

    var detail: String {
        switch self {
        case .firstWin: return "Win your first game."
        case .slammer: return "Slam the tally to 99 with a nine, 10 times."
        case .centurion: return "Ride the matching Ace all the way to 100."
        case .wellWalker: return "Survive the well 5 times."
        case .snackooArtist: return "Declare Snackoo 10 times."
        case .lockSmith: return "Lock the suit 25 times."
        case .belowZero: return "Push the tally to −30 or lower."
        case .hatTrick: return "Win three games in a row."
        case .ruthlessVictor: return "Win a game against Ruthless opponents."
        case .cleanSweep: return "Win a five-handed game."
        case .survivor: return "Play a card with only one point of headroom left."
        }
    }

    var glyph: String {
        switch self {
        case .firstWin: return "crown.fill"
        case .slammer: return "bolt.fill"
        case .centurion: return "flame.fill"
        case .wellWalker: return "arrow.down.circle.fill"
        case .snackooArtist: return "sparkles"
        case .lockSmith: return "lock.fill"
        case .belowZero: return "thermometer.snowflake"
        case .hatTrick: return "flame.circle.fill"
        case .ruthlessVictor: return "shield.lefthalf.filled"
        case .cleanSweep: return "person.3.fill"
        case .survivor: return "heart.fill"
        }
    }

    /// Progress toward this achievement, for the ones that count.
    func target() -> Int? {
        switch self {
        case .slammer: return 10
        case .wellWalker: return 5
        case .snackooArtist: return 10
        case .lockSmith: return 25
        default: return nil
        }
    }

    func progress(in stats: Stats) -> Int {
        switch self {
        case .slammer: return stats.ninesPlayed
        case .wellWalker: return stats.wellsSurvived
        case .snackooArtist: return stats.snackoosDeclared
        case .lockSmith: return stats.suitsLocked
        default: return 0
        }
    }
}

// MARK: - Store

@MainActor
final class Records: ObservableObject {
    static let shared = Records()

    @Published private(set) var stats = Stats()
    @Published private(set) var unlocked: Set<Achievement> = []
    /// Achievements unlocked since the last time the UI drained this — lets the
    /// game screen present them as toasts at a natural moment.
    @Published var pendingToasts: [Achievement] = []

    private let statsKey = "records.stats.v1"
    private let unlockedKey = "records.unlocked.v1"

    private init() { load() }

    // MARK: Persistence

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: statsKey),
           let decoded = try? JSONDecoder().decode(Stats.self, from: data) {
            stats = decoded
        }
        if let data = defaults.data(forKey: unlockedKey),
           let decoded = try? JSONDecoder().decode([Achievement].self, from: data) {
            unlocked = Set(decoded)
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: statsKey)
        }
        if let data = try? JSONEncoder().encode(Array(unlocked)) {
            defaults.set(data, forKey: unlockedKey)
        }
    }

    // MARK: Recording

    /// Fold a batch of engine events into the lifetime record. Only the human
    /// player's own actions count toward stats — an AI slamming a 9 isn't the
    /// player's achievement.
    func record(events: [GameEvent], humanID: String, state: GameState) {
        for event in events {
            switch event {
            case .cardPlayed(_, let by, let effect) where by == humanID:
                if effect.isNine { stats.ninesPlayed += 1 }
                let headroom = 99 - effect.newTally
                if effect.newTally >= 0 {
                    stats.tightestSurvival = min(stats.tightestSurvival, headroom)
                }
                if effect.newTally < stats.deepestNegative {
                    stats.deepestNegative = effect.newTally
                }
            case .hundredReached:
                if state.discardPile.last != nil { stats.hundredsReached += 1 }
            case .suitLocked(_, let by) where by == humanID:
                stats.suitsLocked += 1
            case .snackoo(let by, _, _) where by == humanID:
                stats.snackoosDeclared += 1
            case .wellRevealed(_, let by, let playable) where by == humanID:
                if playable { stats.wellsSurvived += 1 } else { stats.wellsFatal += 1 }
            case .queenPoisoned(_, let owner, _) where owner == humanID:
                stats.queensPoisoned += 1
            case .playerEliminated(let id, _, _, _, _) where id != humanID:
                stats.opponentsEliminated += 1
            default:
                break
            }
        }
        evaluateAchievements(state: state, humanID: humanID)
        save()
    }

    /// Called once when a game ends.
    func recordGameEnd(won: Bool, state: GameState, humanID: String, difficulty: Difficulty) {
        stats.gamesPlayed += 1
        if won {
            stats.gamesWon += 1
            stats.currentStreak += 1
            stats.bestStreak = max(stats.bestStreak, stats.currentStreak)
            if difficulty == .ruthless { unlock(.ruthlessVictor) }
            if state.players.count >= 5 { unlock(.cleanSweep) }
            unlock(.firstWin)
            if stats.currentStreak >= 3 { unlock(.hatTrick) }
        } else {
            stats.currentStreak = 0
        }
        evaluateAchievements(state: state, humanID: humanID)
        save()
    }

    private func evaluateAchievements(state: GameState, humanID: String) {
        if stats.ninesPlayed >= 10 { unlock(.slammer) }
        if stats.hundredsReached >= 1 { unlock(.centurion) }
        if stats.wellsSurvived >= 5 { unlock(.wellWalker) }
        if stats.snackoosDeclared >= 10 { unlock(.snackooArtist) }
        if stats.suitsLocked >= 25 { unlock(.lockSmith) }
        if stats.deepestNegative <= -30 { unlock(.belowZero) }
        if stats.tightestSurvival <= 1 { unlock(.survivor) }
    }

    private func unlock(_ achievement: Achievement) {
        guard !unlocked.contains(achievement) else { return }
        unlocked.insert(achievement)
        pendingToasts.append(achievement)
    }

    func drainToast() -> Achievement? {
        pendingToasts.isEmpty ? nil : pendingToasts.removeFirst()
    }

    /// Exposed for the settings screen's "reset progress" action.
    func resetAll() {
        stats = Stats()
        unlocked = []
        pendingToasts = []
        save()
    }

    /// Seeds a plausible history for App Store capture runs. Guarded by a launch
    /// argument at the call site, so it can never run in a shipped build.
    func seedShowcase() {
        stats = Stats(
            gamesPlayed: 47,
            gamesWon: 26,
            currentStreak: 3,
            bestStreak: 6,
            ninesPlayed: 31,
            hundredsReached: 2,
            wellsSurvived: 9,
            wellsFatal: 12,
            snackoosDeclared: 14,
            suitsLocked: 38,
            queensPoisoned: 7,
            opponentsEliminated: 61,
            tightestSurvival: 1,
            deepestNegative: -34
        )
        unlocked = [
            .firstWin, .slammer, .wellWalker, .snackooArtist,
            .lockSmith, .belowZero, .hatTrick, .survivor,
        ]
        pendingToasts = []
        save()
    }
}
