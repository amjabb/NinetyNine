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
    @Binding var handSize: Int
    let onDeal: () -> Void
    let onCancel: () -> Void

    @Environment(\.motion) private var motion
    @State private var hasAppeared = false

    private var maxHandSize: Int { Rules.maxHandSize(forPlayerCount: playerCount) }

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
                        title: isDealerHuman ? "Deal \(handSize)" : "Continue",
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
            handSize = min(max(handSize, Rules.minHandSize), maxHandSize)
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
                Text("\(handSize)")
                    .font(Typography.counter(22, weight: .heavy))
                    .foregroundStyle(Palette.brassLight)
            }

            HStack(spacing: 8) {
                stepButton(icon: "minus", enabled: handSize > Rules.minHandSize) {
                    handSize = max(Rules.minHandSize, handSize - 1)
                }
                track
                stepButton(icon: "plus", enabled: handSize < maxHandSize) {
                    handSize = min(maxHandSize, handSize + 1)
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
            ForEach(Rules.minHandSize...12, id: \.self) { value in
                RoundedRectangle(cornerRadius: 3)
                    .fill(value <= handSize
                        ? AnyShapeStyle(Palette.brassFace)
                        : AnyShapeStyle(Color.white.opacity(value <= maxHandSize ? 0.12 : 0.04)))
                    .frame(height: value <= handSize ? 20 : 13)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 26)
        .animation(Motion.panel, value: handSize)
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
        .accessibilityLabel(icon == "plus" ? "Deal one more card" : "Deal one fewer card")
    }

    // MARK: AI dealer

    private var aiChoice: some View {
        VStack(spacing: 6) {
            Text("\(handSize)")
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
        .accessibilityLabel("\(dealerName) deals \(handSize) cards each")
    }
}

#Preview {
    NextDealView(
        dealerName: "Vale",
        isDealerHuman: false,
        playerCount: 3,
        handSize: .constant(7),
        onDeal: {},
        onCancel: {}
    )
    .environment(\.motion, MotionBudget(reduceMotion: false))
}
