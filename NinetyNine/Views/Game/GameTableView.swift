//
//  GameTableView.swift
//  The table. Everything the player looks at while a game is running.
//
//  Layout is a vertical stack rather than a literal round table: opponents along
//  the top, the gauge and piles in the middle, the player's fan at the bottom.
//  A real circular seating arrangement looks charming in a mock-up and wastes
//  most of a phone screen — this keeps the gauge and the hand, the two things
//  actually being read, as large as possible.
//

import SwiftUI

struct GameTableView: View {
    @StateObject private var viewModel: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onExit: () -> Void
    let onRematch: () -> Void

    @State private var showsPauseMenu = false

    init(viewModel: GameViewModel, onExit: @escaping () -> Void, onRematch: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onExit = onExit
        self.onRematch = onRematch
    }

    var body: some View {
        ZStack {
            TableBackground(
                lockedSuit: viewModel.state.suitLock?.suit,
                pressure: viewModel.state.pressure
            )

            VStack(spacing: 0) {
                topBar
                opponentRow
                Spacer(minLength: 8)
                centrePiece
                Spacer(minLength: 8)
                statusRow
                actionBar
                handArea
            }
            .padding(.horizontal, 14)

            overlays
        }
        .environment(\.motion, MotionBudget(reduceMotion: reduceMotion))
        .task { await viewModel.begin() }
        .statusBarHidden(false)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                Haptics.shared.play(.select)
                showsPauseMenu = true
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ivory)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .overlay(Circle().strokeBorder(Palette.brassDeep.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause")

            Spacer()

            // Deck and discard counts — needed to judge whether a reshuffle is
            // coming, which changes how safe hoarding is.
            HStack(spacing: 14) {
                pileCounter(icon: "rectangle.stack.fill", value: viewModel.state.drawPile.count, label: "Deck")
                pileCounter(icon: "square.3.layers.3d.down.right", value: viewModel.state.discardPile.count, label: "Pile")
            }

            Spacer()

            DirectionBadge(isClockwise: viewModel.state.direction == 1)
        }
        .padding(.top, 2)
        .frame(height: 44)
    }

    private func pileCounter(icon: String, value: Int, label: String) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text("\(value)")
                    .font(Typography.counter(13, weight: .bold))
            }
            .foregroundStyle(Palette.ivory.opacity(0.9))
            Text(label).labelStyle(Palette.ivoryFaint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value) cards")
    }

    // MARK: - Opponents

    private var opponentRow: some View {
        HStack(alignment: .top, spacing: viewModel.opponents.count > 3 ? 6 : 16) {
            ForEach(viewModel.opponents) { opponent in
                OpponentSeatView(
                    player: opponent,
                    isCurrent: viewModel.state.currentPlayer.id == opponent.id,
                    isThinking: viewModel.thinkingPlayerID == opponent.id,
                    isCompact: viewModel.opponents.count > 3
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Centre

    private var centrePiece: some View {
        ZStack {
            TallyGauge(
                tally: viewModel.state.tally,
                suitLock: viewModel.state.suitLock?.suit,
                isForcedNegative: viewModel.state.forcedNegativeNext,
                isClockwise: viewModel.state.direction == 1,
                isSlamming: viewModel.isSlamming
            )
            .frame(height: 248)

            // The active discard sits to the side of the gauge, angled, so the
            // last card played is always visible without covering the number.
            if let top = viewModel.state.topOfDiscard {
                CardFaceView(card: top)
                    .frame(width: 62)
                    .rotationEffect(.degrees(-7))
                    .cardShadow(lift: 4)
                    .offset(x: 128, y: 62)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .id(top.id)
                    .accessibilityLabel("Top of the discard pile, \(top.accessibleName)")
            }

            // Floating delta chip.
            if let delta = viewModel.tallyDelta {
                TallyDeltaChip(delta: delta)
                    .offset(y: -128)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal: .offset(y: -26).combined(with: .opacity)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action bar

    /// Only shows what's actually available. An always-visible row of disabled
    /// buttons teaches the player nothing; a row that appears exactly when the
    /// well becomes legal teaches them the rule.
    @ViewBuilder
    private var actionBar: some View {
        let options = viewModel.options
        let showsStuck = viewModel.isHumanTurn && !options.canPlayFromHand
        let snackooRanks = viewModel.snackooRanks

        VStack(spacing: 8) {
            if viewModel.isHumanTurn && viewModel.state.playsRemainingThisTurn > 1 {
                DebtBanner(playsOwed: viewModel.state.playsRemainingThisTurn)
            }

            HStack(spacing: 8) {
                if !snackooRanks.isEmpty || viewModel.canSnackooPoison {
                    if viewModel.canSnackooPoison {
                        ActionButton(
                            title: "Snackoo",
                            subtitle: "3 poisoned queens",
                            tint: Palette.poison,
                            icon: "sparkles"
                        ) {
                            viewModel.declareSnackoo(.threeQueens)
                        }
                    }
                    if let rank = snackooRanks.first {
                        ActionButton(
                            title: "Snackoo",
                            subtitle: "three \(rank.displayName)s",
                            tint: Palette.brass,
                            icon: "sparkles"
                        ) {
                            viewModel.declareSnackoo(.threeOfAKind(rank))
                        }
                    }
                }

                if showsStuck && options.canUseWell {
                    ActionButton(
                        title: "The Well",
                        subtitle: "\(viewModel.human.well.count) left · risky",
                        tint: Palette.danger,
                        icon: "arrow.down.circle.fill"
                    ) {
                        viewModel.useWell()
                    }
                }

                if showsStuck && options.canSkip {
                    ActionButton(
                        title: "Skip",
                        subtitle: "owe 2 next turn",
                        tint: Palette.ivoryFaint,
                        icon: "forward.fill"
                    ) {
                        viewModel.skipTurn()
                    }
                }

                if showsStuck && options.isStranded {
                    ActionButton(
                        title: "No outs",
                        subtitle: "concede the seat",
                        tint: Palette.danger,
                        icon: "xmark.circle.fill"
                    ) {
                        viewModel.concede()
                    }
                }
            }
        }
        .animation(Motion.panel, value: viewModel.isHumanTurn)
        .animation(Motion.panel, value: viewModel.state.playsRemainingThisTurn)
        .padding(.bottom, 6)
    }

    // MARK: - Hand

    /// Turn state and the player's own well/poison/cap, above the fan. These used
    /// to sit *below* the fan, where the bottom of the cards covered them.
    private var statusRow: some View {
        VStack(spacing: 5) {
            turnIndicator
            HStack(spacing: 12) {
                WellPips(remaining: viewModel.human.well.count)
                if !viewModel.human.poisonPile.isEmpty {
                    PoisonBadge(count: viewModel.human.poisonPile.count)
                }
                Text("cap \(viewModel.human.handCap)")
                    .labelStyle()
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Hand

    private var handArea: some View {
        VStack(spacing: 0) {
            HandFanView(
                cards: viewModel.human.hand,
                playableIDs: viewModel.playableCardIDs,
                suppressedCardID: viewModel.pendingChoice.map { $0.card.id },
                rejectedCardID: viewModel.rejection?.cardID,
                isInteractive: viewModel.isHumanTurn && !viewModel.isDealing,
                isDealing: viewModel.isDealing
            ) { card in
                viewModel.tapCard(card)
            }
            .frame(height: 178)
        }
        .padding(.bottom, 2)
    }

    private var turnIndicator: some View {
        Group {
            if viewModel.state.isOver {
                EmptyView()
            } else if viewModel.isHumanTurn {
                Text(viewModel.options.canPlayFromHand ? "Your move" : "No legal card")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(viewModel.options.canPlayFromHand ? Palette.brassLight : Palette.danger)
                    .transition(.opacity)
            } else {
                Text("\(viewModel.state.currentPlayer.name) is thinking…")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ivoryDim)
                    .transition(.opacity)
            }
        }
        .frame(height: 24)
        .animation(Motion.panel, value: viewModel.isHumanTurn)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlays: some View {
        // Announcement banner.
        if let announcement = viewModel.announcement {
            AnnouncementBanner(announcement: announcement)
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .top)
                // Clear of the opponent row, which ends around 210pt — the banner
                // used to sit on top of their names.
                .padding(.top, 218)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }

        // Why-is-this-illegal coaching.
        if let rejection = viewModel.rejection, Settings.shared.coachingEnabled {
            CoachingToast(message: rejection.message)
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 210)
                .transition(.opacity.combined(with: .offset(y: 10)))
                .allowsHitTesting(false)
        }

        if let achievement = viewModel.achievementToast {
            AchievementToast(achievement: achievement)
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 218)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }

        if viewModel.wellReveal != .idle {
            WellRevealOverlay(
                phase: viewModel.wellReveal,
                playerName: wellPlayerName,
                isHuman: wellIsHuman
            )
        }

        if let choice = viewModel.pendingChoice {
            DeclarationSheet(
                choice: choice,
                currentTally: viewModel.state.tally,
                projected: { viewModel.projectedTally(for: choice.card, declaration: $0) },
                onChoose: { viewModel.chooseDeclaration($0) },
                onCancel: { viewModel.cancelChoice() }
            )
        }

        if let outcome = viewModel.outcome {
            GameOverView(
                outcome: outcome,
                state: viewModel.state,
                humanID: viewModel.humanID,
                onRematch: onRematch,
                onExit: onExit
            )
        }

        if showsPauseMenu {
            PauseMenu(
                onResume: { showsPauseMenu = false },
                onQuit: onExit
            )
        }
    }

    private var wellPlayerName: String {
        switch viewModel.wellReveal {
        case .rolling(let id), .revealed(_, _, let id):
            return viewModel.state.player(id: id)?.name ?? ""
        case .idle:
            return ""
        }
    }

    private var wellIsHuman: Bool {
        switch viewModel.wellReveal {
        case .rolling(let id), .revealed(_, _, let id):
            return id == viewModel.humanID
        case .idle:
            return false
        }
    }
}

// MARK: - Small components

private struct DirectionBadge: View {
    let isClockwise: Bool

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: isClockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.brassLight)
            Text(isClockwise ? "CW" : "CCW").labelStyle(Palette.ivoryFaint)
        }
        .frame(width: 40)
        .contentTransition(.symbolEffect(.replace))
        .animation(Motion.panel, value: isClockwise)
        .accessibilityLabel(isClockwise ? "Play is clockwise" : "Play is counter-clockwise")
    }
}

private struct WellPips: View {
    let remaining: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("Well").labelStyle()
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index < remaining
                            ? AnyShapeStyle(Palette.brassFace)
                            : AnyShapeStyle(Palette.ivoryFaint.opacity(0.25)))
                        .frame(width: 16, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Well: \(remaining) of 2 cards remaining")
    }
}

private struct PoisonBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "drop.fill").font(.system(size: 9, weight: .bold))
            Text("\(count)").font(Typography.counter(11, weight: .bold))
        }
        .foregroundStyle(Palette.poison)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.poison.opacity(0.18)))
        .accessibilityLabel("\(count) poisoned queens")
    }
}

private struct DebtBanner: View {
    let playsOwed: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
            Text("\(playsOwed) plays owed this turn")
                .font(Typography.caption)
        }
        .foregroundStyle(Palette.caution)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.caution.opacity(0.16)))
        .overlay(Capsule().strokeBorder(Palette.caution.opacity(0.45), lineWidth: 1))
    }
}

private struct ActionButton: View {
    let title: String
    let subtitle: String
    let tint: Color
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 14, weight: .bold))
                    Text(subtitle).font(.system(size: 9, weight: .medium)).opacity(0.75)
                }
            }
            .foregroundStyle(Palette.ivory)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(tint.opacity(0.75), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

// MARK: - Banners

struct AnnouncementBanner: View {
    let announcement: GameViewModel.Announcement

    private var tint: Color {
        switch announcement.tone {
        case .neutral: return Palette.brassMid
        case .good: return Palette.safe
        case .bad: return Palette.danger
        case .danger: return Palette.dangerGlow
        case .poison: return Palette.poison
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(announcement.headline)
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundStyle(Palette.ivory)
            if let detail = announcement.detail {
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ivory.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.feltEdge.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.8), lineWidth: 1.5)
        )
        .shadow(color: tint.opacity(0.35), radius: 16)
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}

struct CoachingToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.caution)
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(Palette.ivory)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.caution.opacity(0.5), lineWidth: 1)
        )
        // Announced rather than silent: a player who taps a dead card should hear
        // why, not just feel a bump.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coaching-toast")
        .accessibilityLabel(message)
    }
}

struct AchievementToast: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: achievement.glyph)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Palette.brassFace)
            VStack(alignment: .leading, spacing: 1) {
                Text("Unlocked").labelStyle(Palette.brassMid)
                Text(achievement.title)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.ivory)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.feltEdge.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.brassDeep, lineWidth: 1.5)
        )
        .shadow(color: Palette.brass.opacity(0.4), radius: 14)
    }
}

// MARK: - Pause

struct PauseMenu: View {
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
                .onTapGesture(perform: onResume)

            VStack(spacing: 14) {
                Text("Paused")
                    .font(Typography.title)
                    .foregroundStyle(Palette.ivory)

                BrassButton(title: "Resume", isProminent: true, action: onResume)
                BrassButton(title: "Quit to menu", isProminent: false, action: onQuit)
            }
            .padding(26)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Palette.feltEdge.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Palette.brassDeep, lineWidth: 1)
            )
        }
        .transition(.opacity)
    }
}
