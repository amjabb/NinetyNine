//
//  HandoffView.swift
//  The screen that covers the table between players sharing one device.
//
//  This is the whole reason pass-and-play works. It must show *nothing* about
//  the game — not the tally, not the discard, not a card count. Anything visible
//  here is something the previous player can still read over the next player's
//  shoulder, and the table underneath is already showing the previous player's
//  hand.
//
//  So it's fully opaque, not a blur or a translucent material. A blur of a hand
//  is still a hand.
//

import SwiftUI

struct HandoffView: View {
    /// Who should be holding the device now.
    let nextPlayerName: String
    /// Seat number, purely so identical names stay distinguishable.
    let seatNumber: Int
    let totalSeats: Int
    let onReady: () -> Void

    @Environment(\.motion) private var motion
    @State private var hasAppeared = false
    @State private var pulse: CGFloat = 1

    var body: some View {
        ZStack {
            // Fully opaque. Deliberately not `.ultraThinMaterial` — a blurred
            // hand is still a hand.
            Palette.feltShadow
                .ignoresSafeArea()

            // A large, calm card back. The one thing safe to show, because it's
            // the same for everyone.
            CardBackView(isHighlighted: true)
                .frame(width: 150)
                .rotationEffect(.degrees(-6))
                .scaleEffect(pulse)
                .cardShadow(lift: 20)
                .opacity(0.9)
                .offset(y: -110)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    Text("PASS THE DEVICE TO")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(3.5)
                        .foregroundStyle(Palette.brassMid)

                    Text(nextPlayerName)
                        .font(.system(size: 40, weight: .black, design: .serif))
                        .brassFoil()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)

                    Text("Seat \(seatNumber) of \(totalSeats)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                }
                .padding(.bottom, 26)

                Text("Everyone else — look away.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ivoryFaint)
                    .padding(.bottom, 34)

                BrassButton(
                    title: "I'm \(nextPlayerName)",
                    subtitle: "tap to see your hand",
                    icon: "eye.fill",
                    isProminent: true,
                    action: onReady
                )
                .padding(.horizontal, 30)
                .padding(.bottom, 46)
            }
            .tableContentWidth()
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : motion.displacement(18))
        }
        .onAppear {
            withAnimation(motion.animation(Motion.drama)) { hasAppeared = true }
            if let ambient = motion.ambient(Motion.breathe(2.4)) {
                withAnimation(ambient) { pulse = 1.04 }
            }
        }
        // One element to VoiceOver, so it can't read the covered table behind.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pass the device to \(nextPlayerName), seat \(seatNumber) of \(totalSeats)")
        .transition(.opacity)
    }
}

#Preview {
    HandoffView(nextPlayerName: "Priya", seatNumber: 2, totalSeats: 4) {}
        .environment(\.motion, MotionBudget(reduceMotion: false))
}
