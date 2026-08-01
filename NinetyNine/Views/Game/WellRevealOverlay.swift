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
    /// True while the two well cards are trading places.
    var isShuffling: Bool = false
    /// Shuffle them before picking. Nil when this player isn't the one choosing.
    var onShuffle: (() -> Void)?

    @Environment(\.motion) private var motion
    /// Which beat of the shuffle choreography we're on: 0 settled, 1 first
    /// crossing, 2 the crossing back, 3 the overshoot before it lands.
    @State private var shufflePass = 0
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
                    if case .survived = phase {
                        verdictBurst(playable: true)
                    }
                    cardStage
                }
                .frame(height: 250)

                verdictText
            }
            .padding(30)
        }
        .transition(.opacity)
        // `.contain` so the cards and buttons inside keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("well-reveal")
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
        case .survived: return "It plays."
        case .whatYouMissed: return "This is what you left down there."
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
                            .cardShadow(lift: 18 + shuffleLift(slot))
                            .rotationEffect(.degrees(slots > 1 ? (slot == 0 ? -5 : 5) : 0))
                            // They cross over each other rather than sliding
                            // sideways: one card passes in front and the other
                            // dips behind, twice, so it reads as a shuffle
                            // instead of two cards politely trading seats.
                            .offset(x: shuffleX(slot), y: shuffleY(slot))
                            .rotationEffect(.degrees(shuffleTilt(slot)))
                            .scaleEffect(shuffleScale(slot))
                            .zIndex(shuffleZ(slot))
                    }
                    .buttonStyle(.plain)
                    .disabled(isShuffling)
                    .accessibilityLabel(slots > 1
                        ? "Well card \(slot + 1) of \(slots)"
                        : "Your last well card")
                    .accessibilityHint("Turn this one over")
                }
            }
            .animation(motion.animation(Motion.shuffleStep), value: shufflePass)
            .onChange(of: isShuffling) { _, shuffling in
                guard shuffling else { return }
                Task { await runShuffleChoreography() }
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

        case .survived(let card, _):
            FlippableCard(card: card, isFaceUp: true, isPlayable: true)
                .frame(width: 168)

        case .whatYouMissed(let card, _):
            FlippableCard(card: card, isFaceUp: true, isPlayable: false)
                .frame(width: 168)
                .saturation(0.55)

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
        case .choosing(_, let slots):
            VStack(spacing: 12) {
                if slots > 1, let onShuffle {
                    // A shake is undiscoverable and unusable for plenty of
                    // people, so the gesture is a flourish on top of a button —
                    // never the only way to do it.
                    Button {
                        onShuffle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 13, weight: .bold))
                            Text("Shuffle")
                                .font(Typography.bodyEmphasised)
                        }
                        .foregroundStyle(Palette.brassLight)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(
                            Capsule().strokeBorder(Palette.brassDeep.opacity(0.8), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isShuffling)
                    .opacity(isShuffling ? 0.5 : 1)
                    .accessibilityIdentifier("well-shuffle")
                    .accessibilityHint("Mix the two cards so neither is the one you were looking at")

                    Text("or give the phone a shake")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryFaint)
                }

                cancelButton
            }

        case .rolling:
            Text("Drawing…")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.ivoryDim)

        case .whatYouMissed(let card, _):
            VStack(spacing: 8) {
                Text("THE OTHER ONE")
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .tracking(2)
                    .foregroundStyle(Palette.ivoryDim)
                Text(missedDetail(card: card))
                    .font(Typography.body)
                    .foregroundStyle(Palette.ivory.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            .transition(.opacity)

        case .survived:
            VStack(spacing: 12) {
                Text(isHuman ? "THE WELL HOLDS" : "\(playerName) SURVIVES")
                    .font(.system(size: 26, weight: .black, design: .serif))
                    .tracking(2)
                    .foregroundStyle(Palette.safe)
                    .shadow(color: Palette.safe.opacity(0.55), radius: 16)

                // The reward, stated — it's the only thing in 99 that hands you
                // cards instead of taking them.
                HStack(spacing: 10) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 17, weight: .bold))
                    Text("Draw two")
                        .font(Typography.bodyEmphasised)
                }
                .foregroundStyle(Palette.feltEdge)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(Capsule().fill(Palette.brassLight))

                Text(isHuman
                    ? "You went in with nothing and came out ahead."
                    : "They came out of it two cards richer.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ivoryDim)
                    .multilineTextAlignment(.center)
            }
            .transition(.scale(scale: 0.86).combined(with: .opacity))

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

    // MARK: Shuffle choreography

    /// Four beats rather than one: across, back, a small overshoot, settle.
    /// A single there-and-back reads as a swap — which is a different gesture
    /// and a less convincing one.
    private func runShuffleChoreography() async {
        let beats: [(pass: Int, hold: Duration)] = [
            (1, .milliseconds(190)),
            (2, .milliseconds(190)),
            (3, .milliseconds(120)),
            (0, .milliseconds(0)),
        ]
        for beat in beats {
            shufflePass = beat.pass
            if beat.hold > .zero { try? await Task.sleep(for: beat.hold) }
        }
    }

    /// Horizontal travel. The two cards mirror each other, and the direction
    /// flips between passes so they genuinely cross twice.
    private func shuffleX(_ slot: Int) -> CGFloat {
        let leading = slot == 0
        switch shufflePass {
        case 1: return leading ? 84 : -84
        case 2: return leading ? -84 : 84
        case 3: return leading ? 10 : -10
        default: return 0
        }
    }

    /// One card lifts over the top while the other dips under it, so the paths
    /// don't simply pass through each other.
    private func shuffleY(_ slot: Int) -> CGFloat {
        let leading = slot == 0
        switch shufflePass {
        case 1: return leading ? -34 : 20
        case 2: return leading ? 20 : -34
        case 3: return leading ? -6 : 4
        default: return 0
        }
    }

    private func shuffleTilt(_ slot: Int) -> Double {
        let leading = slot == 0
        switch shufflePass {
        case 1: return leading ? 16 : -9
        case 2: return leading ? -9 : 16
        case 3: return leading ? 3 : -2
        default: return 0
        }
    }

    /// The card passing in front grows very slightly — enough to read as nearer
    /// without looking like a zoom.
    private func shuffleScale(_ slot: Int) -> CGFloat {
        let leading = slot == 0
        switch shufflePass {
        case 1: return leading ? 1.06 : 0.97
        case 2: return leading ? 0.97 : 1.06
        default: return 1
        }
    }

    private func shuffleLift(_ slot: Int) -> CGFloat {
        shufflePass == 0 ? 0 : (isOverlapping(slot) ? 14 : -4)
    }

    /// Whichever card is in front this pass.
    private func isOverlapping(_ slot: Int) -> Bool {
        shufflePass == 2 ? slot == 1 : slot == 0
    }

    private func shuffleZ(_ slot: Int) -> Double {
        isOverlapping(slot) ? 1 : 0
    }

    /// What the unspent well card would have done — the question everybody asks
    /// the moment somebody goes out on a well.
    private func missedDetail(card: Card) -> String {
        isHuman
            ? "Your other well card was the \(card.accessibleName)."
            : "\(playerName)'s other well card was the \(card.accessibleName)."
    }

    /// Backing out of the well without turning anything over.
    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("Not yet")
                .font(Typography.bodyEmphasised)
                .foregroundStyle(Palette.ivoryDim)
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
                .background(Capsule().fill(.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
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
