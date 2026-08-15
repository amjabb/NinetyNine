//
//  SetupView.swift
//  Table configuration. Kept to one screen with live constraint feedback, so the
//  player can't build an impossible table and then be told off for it.
//

import SwiftUI

struct SetupView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var session = GameCenterSession.shared
    @Binding var mode: GameMode
    let onStart: () -> Void
    let onBack: () -> Void
    /// Online splits in two: setting up a match, and rejoining one. They were a
    /// single "Deal" button that did both and named neither.
    var onNewOnlineMatch: () -> Void = {}
    var onOpenOnlineMatches: () -> Void = {}

    @FocusState private var focusedSeat: Int?
    /// Names are edited in local state and written back on change. Binding a
    /// TextField straight through @AppStorage round-trips UserDefaults on every
    /// keystroke, and SwiftUI re-appends against the stale value — which showed
    /// up as "AdaAdaAdaAdaAda".
    @State private var seatNameDrafts: [String] = []

    enum GameMode: String, CaseIterable, Hashable {
        case solo
        case passAndPlay
        case online

        var title: String {
            switch self {
            case .solo: return "Solo"
            case .passAndPlay: return "Pass & play"
            case .online: return "Online"
            }
        }

        var blurb: String {
            switch self {
            case .solo:
                return "You against the machine."
            case .passAndPlay:
                return "Two to six of you, sharing this device. The screen covers between turns."
            case .online:
                return "Turn-based over Game Center. Take your turn now or come back tomorrow — the match waits."
            }
        }
    }

    /// Seats at the table, counting you.
    private var playerCount: Int {
        mode == .solo ? settings.opponentCount + 1 : settings.localPlayerCount
    }

    /// The hand-size ceiling depends on the player count, so it has to be
    /// recomputed live and the current choice clamped into it.
    private var maxDeal: Int {
        Rules.maxCardsDealt(forPlayerCount: playerCount)
    }

    private var currentDeal: Int {
        min(max(settings.cardsDealt, Rules.minCardsDealt), maxDeal)
    }

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    BrassSegments(
                        title: "Mode",
                        options: GameMode.allCases.map { ($0, $0.title) },
                        selection: $mode
                    )
                    .onChange(of: mode) { _, _ in clampDeal() }

                    Text(mode.blurb)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                        .padding(.top, -14)
                        .fixedSize(horizontal: false, vertical: true)

                    if mode == .online {
                        onlineSection
                    } else if mode == .solo {
                        BrassSegments(
                            title: "Opponents",
                            options: (1...5).map { ($0, "\($0)") },
                            selection: $settings.opponentCount
                        )
                        .onChange(of: settings.opponentCount) { _, _ in clampDeal() }

                        BrassSegments(
                            title: "Difficulty",
                            options: Difficulty.allCases.map { ($0, $0.displayName) },
                            selection: $settings.difficulty
                        )

                        Text(settings.difficulty.blurb)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ivoryDim)
                            .padding(.top, -14)
                    } else {
                        BrassSegments(
                            title: "Players",
                            options: (2...6).map { ($0, "\($0)") },
                            selection: $settings.localPlayerCount
                        )
                        .onChange(of: settings.localPlayerCount) { _, _ in clampDeal() }

                        seatNames
                        autoWellToggle
                    }

                    if mode != .online {
                        cardsDealtSection
                        dealSummary
                    }
                }
                .padding(24)
                .tableContentWidth()
            }

            VStack {
                Spacer()
                VStack(spacing: 10) {
                    if mode == .online {
                        // Two jobs, two buttons. "Deal" used to be both, and
                        // opening your existing games was something you found by
                        // accident.
                        // Not gated on being signed in: choosing a deal needs
                        // nothing from Game Center, and refusing to let someone
                        // even look while it reconnects is a wall for no reason.
                        // The invite step is where sign-in actually matters, and
                        // that's where it's enforced.
                        BrassButton(
                            title: "Start a new match",
                            subtitle: "pick the deal, then invite",
                            icon: "plus.circle.fill",
                            isProminent: true,
                            action: onNewOnlineMatch
                        )
                        BrassButton(
                            title: "Open one in progress",
                            subtitle: openInProgressSubtitle,
                            icon: "list.bullet",
                            isProminent: false,
                            isEnabled: session.canPlayOnline && session.totalMatches > 0,
                            action: onOpenOnlineMatches
                        )
                    } else {
                        BrassButton(
                            title: "Deal", icon: "play.fill",
                            isProminent: true, action: onStart
                        )
                    }
                    BrassButton(title: "Back", isProminent: false, action: onBack)
                }
                .padding(24)
                .tableContentWidth()
                .background(
                    LinearGradient(
                        colors: [.clear, Palette.feltShadow.opacity(0.95)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
            }
        }
        .onAppear { loadSeatNameDrafts() }
        .onChange(of: settings.localPlayerCount) { _, _ in loadSeatNameDrafts() }
        .onChange(of: seatNameDrafts) { _, drafts in
            settings.localPlayerNames = drafts
        }
    }

    /// Pull persisted names into the editable drafts, padded to the seat count.
    private func loadSeatNameDrafts() {
        var stored = settings.localPlayerNames
        while stored.count < settings.localPlayerCount { stored.append("") }
        let trimmed = Array(stored.prefix(settings.localPlayerCount))
        if trimmed != seatNameDrafts { seatNameDrafts = trimmed }
    }

    /// Greyed out with nothing to open, so the button states its own emptiness
    /// rather than opening a list to prove it.
    private var openInProgressSubtitle: String? {
        guard session.canPlayOnline else { return nil }
        if session.matchesAwaitingYou > 0 {
            return "\(session.matchesAwaitingYou) waiting on you"
        }
        if session.totalMatches > 0 {
            return "\(session.totalMatches) in progress"
        }
        return "no matches yet"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The table").labelStyle()
            Text("Set it up")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
        }
    }

    /// Online play depends on Game Center being signed in. Rather than gate the
    /// mode behind a wall, the section states plainly where things stand — the
    /// rest of the game works perfectly without an account.
    @ViewBuilder
    private var onlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch session.status {
            case .signedIn(let name):
                statusCard(
                    icon: "checkmark.seal.fill",
                    tint: Palette.safe,
                    title: "Signed in as \(name)",
                    detail: session.matchesAwaitingYou > 0
                        ? "\(session.matchesAwaitingYou) waiting on you."
                        : (session.totalMatches > 0
                            ? "\(session.totalMatches) match\(session.totalMatches == 1 ? "" : "es") in progress."
                            : "No matches yet.")
                )
            case .signingIn, .unknown:
                statusCard(
                    icon: "ellipsis.circle",
                    tint: Palette.brassMid,
                    title: "Connecting to Game Center…",
                    detail: "This only takes a moment."
                )
            case .unavailable(let reason):
                statusCard(
                    icon: "exclamationmark.triangle.fill",
                    tint: Palette.caution,
                    title: "Game Center isn't available",
                    detail: reason
                )
            }

            if session.canPlayOnline {
                BrassSegments(
                    title: "Players",
                    options: (2...6).map { ($0, "\($0)") },
                    selection: $settings.onlinePlayerCount
                )
                .onChange(of: settings.onlinePlayerCount) { _, _ in clampDeal() }
            }

            Text("The player who starts the match sets the deal size. Everything else plays exactly as it does offline.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ivoryFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { session.authenticateIfNeeded() }
    }

    private func statusCard(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(Palette.ivory)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ivoryDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
    }

    private func clampDeal() {
        // Clamp rather than silently allowing an illegal deal.
        if settings.cardsDealt > maxDeal { settings.cardsDealt = maxDeal }
    }

    /// Name entry for each seat. Names matter far more here than in solo — the
    /// hand-off screen has to be able to tell one player from another, and
    /// "Player 3" is a poor way to hand someone a phone.
    private var seatNames: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Names").labelStyle()
            VStack(spacing: 8) {
                // Array-wrapped for the same reason as everywhere else: the
                // bare range initialiser caches its count, and this one changes
                // every time the player adjusts the table size.
                ForEach(Array(0..<settings.localPlayerCount), id: \.self) { index in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(Typography.counter(12, weight: .heavy))
                            .foregroundStyle(Palette.brassMid)
                            .frame(width: 16)
                        TextField(
                            "Player \(index + 1)",
                            text: Binding(
                                get: { index < seatNameDrafts.count ? seatNameDrafts[index] : "" },
                                set: { newValue in
                                    while seatNameDrafts.count <= index { seatNameDrafts.append("") }
                                    seatNameDrafts[index] = String(newValue.prefix(16))
                                }
                            )
                        )
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { focusedSeat = nil }
                        .focused($focusedSeat, equals: index)
                        .foregroundStyle(Palette.ivory)
                        .font(Typography.bodyEmphasised)
                        .accessibilityLabel("Name for seat \(index + 1)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                focusedSeat == index
                                    ? Palette.brassMid.opacity(0.8)
                                    : Palette.brassDeep.opacity(0.4),
                                lineWidth: 1
                            )
                    )
                }
            }
        }
    }

    /// Pass-and-play only. Online players each hold their own device, and a solo
    /// player picks their well without passing anything to anybody.
    private var autoWellToggle: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bank wells automatically")
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(Palette.ivory)
                Text("Skip a lap of the table before the first card. The well is picked face down either way.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ivoryFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $settings.autoAssignWells)
                .labelsHidden()
                .tint(Palette.brass)
                .accessibilityIdentifier("setup.autoWell")
        }
        .padding(.top, 2)
    }

    private var cardsDealtSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Cards to deal").labelStyle()
                Spacer()
                Text("\(currentDeal)")
                    .font(Typography.counter(15, weight: .heavy))
                    .foregroundStyle(Palette.brassLight)
            }
            // A stepper rather than a slider: the legal range is small and every
            // value matters, so precision beats sweep.
            HStack(spacing: 8) {
                stepButton(icon: "minus", enabled: currentDeal > Rules.minCardsDealt) {
                    settings.cardsDealt = max(Rules.minCardsDealt, currentDeal - 1)
                }
                cardsDealtTrack
                stepButton(icon: "plus", enabled: currentDeal < maxDeal) {
                    settings.cardsDealt = min(maxDeal, currentDeal + 1)
                }
            }
            Text(dealExplanation)
                .font(.system(size: 11))
                .foregroundStyle(Palette.ivoryFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The number isn't a hand size any more, and saying so is the difference
    /// between "deal 5" being a reasonable choice and a baffling one.
    private var dealExplanation: String {
        let hand = currentDeal - Rules.wellSize
        let topUp = hand < Rules.sustainingHandCap
            ? " You'd draw up to \(Rules.sustainingHandCap) on your first turn."
            : ""
        return "Two of them go to your well, so you'd start holding \(hand).\(topUp) "
            + "Up to \(maxDeal) with \(playerCount) players."
    }

    private var cardsDealtTrack: some View {
        GeometryReader { geometry in
            let span = Rules.minCardsDealt...12
            let count = span.count
            HStack(spacing: 3) {
                ForEach(Array(span), id: \.self) { value in
                    let isAvailable = value <= maxDeal
                    let isFilled = value <= currentDeal
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isFilled
                            ? AnyShapeStyle(Palette.brassFace)
                            : AnyShapeStyle(Color.white.opacity(isAvailable ? 0.12 : 0.04)))
                        .frame(height: isFilled ? 18 : 12)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: geometry.size.width)
            .animation(Motion.panel, value: settings.cardsDealt)
            .animation(Motion.panel, value: maxDeal)
            .accessibilityHidden(true)
            .onAppear { _ = count }
        }
        .frame(height: 24)
    }

    private func stepButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled else {
                Haptics.shared.play(.rejected)
                return
            }
            Haptics.shared.play(.select)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.ivory)
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "plus" ? "One more card to deal" : "One fewer card to deal")
    }

    /// Shows the arithmetic of the deal, because "why can't I pick 12?" is the
    /// obvious question and the answer is just a sum.
    private var dealSummary: some View {
        let players = playerCount
        let hand = currentDeal
        let dealt = players * (hand + 2)
        return VStack(alignment: .leading, spacing: 6) {
            Text("The deal").labelStyle()
            HStack(spacing: 0) {
                Text("\(players) × (\(hand) + 2 well)")
                    .font(Typography.counter(13, weight: .semibold))
                    .foregroundStyle(Palette.ivory.opacity(0.8))
                Spacer()
                Text("\(dealt) of 52 dealt")
                    .font(Typography.counter(13, weight: .bold))
                    .foregroundStyle(Palette.brassLight)
            }
            Text("\(52 - dealt) card\(52 - dealt == 1 ? "" : "s") left in the draw pile.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ivoryFaint)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.4), lineWidth: 1)
        )
        .padding(.bottom, 120)
    }
}
