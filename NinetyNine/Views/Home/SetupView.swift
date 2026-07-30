//
//  SetupView.swift
//  Table configuration. Kept to one screen with live constraint feedback, so the
//  player can't build an impossible table and then be told off for it.
//

import SwiftUI

struct SetupView: View {
    @ObservedObject private var settings = Settings.shared
    @Binding var mode: GameMode
    let onStart: () -> Void
    let onBack: () -> Void

    @FocusState private var focusedSeat: Int?
    /// Names are edited in local state and written back on change. Binding a
    /// TextField straight through @AppStorage round-trips UserDefaults on every
    /// keystroke, and SwiftUI re-appends against the stale value — which showed
    /// up as "AdaAdaAdaAdaAda".
    @State private var seatNameDrafts: [String] = []

    enum GameMode: String, CaseIterable, Hashable {
        case solo
        case passAndPlay

        var title: String { self == .solo ? "Solo" : "Pass & play" }
        var blurb: String {
            self == .solo
                ? "You against the machine."
                : "Two to six of you, sharing this device. The screen covers between turns."
        }
    }

    /// Seats at the table, counting you.
    private var playerCount: Int {
        mode == .solo ? settings.opponentCount + 1 : settings.localPlayerCount
    }

    /// The hand-size ceiling depends on the player count, so it has to be
    /// recomputed live and the current choice clamped into it.
    private var maxHandSize: Int {
        Rules.maxHandSize(forPlayerCount: playerCount)
    }

    private var currentHandSize: Int {
        min(max(settings.handSize, Rules.minHandSize), maxHandSize)
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
                    .onChange(of: mode) { _, _ in clampHandSize() }

                    Text(mode.blurb)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                        .padding(.top, -14)
                        .fixedSize(horizontal: false, vertical: true)

                    if mode == .solo {
                        BrassSegments(
                            title: "Opponents",
                            options: (1...5).map { ($0, "\($0)") },
                            selection: $settings.opponentCount
                        )
                        .onChange(of: settings.opponentCount) { _, _ in clampHandSize() }

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
                        .onChange(of: settings.localPlayerCount) { _, _ in clampHandSize() }

                        seatNames
                    }

                    handSizeSection

                    dealSummary
                }
                .padding(24)
                .tableContentWidth()
            }

            VStack {
                Spacer()
                VStack(spacing: 10) {
                    BrassButton(title: "Deal", icon: "play.fill", isProminent: true, action: onStart)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The table").labelStyle()
            Text("Set it up")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
        }
    }

    private func clampHandSize() {
        // Clamp rather than silently allowing an illegal deal.
        if settings.handSize > maxHandSize { settings.handSize = maxHandSize }
    }

    /// Name entry for each seat. Names matter far more here than in solo — the
    /// hand-off screen has to be able to tell one player from another, and
    /// "Player 3" is a poor way to hand someone a phone.
    private var seatNames: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Names").labelStyle()
            VStack(spacing: 8) {
                ForEach(0..<settings.localPlayerCount, id: \.self) { index in
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

    private var handSizeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Hand size").labelStyle()
                Spacer()
                Text("\(currentHandSize)")
                    .font(Typography.counter(15, weight: .heavy))
                    .foregroundStyle(Palette.brassLight)
            }
            // A stepper rather than a slider: the legal range is only 5-12 and
            // every value matters, so precision beats sweep.
            HStack(spacing: 8) {
                stepButton(icon: "minus", enabled: currentHandSize > Rules.minHandSize) {
                    settings.handSize = max(Rules.minHandSize, currentHandSize - 1)
                }
                handSizeTrack
                stepButton(icon: "plus", enabled: currentHandSize < maxHandSize) {
                    settings.handSize = min(maxHandSize, currentHandSize + 1)
                }
            }
            Text("Up to \(maxHandSize) with \(playerCount) players — everyone also needs a two-card well.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ivoryFaint)
        }
    }

    private var handSizeTrack: some View {
        GeometryReader { geometry in
            let span = Rules.minHandSize...12
            let count = span.count
            HStack(spacing: 3) {
                ForEach(Array(span), id: \.self) { value in
                    let isAvailable = value <= maxHandSize
                    let isFilled = value <= currentHandSize
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isFilled
                            ? AnyShapeStyle(Palette.brassFace)
                            : AnyShapeStyle(Color.white.opacity(isAvailable ? 0.12 : 0.04)))
                        .frame(height: isFilled ? 18 : 12)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: geometry.size.width)
            .animation(Motion.panel, value: settings.handSize)
            .animation(Motion.panel, value: maxHandSize)
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
        .accessibilityLabel(icon == "plus" ? "Increase hand size" : "Decrease hand size")
    }

    /// Shows the arithmetic of the deal, because "why can't I pick 12?" is the
    /// obvious question and the answer is just a sum.
    private var dealSummary: some View {
        let players = playerCount
        let hand = currentHandSize
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
