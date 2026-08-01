//
//  SnackooCelebration.swift
//  Confetti, because a Snackoo is the one move worth cheering.
//
//  Everything else in 99 is damage control — you survive a turn, you dodge the
//  ceiling, you get away with the well. A Snackoo is the only time you *do*
//  something to the table rather than to yourself, and it happens to anyone at
//  any moment, including out of turn. So the whole table sees it.
//
//  Drawn rather than animated frame by frame: each piece is a deterministic
//  function of its index and one progress value, so the entire burst is a single
//  animatable Double. No timers, no per-piece state, nothing to leak.
//

import SwiftUI

struct SnackooCelebration: View {
    let headline: String
    let detail: String
    /// The three cards being declared, face up.
    var cards: [Card] = []
    /// Whose it was, for the colour of the burst.
    var isYours: Bool

    @Environment(\.motion) private var motion
    @State private var progress: Double = 0
    @State private var textScale: CGFloat = 0.7

    private let pieceCount = 46

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<pieceCount, id: \.self) { index in
                        confettiPiece(index, in: geometry.size)
                    }
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                Text(headline)
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(isYours ? Palette.brassLight : Palette.ivory)
                    .shadow(color: Palette.brass.opacity(0.7), radius: 22)

                // The claim itself. A Snackoo is a declaration made out loud at
                // a table and answered by showing the cards; saying only "three
                // Jacks" asks everyone to take your word for it.
                if !cards.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            CardFaceView(card: card)
                                .frame(width: 74)
                                .cardShadow(lift: 16)
                                .rotationEffect(.degrees(Double(index - 1) * 7))
                                .offset(y: abs(Double(index - 1)) * 5)
                                .scaleEffect(textScale)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text(detail)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ivory.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
            }
            .scaleEffect(textScale)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
        }
        .onAppear {
            // Reduce Motion turns this into a still card rather than a shower —
            // the message is the point, the confetti is the flourish.
            withAnimation(motion.animation(.spring(duration: 0.4, bounce: 0.5))) {
                textScale = 1
            }
            withAnimation(motion.animation(.easeOut(duration: 1.9))) {
                progress = 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snackoo-celebration")
    }

    /// One piece of confetti, entirely determined by its index.
    private func confettiPiece(_ index: Int, in size: CGSize) -> some View {
        let seed = Double(index)
        // Cheap deterministic spread — no RNG, so the burst is identical on
        // every device replaying the same moment.
        let spread = (seed * 0.6180339887).truncatingRemainder(dividingBy: 1)
        let drift = (seed * 0.7548776662).truncatingRemainder(dividingBy: 1)
        let spin = (seed * 0.3819660112).truncatingRemainder(dividingBy: 1)

        let startX = size.width * 0.5
        let endX = size.width * (0.5 + (spread - 0.5) * 1.9)
        let peak = size.height * (0.14 + drift * 0.3)
        let fall = size.height * (0.9 + drift * 0.25)

        // Up fast, then down under gravity: two eased halves rather than a line.
        let rise = min(1, progress / 0.38)
        let drop = max(0, (progress - 0.38) / 0.62)
        let y = size.height * 0.42 - peak * rise + fall * drop * drop

        return RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(colour(index))
            .frame(width: 7, height: 11)
            .rotationEffect(.degrees(spin * 360 + progress * (spin > 0.5 ? 720 : -540)))
            .position(
                x: startX + (endX - startX) * min(1, progress * 1.35),
                y: y
            )
            .opacity(progress > 0.82 ? (1 - progress) / 0.18 : 1)
    }

    private func colour(_ index: Int) -> Color {
        let palette: [Color] = isYours
            ? [Palette.brassLight, Palette.brass, Palette.ivory, Palette.safe, Palette.caution]
            : [Palette.ivoryDim, Palette.brass, Palette.ivory, Palette.negative]
        return palette[index % palette.count]
    }
}
