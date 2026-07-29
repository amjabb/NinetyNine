//
//  OpponentSeatView.swift
//  One opponent, as seen across the table.
//
//  Everything you're allowed to know about an opponent is here and nothing you
//  aren't: card count, well pips remaining, poisoned queens, skip debt, and
//  whether they're thinking. Their actual cards stay face down.
//

import SwiftUI

struct OpponentSeatView: View {
    let player: PlayerState
    var isCurrent: Bool
    var isThinking: Bool
    /// Compact form for tables with four or more opponents.
    var isCompact: Bool = false

    @Environment(\.motion) private var motion
    @State private var thinkingSweep: Double = 0

    private var ringSize: CGFloat { isCompact ? 44 : 54 }

    var body: some View {
        VStack(spacing: isCompact ? 3 : 5) {
            avatar
            name
            if !player.isEliminated {
                indicators
            }
        }
        .opacity(player.isEliminated ? 0.35 : 1)
        .saturation(player.isEliminated ? 0 : 1)
        .animation(motion.animation(Motion.drama), value: player.isEliminated)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Avatar

    private var avatar: some View {
        ZStack {
            // Fanned card backs behind the avatar, count-accurate up to five —
            // an instant read on how loaded they are.
            ForEach(0..<min(player.hand.count, 5), id: \.self) { index in
                CardBackView()
                    .frame(width: ringSize * 0.46)
                    .rotationEffect(.degrees(Double(index - 2) * 9))
                    .offset(y: -ringSize * 0.30)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.feltCore, Palette.feltEdge],
                        center: UnitPoint(x: 0.35, y: 0.25),
                        startRadius: 1,
                        endRadius: ringSize
                    )
                )
                .frame(width: ringSize, height: ringSize)

            // Monogram.
            Text(String(player.name.prefix(1)))
                .font(.system(size: ringSize * 0.42, weight: .bold, design: .serif))
                .foregroundStyle(player.isEliminated ? Palette.ivoryFaint : Palette.ivory)

            // Seat ring: brass when it's their turn, dim otherwise.
            Circle()
                .strokeBorder(
                    isCurrent ? AnyShapeStyle(Palette.brassRing) : AnyShapeStyle(Palette.ivoryFaint.opacity(0.5)),
                    lineWidth: isCurrent ? 2.5 : 1.2
                )
                .frame(width: ringSize, height: ringSize)

            // Thinking indicator: a brass arc sweeping the ring.
            if isThinking {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Palette.brassLight, style: .init(lineWidth: 2.5, lineCap: .round))
                    .frame(width: ringSize + 7, height: ringSize + 7)
                    .rotationEffect(.degrees(thinkingSweep))
                    .onAppear {
                        guard let ambient = motion.ambient(Motion.sweep(0.9)) else { return }
                        withAnimation(ambient) { thinkingSweep = 360 }
                    }
                    .onDisappear { thinkingSweep = 0 }
            }

            if player.isEliminated {
                Image(systemName: "xmark")
                    .font(.system(size: ringSize * 0.44, weight: .heavy))
                    .foregroundStyle(Palette.danger)
            }
        }
        .frame(width: ringSize + 10, height: ringSize + 10)
        .shadow(color: isCurrent ? Palette.brass.opacity(0.5) : .clear, radius: 10)
    }

    // MARK: Name + count

    private var name: some View {
        HStack(spacing: 4) {
            Text(player.name)
                .font(.system(size: isCompact ? 11 : 13, weight: .semibold))
                .foregroundStyle(isCurrent ? Palette.brassLight : Palette.ivory.opacity(0.85))
                .lineLimit(1)
            if !player.isEliminated {
                Text("\(player.hand.count)")
                    .font(Typography.counter(isCompact ? 10 : 11, weight: .bold))
                    .foregroundStyle(Palette.ivoryDim)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.black.opacity(0.35)))
            }
        }
    }

    // MARK: Indicators

    private var indicators: some View {
        HStack(spacing: 5) {
            // Well pips: two dots, filled while unspent. The single most useful
            // thing to know about an opponent's survival odds.
            HStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(index < player.well.count ? Palette.brassMid : Palette.ivoryFaint.opacity(0.3))
                        .frame(width: 5, height: 5)
                        .overlay(
                            Circle().strokeBorder(Palette.brassDeep.opacity(0.6), lineWidth: 0.5)
                        )
                }
            }

            if !player.poisonPile.isEmpty {
                HStack(spacing: 1) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 7, weight: .bold))
                    Text("\(player.poisonPile.count)")
                        .font(Typography.counter(9, weight: .bold))
                }
                .foregroundStyle(Palette.poison)
            }

            if player.owesExtraPlay {
                Text("×2")
                    .font(Typography.counter(9, weight: .heavy))
                    .foregroundStyle(Palette.caution)
            }
        }
        .frame(height: 10)
    }

    private var accessibilityDescription: String {
        if player.isEliminated { return "\(player.name), eliminated" }
        var parts = ["\(player.name), \(player.hand.count) cards"]
        parts.append("\(player.well.count) well \(player.well.count == 1 ? "card" : "cards") left")
        if !player.poisonPile.isEmpty { parts.append("\(player.poisonPile.count) poisoned queens") }
        if player.owesExtraPlay { parts.append("owes two plays") }
        if isCurrent { parts.append("their turn") }
        return parts.joined(separator: ", ")
    }
}
