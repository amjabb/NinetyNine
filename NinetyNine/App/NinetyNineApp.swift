//
//  NinetyNineApp.swift
//

import SwiftUI

@main
struct NinetyNineApp: App {

    init() {
        // UI tests need a known starting table: no saved record, default
        // settings. Guarded on a launch argument so it can never fire in a
        // shipped build.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uitest-reset") {
            Records.shared.resetAll()
            Settings.shared.opponentCount = 2
            Settings.shared.difficulty = .sharp
            Settings.shared.handSize = 6
            Settings.shared.coachingEnabled = true
            Settings.shared.localPlayerCount = 3
            Settings.shared.localPlayerNames = []
        }
        // Store screenshots should show a played-in record rather than a row of
        // zeroes, so the capture run seeds a plausible history.
        if arguments.contains("-uitest-showcase") {
            Records.shared.seedShowcase()
        }
        // A test that needs a particular hand — a pair to run, a queen to draw —
        // can't wait for one to turn up by luck. This pins the shuffle.
        if let index = arguments.firstIndex(of: "-uitest-seed"),
           index + 1 < arguments.count,
           let seed = UInt32(arguments[index + 1]) {
            UITestSeed.value = seed
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// The pinned shuffle seed for UI tests. Nil in every shipped build — nothing
/// sets it but the launch argument above.
enum UITestSeed {
    nonisolated(unsafe) static var value: UInt32?
}
