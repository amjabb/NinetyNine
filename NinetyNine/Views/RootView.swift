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
import GameKit

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var route: Route = .home
    /// Bumped on every new game so SwiftUI tears down and rebuilds the table
    /// rather than trying to reuse a finished one.
    @State private var gameSeed = 0
    /// Built once per game in `startGame()`. Constructing this inside the view
    /// builder would deal a brand-new game on every body evaluation.
    @State private var activeGame: GameViewModel?
    /// The deal size chosen on the setup screen, held while Apple's matchmaker
    /// is up — the match comes back through a listener, not a return value.
    @State private var pendingOnlineDeal: Int?
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
        var cardsDealt: Int
    }

    private enum Route: Equatable {
        case home
        case setup
        /// Choosing the deal for a match nobody has been invited to yet.
        case onlineSetup
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
        // Any route into a match — an invitation, a push, a row in the
        // matchmaker — lands here. Watched at the root because an invitation can
        // arrive while the player is on the home screen or mid-solo-game, not
        // only while they happen to be looking at the online tab.
        .onReceive(GameCenterSession.shared.$matchToOpen.compactMap { $0 }) { match in
            openOnlineMatch(match)
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
                onBack: { go(.home) },
                onNewOnlineMatch: { go(.onlineSetup) },
                onOpenOnlineMatches: { presentMatchmaker() }
            )
            .id("setup")

        case .onlineSetup:
            OnlineMatchSetupView(
                onFindPlayers: { startOnlineGame(cardsDealt: Settings.shared.cardsDealt) },
                onBack: { go(.setup) }
            )
            .id("online-setup")

        case .nextDeal:
            if let plan = nextDeal {
                NextDealView(
                    dealerName: plan.dealerName,
                    isDealerHuman: plan.isDealerHuman,
                    playerCount: plan.playerCount,
                    cardsDealt: Binding(
                        get: { nextDeal?.cardsDealt ?? plan.cardsDealt },
                        set: { nextDeal?.cardsDealt = $0 }
                    ),
                    onDeal: { startGame(dealerID: plan.dealerID, cardsDealt: nextDeal?.cardsDealt) },
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
                onExit: { leaveGame(viewModel) },
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
        let maxHand = Rules.maxCardsDealt(forPlayerCount: playerCount)

        guard let dealer = viewModel.nextDealer else {
            startGame()
            return
        }
        let isHuman = dealer.kind.isLocalHuman
        let chosen: Int
        if let difficulty = dealer.kind.difficulty {
            chosen = AIPlayer(difficulty: difficulty).preferredDeal(maxCardsDealt: maxHand)
        } else {
            chosen = min(max(Settings.shared.cardsDealt, Rules.minCardsDealt), maxHand)
        }

        nextDeal = NextDealPlan(
            dealerID: dealer.id,
            dealerName: isHuman ? dealer.name : dealer.name,
            isDealerHuman: isHuman,
            playerCount: playerCount,
            cardsDealt: chosen
        )
        go(.nextDeal)
    }

    private func startGame(dealerID: String? = nil, cardsDealt overrideDeal: Int? = nil) {
        let settings = Settings.shared

        // Validate the deal *before* routing, so a bad configuration surfaces as
        // an explanation on the setup screen instead of a broken table.
        let playerCount = mode == .solo ? settings.opponentCount + 1 : settings.localPlayerCount
        let cardsDealt = min(
            max(overrideDeal ?? settings.cardsDealt, Rules.minCardsDealt),
            Rules.maxCardsDealt(forPlayerCount: playerCount)
        )
        guard GameViewModel.canDeal(playerCount: playerCount, cardsDealt: cardsDealt) else {
            setupFailure = "That table needs more cards than a 52-card deck has. Try fewer players or a smaller hand."
            return
        }

        switch mode {
        case .solo:
            activeGame = .solo(
                difficulty: settings.difficulty,
                opponentCount: settings.opponentCount,
                cardsDealt: cardsDealt,
                playerName: settings.playerName,
                dealerID: dealerID,
                seed: UITestSeed.value
            )
        case .passAndPlay:
            activeGame = .passAndPlay(
                playerNames: settings.resolvedLocalPlayerNames,
                cardsDealt: cardsDealt,
                dealerID: dealerID,
                autoAssignWells: settings.autoAssignWells
            )
        case .online:
            startOnlineGame(cardsDealt: cardsDealt)
            return
        }
        // Remember the dealer's choice so the next setup screen opens on it.
        settings.cardsDealt = cardsDealt
        gameSeed += 1
        go(.game)
    }

    /// Online play goes through Game Center's own matchmaking UI, so this is
    /// async and can fail in ways the other modes can't — declined sign-in, a
    /// cancelled matchmaker, no network. Each surfaces as an explanation rather
    /// than a dead button.
    private func startOnlineGame(cardsDealt: Int) {
        guard GameCenterSession.shared.canPlayOnline else {
            setupFailure = "Sign in to Game Center to play online. You can still play solo or pass-and-play."
            return
        }
        do {
            // Present the matchmaker and stop. The chosen match — new or
            // existing — arrives at the session's listener, and `matchToOpen`
            // below takes the app into it. Awaiting a match here is what broke:
            // the callback that would have delivered it was deprecated in iOS 9.
            try GameKitTransport.presentMatchmaker(
                minPlayers: 2,
                maxPlayers: Settings.shared.onlinePlayerCount
            )
            pendingOnlineDeal = cardsDealt
        } catch let error as MatchError {
            setupFailure = error.errorDescription ?? "Couldn't open Game Center."
        } catch {
            setupFailure = error.localizedDescription
        }
    }

    /// Leaving a table.
    ///
    /// Online this is *not* a forfeit — a turn-based match waits, so stepping
    /// out has to put you back among your games rather than at the main menu.
    /// There was no route back at all before: the only way out of a match was a
    /// button marked "SDQ", which reads as conceding whether or not it does.
    private func leaveGame(_ viewModel: GameViewModel) {
        activeGame = nil
        if viewModel.mode == .online {
            mode = .online
            go(.setup)
            presentMatchmaker()
        } else {
            go(.home)
        }
    }

    /// Show Game Center's list of the player's matches.
    private func presentMatchmaker() {
        guard GameCenterSession.shared.canPlayOnline else {
            setupFailure = "Sign in to Game Center to play online. You can still play solo or pass-and-play."
            return
        }
        do {
            try GameKitTransport.presentMatchmaker(
                minPlayers: 2,
                maxPlayers: Settings.shared.onlinePlayerCount
            )
        } catch let error as MatchError {
            setupFailure = error.errorDescription ?? "Couldn't open Game Center."
        } catch {
            setupFailure = error.localizedDescription
        }
    }

    /// Take the app into a match the system handed us.
    private func openOnlineMatch(_ match: GKTurnBasedMatch) {
        GameKitTransport.dismissMatchmaker()
        GameCenterSession.shared.matchToOpen = nil

        let transport = GameKitTransport(
            match: match,
            cardsDealt: pendingOnlineDeal ?? Settings.shared.cardsDealt,
            autoAssignWells: Settings.shared.onlineAutoAssignWells
        )
        pendingOnlineDeal = nil
        activeGame = .online(transport: transport)
        gameSeed += 1
        go(.game)
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
