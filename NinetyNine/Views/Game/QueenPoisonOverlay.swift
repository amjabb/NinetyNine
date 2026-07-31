//
//  QueenPoisonOverlay.swift
//  The turn queens go bad.
//
//  This happens exactly once per game and changes the rules for everyone at the
//  same instant: every queen still in a hand is exiled, and each one costs its
//  owner a card of hand capacity permanently. It used to be a banner that slid
//  past in under a second, which is nothing like enough for a moment you can't
//  undo and won't see again.
//
//  So it takes the screen. The card that did it is shown face up, because the
//  first question anyone asks is "who drew it?" — and if it was you, the copy
//  says so plainly.
//

import SwiftUI

struct QueenPoisonOverlay: View {
    let card: Card
    let triggerName: String
    let itWasYou: Bool
    /// Queens taken out of *your* hand by this, and where your cap lands.
    let yourExiledCount: Int
    let yourNewCap: Int?
    let onDismiss: () -> Void

    @Environment(\.motion) private var motion
    @State private var hasLanded = false

    var body: some View {
        ZStack {
            // Near-opaque, not a tint. The table underneath has a banner, a
            // thinking line and a status row that all sit right where this text
            // goes — at 0.7 they read straight through the headline.
            Color.black.opacity(0.93)
                .ignoresSafeArea()
            RadialGradient(
                colors: [Palette.poison.opacity(0.30), .clear],
                center: .center, startRadius: 20, endRadius: 460
            )
            .ignoresSafeArea()
            .opacity(hasLanded ? 1 : 0)

            VStack(spacing: 20) {
                Text(headline)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.poison)
                    .multilineTextAlignment(.center)
                    .shadow(color: Palette.poison.opacity(0.5), radius: 14)
                    .fixedSize(horizontal: false, vertical: true)

                queenCard

                VStack(spacing: 7) {
                    Text("Queens are poison from here on.")
                        .font(Typography.bodyEmphasised)
                        .foregroundStyle(Palette.ivory)
                        .multilineTextAlignment(.center)
                    Text(consequence)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Tap to continue")
                    .font(Typography.label)
                    .foregroundStyle(Palette.ivoryFaint)
                    .padding(.top, 2)
            }
            .padding(28)
            .frame(maxWidth: 380)
            .background(panel)
            .padding(.horizontal, 20)
            .opacity(hasLanded ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onAppear {
            withAnimation(motion.animation(Motion.drama)) { hasLanded = true }
        }
        .transition(.opacity)
        // `.contain`, not a label: an identifier on a container overwrites its
        // children's, and the card inside has its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queen-poison-overlay")
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Palette.feltEdge)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Palette.poison.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Palette.poison.opacity(0.35), radius: 36)
    }

    /// The queen arrives rotated and small, then settles — a card being turned
    /// over rather than a dialog appearing.
    private var queenCard: some View {
        CardFaceView(card: card)
            .frame(width: 132)
            .cardShadow(lift: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.poison, lineWidth: 2)
                    .blur(radius: 3)
            )
            .rotationEffect(.degrees(hasLanded ? -4 : 22))
            .scaleEffect(hasLanded ? 1 : 0.6)
            .opacity(hasLanded ? 1 : 0)
            .shadow(color: Palette.poison.opacity(0.7), radius: motion.displacement(30))
    }

    private var headline: String {
        itWasYou ? "Oh no — you drew a Queen" : "\(triggerName) drew a Queen"
    }

    /// What it actually costs *this* player, which is the only part that differs
    /// between the people looking at this screen.
    private var consequence: String {
        guard yourExiledCount > 0, let cap = yourNewCap else {
            return "Any Queen still in a hand is exiled to its owner's poison pile. Three of them there is still a Snackoo."
        }
        let queens = yourExiledCount == 1 ? "Your Queen is" : "Your \(yourExiledCount) Queens are"
        return "\(queens) exiled to your poison pile — your hand limit is now \(cap). Three there is still a Snackoo."
    }
}
