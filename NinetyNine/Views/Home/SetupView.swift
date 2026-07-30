//
//  SetupView.swift
//  Table configuration. Kept to one screen with live constraint feedback, so the
//  player can't build an impossible table and then be told off for it.
//

import SwiftUI

struct SetupView: View {
    @ObservedObject private var settings = Settings.shared
    let onStart: () -> Void
    let onBack: () -> Void

    /// The hand-size ceiling depends on the player count, so it has to be
    /// recomputed live and the current choice clamped into it.
    private var maxHandSize: Int {
        Rules.maxHandSize(forPlayerCount: settings.opponentCount + 1)
    }

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    BrassSegments(
                        title: "Opponents",
                        options: (1...5).map { ($0, "\($0)") },
                        selection: $settings.opponentCount
                    )
                    .onChange(of: settings.opponentCount) { _, _ in
                        // Clamp rather than silently allowing an illegal deal.
                        if settings.handSize > maxHandSize { settings.handSize = maxHandSize }
                    }

                    BrassSegments(
                        title: "Difficulty",
                        options: Difficulty.allCases.map { ($0, $0.displayName) },
                        selection: $settings.difficulty
                    )

                    Text(settings.difficulty.blurb)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                        .padding(.top, -14)

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The table").labelStyle()
            Text("Set it up")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
        }
    }

    private var handSizeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Hand size").labelStyle()
                Spacer()
                Text("\(settings.validHandSize())")
                    .font(Typography.counter(15, weight: .heavy))
                    .foregroundStyle(Palette.brassLight)
            }
            // A stepper rather than a slider: the legal range is only 5-12 and
            // every value matters, so precision beats sweep.
            HStack(spacing: 8) {
                stepButton(icon: "minus", enabled: settings.validHandSize() > Rules.minHandSize) {
                    settings.handSize = max(Rules.minHandSize, settings.validHandSize() - 1)
                }
                handSizeTrack
                stepButton(icon: "plus", enabled: settings.validHandSize() < maxHandSize) {
                    settings.handSize = min(maxHandSize, settings.validHandSize() + 1)
                }
            }
            Text("Up to \(maxHandSize) with \(settings.opponentCount + 1) players — everyone also needs a two-card well.")
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
                    let isFilled = value <= settings.validHandSize()
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
        let players = settings.opponentCount + 1
        let hand = settings.validHandSize()
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
