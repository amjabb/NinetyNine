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
    @State private var mode: SetupView.GameMode = .solo
    /// Set when a game ends, carrying who deals next and what they've chosen.
    @State private var nextDeal: NextDealPlan?

    /// Who deals the next game, and what they picked.
    private struct NextDealPlan: Equatable {
        var dealerID: String
        var dealerName: String
        var isDealerHuman: Bool
        var playerCount: Int
        var handSize: Int
    }

    private enum Route: Equatable {
        case home
        case setup
        /// Between games: the first player out chooses the next deal size.
        case nextDeal
        case game
        case rules
        case record
        case settings

        /// Screens that sit "above" home, and so slide in from the trailing edge.
        var isForward: Bool { self != .home }
    }



    var body: some View {
        ZStack {
            // Base layer so the felt never flashes between screens.
            TableBackground(pressure: 0)

            content
                .transition(transition(for: route))
        }
        .environment(\.motion, MotionBudget(reduceMotion: reduceMotion))
        .onAppear {
            SoundEngine.shared.warmUp()
            // Authenticate early and quietly. If it fails, nothing breaks —
            // online is simply reported as unavailable when the player looks.
            GameCenterSession.shared.authenticateIfNeeded()
        }
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
                mode: $mode,
                onStart: { startGame() },
                onBack: { go(.home) }
            )
            .id("setup")

        case .nextDeal:
            if let plan = nextDeal {
                NextDealView(
                    dealerName: plan.dealerName,
                    isDealerHuman: plan.isDealerHuman,
                    playerCount: plan.playerCount,
                    handSize: Binding(
                        get: { nextDeal?.handSize ?? plan.handSize },
                        set: { nextDeal?.handSize = $0 }
                    ),
                    onDeal: { startGame(dealerID: plan.dealerID, handSize: nextDeal?.handSize) },
                    onCancel: { go(.home) }
                )
                .id("nextdeal")
            }

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
                onRematch: { planNextDeal(after: viewModel) }
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

    /// A game just ended: work out who deals next and what they'd choose, then
    /// show them the prompt instead of silently re-dealing the previous setup.
    private func planNextDeal(after viewModel: GameViewModel) {
        let playerCount = viewModel.participants.count
        let maxHand = Rules.maxHandSize(forPlayerCount: playerCount)

        guard let dealer = viewModel.nextDealer else {
            startGame()
            return
        }
        let isHuman = dealer.kind.isLocalHuman
        let chosen: Int
        if let difficulty = dealer.kind.difficulty {
            chosen = AIPlayer(difficulty: difficulty).preferredHandSize(maxHandSize: maxHand)
        } else {
            chosen = min(max(Settings.shared.handSize, Rules.minHandSize), maxHand)
        }

        nextDeal = NextDealPlan(
            dealerID: dealer.id,
            dealerName: isHuman ? dealer.name : dealer.name,
            isDealerHuman: isHuman,
            playerCount: playerCount,
            handSize: chosen
        )
        go(.nextDeal)
    }

    private func startGame(dealerID: String? = nil, handSize overrideHandSize: Int? = nil) {
        let settings = Settings.shared

        // Validate the deal *before* routing, so a bad configuration surfaces as
        // an explanation on the setup screen instead of a broken table.
        let playerCount = mode == .solo ? settings.opponentCount + 1 : settings.localPlayerCount
        let handSize = min(
            max(overrideHandSize ?? settings.handSize, Rules.minHandSize),
            Rules.maxHandSize(forPlayerCount: playerCount)
        )
        guard GameViewModel.canDeal(playerCount: playerCount, handSize: handSize) else {
            setupFailure = "That table needs more cards than a 52-card deck has. Try fewer players or a smaller hand."
            return
        }

        switch mode {
        case .solo:
            activeGame = .solo(
                difficulty: settings.difficulty,
                opponentCount: settings.opponentCount,
                handSize: handSize,
                playerName: settings.playerName,
                dealerID: dealerID,
                seed: UITestSeed.value
            )
        case .passAndPlay:
            activeGame = .passAndPlay(
                playerNames: settings.resolvedLocalPlayerNames,
                handSize: handSize,
                dealerID: dealerID
            )
        case .online:
            startOnlineGame(handSize: handSize)
            return
        }
        // Remember the dealer's choice so the next setup screen opens on it.
        settings.handSize = handSize
        gameSeed += 1
        go(.game)
    }

    /// Online play goes through Game Center's own matchmaking UI, so this is
    /// async and can fail in ways the other modes can't — declined sign-in, a
    /// cancelled matchmaker, no network. Each surfaces as an explanation rather
    /// than a dead button.
    private func startOnlineGame(handSize: Int) {
        Task {
            guard GameCenterSession.shared.canPlayOnline else {
                setupFailure = "Sign in to Game Center to play online. You can still play solo or pass-and-play."
                return
            }
            let transport = GameKitTransport()
            do {
                let match = try await transport.findMatch(
                    minPlayers: 2,
                    maxPlayers: min(6, Settings.shared.opponentCount + 1),
                    handSize: handSize
                )
                let online = GameKitTransport(match: match)
                activeGame = .online(transport: online)
                gameSeed += 1
                go(.game)
            } catch let error as MatchError {
                // Cancelling the matchmaker is a choice, not a failure.
                if case .matchmakingFailed("cancelled") = error { return }
                setupFailure = error.errorDescription ?? "Couldn't start an online match."
            } catch {
                setupFailure = error.localizedDescription
            }
        }
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
