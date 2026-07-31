//
//  NextDealView.swift
//  "You deal. How many?"
//
//  Between games the rulebook hands the deal to the player who went out *first* —
//  a small consolation for early elimination, and the one decision they get to
//  make about the next game.
//
//  Now that the sustaining hand cap is five regardless of the deal, the size is
//  an opening position rather than a standing allowance: deal big for a cushion
//  that decays, deal small to strangle everyone equally. That's a real choice,
//  which is why it's worth asking rather than silently reusing the last value.
//

import SwiftUI

struct NextDealView: View {
    let dealerName: String
    /// False when an AI holds the deal — then this screen reports their choice
    /// rather than asking for one.
    let isDealerHuman: Bool
    let playerCount: Int
    @Binding var cardsDealt: Int
    let onDeal: () -> Void
    let onCancel: () -> Void

    @Environment(\.motion) private var motion
    @State private var hasAppeared = false

    private var maxHandSize: Int { Rules.maxCardsDealt(forPlayerCount: playerCount) }

    var body: some View {
        ZStack {
            Palette.feltShadow.opacity(0.97).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Text(isDealerHuman ? "YOUR DEAL" : "THE DEAL PASSES")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(4)
                        .foregroundStyle(Palette.brassMid)

                    Text(dealerName)
                        .font(.system(size: 38, weight: .black, design: .serif))
                        .brassFoil()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text("First one out deals the next game.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                }
                .padding(.bottom, 30)

                if isDealerHuman {
                    picker
                } else {
                    aiChoice
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    BrassButton(
                        title: isDealerHuman ? "Deal \(cardsDealt)" : "Continue",
                        icon: "play.fill",
                        isProminent: true,
                        action: onDeal
                    )
                    BrassButton(title: "Back to menu", isProminent: false, action: onCancel)
                }
                .padding(.horizontal, 4)
            }
            .padding(28)
            .tableContentWidth()
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : motion.displacement(18))
        }
        .onAppear {
            // Clamp before showing — the previous game's size may be illegal at
            // this table size.
            cardsDealt = min(max(cardsDealt, Rules.minCardsDealt), maxHandSize)
            withAnimation(motion.animation(Motion.drama)) { hasAppeared = true }
        }
        .transition(.opacity)
    }

    // MARK: Picker

    private var picker: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Cards each").labelStyle()
                Spacer()
                Text("\(cardsDealt)")
                    .font(Typography.counter(22, weight: .heavy))
                    .foregroundStyle(Palette.brassLight)
            }

            HStack(spacing: 8) {
                stepButton(icon: "minus", enabled: cardsDealt > Rules.minCardsDealt) {
                    cardsDealt = max(Rules.minCardsDealt, cardsDealt - 1)
                }
                track
                stepButton(icon: "plus", enabled: cardsDealt < maxHandSize) {
                    cardsDealt = min(maxHandSize, cardsDealt + 1)
                }
            }

            Text("Everyone plays down to \(Rules.sustainingHandCap) and holds there — a big deal is an opening cushion, not a permanent one.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ivoryFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.5), lineWidth: 1)
        )
    }

    private var track: some View {
        HStack(spacing: 3) {
            ForEach(Rules.minCardsDealt...12, id: \.self) { value in
                RoundedRectangle(cornerRadius: 3)
                    .fill(value <= cardsDealt
                        ? AnyShapeStyle(Palette.brassFace)
                        : AnyShapeStyle(Color.white.opacity(value <= maxHandSize ? 0.12 : 0.04)))
                    .frame(height: value <= cardsDealt ? 20 : 13)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 26)
        .animation(Motion.panel, value: cardsDealt)
        .accessibilityHidden(true)
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.ivory)
                .frame(width: 38, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        // Deliberately not "Deal one more card": the primary button on this
        // screen is "Deal 7", and two controls whose labels begin the same way
        // are ambiguous to anyone navigating by label — VoiceOver users and
        // automation alike.
        .accessibilityLabel(icon == "plus" ? "One more card" : "One fewer card")
    }

    // MARK: AI dealer

    private var aiChoice: some View {
        VStack(spacing: 6) {
            Text("\(cardsDealt)")
                .font(Typography.tally(64))
                .foregroundStyle(Palette.brassLight)
            Text("cards each")
                .labelStyle()
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dealerName) deals \(cardsDealt) cards each")
    }
}

#Preview {
    NextDealView(
        dealerName: "Vale",
        isDealerHuman: false,
        playerCount: 3,
        cardsDealt: .constant(7),
        onDeal: {},
        onCancel: {}
    )
    .environment(\.motion, MotionBudget(reduceMotion: false))
}
