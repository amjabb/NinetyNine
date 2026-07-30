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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
