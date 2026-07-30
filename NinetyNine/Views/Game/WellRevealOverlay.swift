//
//  WellRevealOverlay.swift
//  The well: the only coin-flip in the game, and the moment it hangs on.
//
//  Going to the well is a 50/50 on your own elimination, decided by a card you
//  don't choose. That deserves more than a toast — so the table dims, the two
//  face-down cards shuffle, one comes forward, and it flips. The verdict then
//  holds on screen long enough to land.
//

import SwiftUI

struct WellRevealOverlay: View {
    let phase: GameViewModel.WellRevealPhase
    /// Name of whoever is at the well, for the caption.
    let playerName: String
    let isHuman: Bool
    /// Called with the slot the player picked, while choosing.
    var onChoose: (Int) -> Void = { _ in }
    var onCancel: () -> Void = {}
    /// Take the Snackoo reprieve on an unplayable card that completes a trio.
    var onSnackoo: () -> Void = {}
    /// Decline it and accept elimination.
    var onDecline: () -> Void = {}

    @Environment(\.motion) private var motion
    @State private var shuffleOffset: CGFloat = 0
    @State private var burstScale: CGFloat = 0.2
    @State private var burstOpacity: Double = 0

    var body: some View {
        ZStack {
            // Dim the table hard — nothing else matters for these two seconds.
            Color.black.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                caption

                ZStack {
                    if case .revealed(_, let playable, _) = phase {
                        verdictBurst(playable: playable)
                    }
                    cardStage
                }
                .frame(height: 250)

                verdictText
            }
            .padding(30)
        }
        .transition(.opacity)
    }

    // MARK: Caption

    private var caption: some View {
        VStack(spacing: 6) {
            Text("THE WELL")
                .font(.system(size: 13, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Palette.brassMid)
            Text(isHuman ? captionForHuman : "\(playerName) reaches for the well.")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Cards

    private var captionForHuman: String {
        switch phase {
        case .choosing: return "Pick one. You won't know until you turn it."
        case .rescue: return "It won't play — but it's your third."
        default: return "One card. Everything rides on it."
        }
    }

    @ViewBuilder
    private var cardStage: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .choosing(_, let slots):
            // Both face down, so the choice is blind — but it's the player's.
            // Having the game pick made the tensest moment in the game something
            // that happened *to* them.
            HStack(spacing: 22) {
                ForEach(0..<slots, id: \.self) { slot in
                    Button {
                        Haptics.shared.play(.cardFlick)
                        onChoose(slot)
                    } label: {
                        CardBackView(isHighlighted: true)
                            .frame(width: slots > 1 ? 132 : 156)
                            .cardShadow(lift: 18)
                            .rotationEffect(.degrees(slots > 1 ? (slot == 0 ? -5 : 5) : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(slots > 1
                        ? "Well card \(slot + 1) of \(slots)"
                        : "Your last well card")
                    .accessibilityHint("Turn this one over")
                }
            }

        case .rolling:
            // Two face-down cards trading places — you can see there's a choice
            // being made, but not what it is.
            HStack(spacing: 18) {
                CardBackView(isHighlighted: true)
                    .frame(width: 132)
                    .offset(x: shuffleOffset, y: -shuffleOffset * 0.25)
                    .rotationEffect(.degrees(shuffleOffset * 0.09))
                CardBackView(isHighlighted: true)
                    .frame(width: 132)
                    .offset(x: -shuffleOffset, y: shuffleOffset * 0.25)
                    .rotationEffect(.degrees(-shuffleOffset * 0.09))
            }
            .cardShadow(lift: 20)
            .onAppear {
                guard let ambient = motion.ambient(Motion.breathe(0.34)) else { return }
                withAnimation(ambient) { shuffleOffset = 26 }
            }

        case .rescue(let card, _, _):
            // Struck through, because it genuinely cannot be played — the way out
            // is the Snackoo, not the card.
            FlippableCard(card: card, isFaceUp: true, isPlayable: false)
                .frame(width: 168)
                .cardShadow(lift: 26)
                .overlay {
                    Rectangle()
                        .fill(Palette.danger)
                        .frame(height: 5)
                        .rotationEffect(.degrees(-24))
                        .shadow(color: Palette.danger.opacity(0.8), radius: 8)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))

        case .revealed(let card, let playable, _):
            FlippableCard(card: card, isFaceUp: true, isPlayable: playable)
                .frame(width: 168)
                .cardShadow(lift: 26)
                .rotation3DEffect(.degrees(playable ? 0 : 8), axis: (x: 1, y: 0, z: 0))
                .scaleEffect(playable ? 1 : 0.94)
                .saturation(playable ? 1 : 0.2)
                .overlay {
                    if !playable {
                        // A hard diagonal strike, drawn on the card itself.
                        Rectangle()
                            .fill(Palette.danger)
                            .frame(height: 5)
                            .rotationEffect(.degrees(-24))
                            .shadow(color: Palette.danger.opacity(0.8), radius: 8)
                    }
                }
                .transition(.scale(scale: 0.55).combined(with: .opacity))
        }
    }

    /// A radial flare behind the card — gold for survival, red for the end.
    private func verdictBurst(playable: Bool) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        (playable ? Palette.brassLight : Palette.danger).opacity(0.55),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: 190
                )
            )
            .frame(width: 380, height: 380)
            .scaleEffect(burstScale)
            .opacity(burstOpacity)
            .blendMode(.plusLighter)
            .onAppear {
                withAnimation(motion.animation(Motion.dramaSlow)) {
                    burstScale = 1
                    burstOpacity = 1
                }
            }
    }

    // MARK: Verdict

    @ViewBuilder
    private var verdictText: some View {
        switch phase {
        case .choosing:
            Button(action: onCancel) {
                Text("Not yet")
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(Palette.ivoryDim)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(.white.opacity(0.07)))
            }
            .buttonStyle(.plain)

        case .rolling:
            Text("Drawing…")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.ivoryDim)

        case .rescue(_, let rank, _):
            VStack(spacing: 14) {
                Text("SNACKOO!")
                    .font(.system(size: 26, weight: .black, design: .serif))
                    .tracking(2)
                    .foregroundStyle(Palette.brassLight)
                Text("That's your third \(rank.displayName). Discard all three and draw three fresh — you'll still owe a play.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ivory.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)

                BrassButton(
                    title: "Snackoo",
                    subtitle: "three \(rank.displayName)s",
                    icon: "sparkles",
                    isProminent: true,
                    action: onSnackoo
                )
                Button(action: onDecline) {
                    Text("Accept the loss")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .transition(.opacity.combined(with: .offset(y: 12)))

        case .revealed(let card, let playable, _):
            VStack(spacing: 8) {
                Text(playable ? "PLAYABLE" : "UNPLAYABLE")
                    .font(.system(size: 26, weight: .black, design: .serif))
                    .tracking(2)
                    .foregroundStyle(playable ? Palette.brassLight : Palette.danger)
                Text(verdictDetail(card: card, playable: playable))
                    .font(Typography.body)
                    .foregroundStyle(Palette.ivory.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .transition(.opacity.combined(with: .offset(y: 12)))

        case .idle:
            EmptyView()
        }
    }

    private func verdictDetail(card: Card, playable: Bool) -> String {
        if playable {
            return isHuman
                ? "The \(card.accessibleName) plays. Two bonus cards for the nerve."
                : "\(playerName) survives, and draws two."
        }
        return isHuman
            ? "The \(card.accessibleName) has nowhere to go. You're out."
            : "\(playerName) is out."
    }
}
