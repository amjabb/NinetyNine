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
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            Records.shared.resetAll()
            Settings.shared.opponentCount = 2
            Settings.shared.difficulty = .sharp
            Settings.shared.handSize = 6
            Settings.shared.coachingEnabled = true
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
