//
//  RootView.swift
//  Screen routing.
//
//  Deliberately not a NavigationStack. The default push transition and the
//  system back chevron are the two most recognisable "this is a stock iOS app"
//  tells, and this is a game — it should feel like one from the first tap. Routes
//  are a plain enum and transitions are authored per direction.
//

import SwiftUI

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var route: Route = .home
    /// Bumped on every new game so SwiftUI tears down and rebuilds the table
    /// rather than trying to reuse a finished one.
    @State private var gameSeed = 0
    /// Built once per game in `startGame()`. Constructing this inside the view
    /// builder would deal a brand-new game on every body evaluation.
    @State private var activeGame: GameViewModel?
    @State private var setupFailure: String?

    private enum Route: Equatable {
        case home
        case setup
        case game
        case rules
        case record
        case settings

        /// Screens that sit "above" home, and so slide in from the trailing edge.
        var isForward: Bool { self != .home }
    }

    struct GameConfiguration: Equatable {
        var difficulty: Difficulty
        var opponentCount: Int
        var handSize: Int
        var playerName: String
    }

    var body: some View {
        ZStack {
            // Base layer so the felt never flashes between screens.
            TableBackground(pressure: 0)

            content
                .transition(transition(for: route))
        }
        .environment(\.motion, MotionBudget(reduceMotion: reduceMotion))
        .onAppear { SoundEngine.shared.warmUp() }
        .alert("Couldn't deal", isPresented: .constant(setupFailure != nil)) {
            Button("OK") { setupFailure = nil }
        } message: {
            Text(setupFailure ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .home:
            HomeView(
                onPlay: { go(.setup) },
                onRules: { go(.rules) },
                onStats: { go(.record) },
                onSettings: { go(.settings) }
            )
            .id("home")

        case .setup:
            SetupView(
                onStart: { startGame() },
                onBack: { go(.home) }
            )
            .id("setup")

        case .game:
            gameScreen
                .id("game-\(gameSeed)")

        case .rules:
            RulebookView(onBack: { go(.home) })
                .id("rules")

        case .record:
            RecordView(onBack: { go(.home) })
                .id("record")

        case .settings:
            SettingsView(onBack: { go(.home) })
                .id("settings")
        }
    }

    @ViewBuilder
    private var gameScreen: some View {
        if let viewModel = activeGame {
            GameTableView(
                viewModel: viewModel,
                onExit: { go(.home) },
                onRematch: { startGame() }
            )
        } else {
            // Should be unreachable: startGame validates before routing here.
            VStack(spacing: 16) {
                Text("Something went wrong dealing that hand.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ivory)
                BrassButton(title: "Back to menu", isProminent: true) { go(.home) }
                    .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Routing

    private func go(_ destination: Route) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.screen) {
            route = destination
        }
    }

    private func startGame() {
        let settings = Settings.shared
        let configuration = GameConfiguration(
            difficulty: settings.difficulty,
            opponentCount: settings.opponentCount,
            handSize: settings.validHandSize(),
            playerName: settings.playerName
        )
        // Build the deal *before* routing, so a bad configuration surfaces as an
        // explanation on the setup screen instead of a broken table.
        guard let viewModel = makeViewModel(configuration) else {
            setupFailure = "That table needs more cards than a 52-card deck has. Try fewer players or a smaller hand."
            return
        }
        activeGame = viewModel
        gameSeed += 1
        go(.game)
    }

    private func makeViewModel(_ configuration: GameConfiguration) -> GameViewModel? {
        try? GameViewModel(
            difficulty: configuration.difficulty,
            opponentCount: configuration.opponentCount,
            handSize: configuration.handSize,
            playerName: configuration.playerName
        )
    }

    // MARK: - Transitions

    /// Forward screens slide up and scale in; going home reverses it. Under
    /// Reduce Motion everything collapses to a cross-fade.
    private func transition(for route: Route) -> AnyTransition {
        if reduceMotion { return .opacity }
        if route == .game {
            // Entering a game is a bigger moment than a navigation push.
            return .asymmetric(
                insertion: .scale(scale: 1.08).combined(with: .opacity),
                removal: .scale(scale: 0.94).combined(with: .opacity)
            )
        }
        return .asymmetric(
            insertion: .offset(y: 26).combined(with: .opacity),
            removal: .offset(y: 18).combined(with: .opacity)
        )
    }
}
