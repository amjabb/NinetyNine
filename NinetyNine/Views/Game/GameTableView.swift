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
                lockedSuit: viewModel.view?.suitLock?.suit,
                pressure: viewModel.view?.pressure ?? 0
            )

            // The gauge and the fan scale with the height available, so a tall
            // screen gets a bigger gauge rather than more empty felt. Clamped at
            // both ends: the lower bound keeps the gauge readable on a small
            // phone, the upper bound stops it dominating an iPad.
            GeometryReader { geometry in
                let height = geometry.size.height
                let gaugeHeight = min(max(height * 0.30, 196), 340)
                let fanHeight = min(max(height * 0.23, 158), 260)

                VStack(spacing: 0) {
                    topBar
                    opponentRow
                    Spacer(minLength: 8)
                    centrePiece(gaugeHeight: gaugeHeight)
                    Spacer(minLength: 8)
                    statusRow
                    actionBar
                    handArea(fanHeight: fanHeight)
                }
                // Height only — pinning the width here would override the content
                // measure applied below and leave the top bar spanning an iPad.
                .frame(height: height)
                .padding(.horizontal, 14)
                .tableContentWidth()
            }

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
                pileCounter(icon: "rectangle.stack.fill", value: viewModel.view?.drawPileCount ?? 0, label: "Deck")
                pileCounter(icon: "square.3.layers.3d.down.right", value: viewModel.view?.discardPile.count ?? 0, label: "Pile")
            }

            Spacer()

            // The direction used to live here, in the least looked-at corner of
            // the screen. It's inside the gauge now, next to the number people
            // are already reading — this keeps the header balanced.
            Color.clear.frame(width: 40, height: 1)
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
                    isCurrent: viewModel.view?.currentPlayerID == opponent.id,
                    isThinking: viewModel.thinkingPlayerID == opponent.id,
                    isCompact: viewModel.opponents.count > 3
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Centre

    private func centrePiece(gaugeHeight: CGFloat) -> some View {
        ZStack {
            TallyGauge(
                tally: viewModel.view?.tally ?? 0,
                suitLock: viewModel.view?.suitLock?.suit,
                isForcedNegative: viewModel.view?.forcedNegativeNext ?? false,
                isClockwise: (viewModel.view?.direction ?? 1) == 1,
                isSlamming: viewModel.isSlamming
            )
            .frame(height: gaugeHeight)

            // The active discard sits to the side of the gauge, angled, so the
            // last card played is always visible without covering the number.
            if let top = viewModel.view?.topOfDiscard {
                CardFaceView(card: top)
                    .frame(width: gaugeHeight * 0.25)
                    .rotationEffect(.degrees(-7))
                    .cardShadow(lift: 4)
                    .offset(x: gaugeHeight * 0.52, y: gaugeHeight * 0.25)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .id(top.id)
                    .accessibilityLabel("Top of the discard pile, \(top.accessibleName)")
            }

            // Floating delta chip.
            if let delta = viewModel.tallyDelta {
                TallyDeltaChip(delta: delta)
                    .offset(y: -gaugeHeight * 0.52)
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
        let showsStuck = viewModel.isYourTurn && !options.canPlayFromHand
        let snackooRanks = viewModel.snackooRanks

        VStack(spacing: 8) {
            if viewModel.isYourTurn, let owed = viewModel.view?.playsRemainingThisTurn, owed > 1 {
                DebtBanner(playsOwed: owed)
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
                        subtitle: "\(viewModel.view?.yourWellCount ?? 0) left · risky",
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
                        title: "SDQ",
                        subtitle: "Self Disqualify",
                        tint: Palette.danger,
                        icon: "xmark.circle.fill"
                    ) {
                        viewModel.concede()
                    }
                }
            }
        }
        .animation(Motion.panel, value: viewModel.isYourTurn)
        .animation(Motion.panel, value: viewModel.view?.playsRemainingThisTurn)
        .padding(.bottom, 6)
    }

    // MARK: - Hand

    /// Turn state and the player's own well/poison/cap, above the fan. These used
    /// to sit *below* the fan, where the bottom of the cards covered them.
    private var statusRow: some View {
        VStack(spacing: 5) {
            turnIndicator
            HStack(spacing: 12) {
                WellPips(remaining: viewModel.view?.yourWellCount ?? 0)
                if let poison = viewModel.view?.yourPoisonPile, !poison.isEmpty {
                    PoisonBadge(count: poison.count)
                }
                Text("cap \(viewModel.view?.yourHandCap ?? 0)")
                    .labelStyle()
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Hand

    private func handArea(fanHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HandFanView(
                cards: viewModel.yourHand,
                playableIDs: viewModel.playableCardIDs,
                suppressedCardID: viewModel.pendingChoice.map { $0.card.id },
                rejectedCardID: viewModel.rejection?.cardID,
                isInteractive: viewModel.isYourTurn && !viewModel.isDealing,
                isDealing: viewModel.isDealing,
                onPlay: { viewModel.tapCard($0) },
                onLongPress: { viewModel.longPressCard($0) }
            )
            .frame(height: fanHeight)
        }
        .padding(.bottom, 2)
    }

    private var turnIndicator: some View {
        VStack(spacing: 2) {
            Group {
                if viewModel.view?.isOver ?? false {
                    EmptyView()
                } else if viewModel.isYourTurn {
                    Text(viewModel.options.canPlayFromHand ? "Your move" : "No legal card")
                        .font(Typography.sectionTitle)
                        .foregroundStyle(viewModel.options.canPlayFromHand ? Palette.brassLight : Palette.danger)
                        .transition(.opacity)
                } else {
                    Text("\(currentPlayerName) is thinking…")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                        .transition(.opacity)
                }
            }

            // Who's on the receiving end. Knowing this is most of the tactics in
            // 99 — whether to hand the next player a 99 or a clean slate — and a
            // small CW/CCW badge in the corner was leaving people to work it out
            // from the seating.
            if !(viewModel.view?.isOver ?? false), let next = viewModel.nextPlayerName {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(next == "You" ? "then you" : "then \(next)")
                        .font(Typography.label)
                        .tracking(0.8)
                }
                .foregroundStyle(Palette.ivoryFaint)
                .transition(.opacity)
                .accessibilityLabel(next == "You" ? "You play next" : "\(next) plays next")
            }
        }
        .frame(height: 40)
        .animation(Motion.panel, value: viewModel.isYourTurn)
        .animation(Motion.panel, value: viewModel.nextPlayerName)
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
                isHuman: wellIsHuman,
                onChoose: { viewModel.chooseWellCard(slot: $0) },
                onCancel: { viewModel.cancelWellChoice() },
                onSnackoo: { viewModel.takeWellSnackoo() },
                onDecline: { viewModel.declineWellSnackoo() },
                isShuffling: viewModel.isShufflingWell,
                onShuffle: wellIsHuman ? { viewModel.shuffleWell() } : nil
            )
            // Scoped to this overlay: the notification is global, so without the
            // gate a shake meant for the well would fire from anywhere.
            .onShake(isEnabled: wellIsHuman) { viewModel.shuffleWell() }
        }

        if let moment = viewModel.snackooMoment {
            SnackooCelebration(
                headline: moment.headline,
                detail: moment.detail,
                isYours: moment.isYours
            )
            .transition(.opacity)
        }

        if let poisoning = viewModel.queenPoisoning {
            QueenPoisonOverlay(
                card: poisoning.card,
                triggerName: poisoning.triggerName,
                itWasYou: poisoning.itWasYou,
                yourExiledCount: poisoning.yourExiledCount,
                yourNewCap: poisoning.yourNewCap,
                onDismiss: { viewModel.dismissQueenPoisoning() }
            )
        }

        if let pending = viewModel.pendingSet {
            SetPlaySheet(
                pending: pending,
                currentTally: viewModel.view?.tally ?? 0,
                declarations: viewModel.setDeclarations,
                projected: { viewModel.projectedSetTally($0) },
                onToggle: { viewModel.toggleSetCard($0) },
                onPlay: { viewModel.playSet(declaration: $0) },
                onCancel: { viewModel.cancelSet() }
            )
        }

        if let choice = viewModel.pendingChoice {
            DeclarationSheet(
                choice: choice,
                currentTally: viewModel.view?.tally ?? 0,
                projected: { viewModel.projectedTally(for: choice.card, declaration: $0) },
                onChoose: { viewModel.chooseDeclaration($0) },
                onCancel: { viewModel.cancelChoice() }
            )
        }

        if let outcome = viewModel.outcome {
            GameOverView(
                outcome: outcome,
                standings: viewModel.finishingOrder,
                subjectID: viewModel.viewingPlayerID,
                winnerName: viewModel.winnerName,
                isSharedDevice: viewModel.mode == .passAndPlay,
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

        // Before the first card: everyone builds their own well out of what they
        // were dealt. Above the table, below the hand-off — the hand-off has to
        // come first on a shared device or the next player's deal is face up
        // before they're holding the phone.
        if viewModel.isChoosingWell, let view = viewModel.view {
            WellSelectionView(
                playerName: view.yourName,
                slotCount: view.wellChoiceCount,
                wellSize: Rules.wellSize,
                isSharedDevice: viewModel.isSharedDevice,
                onConfirm: { viewModel.chooseWell(slots: $0) }
            )
        }

        // Last in the stack, so it covers everything. In pass-and-play the table
        // underneath is still showing the previous player's hand until they
        // hand over — this must sit on top of all of it.
        if viewModel.awaitingHandoff, let name = viewModel.handoffTargetName {
            HandoffView(
                nextPlayerName: name,
                seatNumber: viewModel.handoffSeatNumber,
                totalSeats: viewModel.participants.count,
                onReady: { viewModel.acknowledgeHandoff() }
            )
        }
    }

    private var currentPlayerName: String {
        guard let id = viewModel.view?.currentPlayerID else { return "" }
        return viewModel.participants.first { $0.id == id }?.name ?? ""
    }

    private var wellPlayerName: String {
        switch viewModel.wellReveal {
        case .choosing(let id, _), .rolling(let id), .revealed(_, _, let id),
             .rescue(_, _, let id), .survived(_, let id), .whatYouMissed(_, let id):
            return viewModel.participants.first { $0.id == id }?.name ?? ""
        case .idle:
            return ""
        }
    }

    private var wellIsHuman: Bool {
        switch viewModel.wellReveal {
        case .choosing(let id, _), .rolling(let id), .revealed(_, _, let id),
             .rescue(_, _, let id), .survived(_, let id), .whatYouMissed(_, let id):
            return id == viewModel.viewingPlayerID
        case .idle:
            return false
        }
    }
}

// MARK: - Small components

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
                BrassButton(
                    title: "SDQ",
                    subtitle: "Self Disqualify",
                    isProminent: false,
                    action: onQuit
                )
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
