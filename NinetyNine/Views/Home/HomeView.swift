//
//  HomeView.swift
//  The title screen. Sets the tone before a single card is dealt.
//

import SwiftUI

struct HomeView: View {
    let onPlay: () -> Void
    let onRules: () -> Void
    let onStats: () -> Void
    let onSettings: () -> Void

    @ObservedObject private var records = Records.shared
    @Environment(\.motion) private var motion
    @State private var hasAppeared = false
    @State private var sheen: Double = 0

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            // Three cards fanned behind the wordmark, drifting slowly.
            decorativeFan

            VStack(spacing: 0) {
                // Fixed top inset rather than a pair of competing Spacers, so the
                // wordmark sits high and clear of the decorative fan behind it.
                Spacer().frame(height: 56)

                wordmark

                Spacer(minLength: 0)

                if records.stats.gamesPlayed > 0 {
                    streakLine
                        .padding(.bottom, 18)
                }

                VStack(spacing: 11) {
                    BrassButton(
                        title: "Play",
                        subtitle: "\(Settings.shared.opponentCount + 1) players · \(Settings.shared.difficulty.displayName)",
                        icon: "play.fill",
                        isProminent: true,
                        action: onPlay
                    )
                    HStack(spacing: 11) {
                        BrassButton(title: "Rules", icon: "book.closed.fill", isProminent: false, action: onRules)
                        BrassButton(title: "Record", icon: "chart.bar.fill", isProminent: false, action: onStats)
                    }
                    BrassButton(title: "Settings", icon: "slider.horizontal.3", isProminent: false, action: onSettings)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 34)
            }
            .tableContentWidth()
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : motion.displacement(22))
        }
        .onAppear {
            withAnimation(motion.animation(Motion.screen)) { hasAppeared = true }
            if let ambient = motion.ambient(Motion.breathe(4.5)) {
                withAnimation(ambient) { sheen = 1 }
            }
        }
    }

    // MARK: Wordmark

    private var wordmark: some View {
        VStack(spacing: 2) {
            Text("99")
                .font(Typography.wordmark)
                .tracking(-6)
                .brassFoil()
                // A slow specular sweep across the foil. This is the one piece of
                // ambient motion on the screen, and it's what makes the metal read
                // as metal rather than as a gold-coloured fill.
                .overlay {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 90)
                    .offset(x: -150 + sheen * 300)
                    .blendMode(.plusLighter)
                    .mask(
                        Text("99")
                            .font(Typography.wordmark)
                            .tracking(-6)
                    )
                    .allowsHitTesting(false)
                }

            Text("PUSH YOUR LUCK")
                .font(.system(size: 12, weight: .heavy))
                .tracking(5.5)
                .foregroundStyle(Palette.ivoryDim)
        }
    }

    private var streakLine: some View {
        HStack(spacing: 16) {
            statChip(value: "\(records.stats.gamesWon)", label: "Wins")
            statChip(value: "\(Int(records.stats.winRate * 100))%", label: "Win rate")
            statChip(value: "\(records.stats.currentStreak)", label: "Streak")
        }
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(Typography.counter(19, weight: .heavy))
                .foregroundStyle(Palette.brassLight)
            Text(label).labelStyle()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Decoration

    private var decorativeFan: some View {
        GeometryReader { geometry in
            // Sized against the content measure, not the screen, so the cards
            // don't balloon on an iPad.
            let stage = min(geometry.size.width, Layout.maxContentWidth)
            ZStack {
                ForEach(Array(HomeView.showcase.enumerated()), id: \.element.id) { index, card in
                    CardFaceView(card: card)
                        .frame(width: stage * 0.30)
                        .cardShadow(lift: 8)
                        .rotationEffect(.degrees(Double(index - 1) * 15 + (sheen - 0.5) * 1.6))
                        .offset(
                            x: CGFloat(index - 1) * stage * 0.21,
                            y: abs(CGFloat(index - 1)) * 14
                        )
                }
            }
            .frame(width: geometry.size.width, alignment: .center)
            // Sits in the empty band between the wordmark and the buttons.
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.52)
            .opacity(0.26)
            .blur(radius: 1.1)
            .allowsHitTesting(false)
        }
    }

    /// The three cards that define the game: the 9 that slams, the Queen that
    /// betrays, and the 10 that saves.
    private static let showcase: [Card] = [
        Card(id: 9001, rank: .nine, suit: .spades),
        Card(id: 9002, rank: .queen, suit: .hearts),
        Card(id: 9003, rank: .ten, suit: .clubs),
    ]
}
