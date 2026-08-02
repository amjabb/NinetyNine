//
//  DiscardTrailView.swift
//  The last few cards played, so you don't have to remember them.
//
//  At a table the discard pile is right there and you can lift the corner of it.
//  On a phone only the top card was visible, which quietly made 99 a memory test
//  it was never meant to be: whether a 10 has gone, how many 9s are left, what
//  the last player was forced to dump — all of it decides a play, and all of it
//  was gone the moment the next card landed.
//
//  The active card stays full strength. Everything behind it fades back in
//  order, so which one is live is never in doubt.
//

import SwiftUI

struct DiscardTrailView: View {
    /// Oldest first, as the engine keeps it.
    let pile: [Card]
    var cardWidth: CGFloat

    /// How many to show at all. Beyond a few back it stops being information
    /// and starts being clutter — and this sits next to the tally, which must
    /// stay the most readable thing on the table.
    private let depth = 4

    @Environment(\.motion) private var motion

    /// Newest first — the order you'd lift them off the pile in.
    private var trail: [Card] { pile.reversed() }

    private struct Layer {
        var index: Int
        var card: Card
    }

    private var shown: [Layer] {
        trail.prefix(depth).enumerated().map { Layer(index: $0.offset, card: $0.element) }
    }

    /// One card in the stack. Split out because the compiler gives up trying to
    /// type-check this many chained modifiers inside a ForEach.
    private func layer(_ entry: Layer) -> some View {
        let step = CGFloat(entry.index)
        let isLive = entry.index == 0
        let fade: Double = isLive ? 1 : Swift.max(0.22, 0.5 - Double(step) * 0.09)
        return CardFaceView(card: entry.card)
            .frame(width: cardWidth * (1 - step * 0.07))
            .cardShadow(lift: isLive ? 10 : 2)
            .rotationEffect(.degrees(isLive ? -7 : -7 + Double(step) * 5))
            .opacity(fade)
            .saturation(isLive ? 1 : 0.4)
            .offset(x: step * cardWidth * 0.3, y: step * cardWidth * 0.12)
            .zIndex(Double(depth - entry.index))
            .accessibilityLabel(
                isLive
                    ? "Top of the discard pile, \(entry.card.accessibleName)"
                    : "\(entry.index + 1) back, \(entry.card.accessibleName)"
            )
    }

    var body: some View {
        // A stack, not a row. The played card stays exactly where it always was,
        // and the ones before it peek out behind — an earlier version laid them
        // out side by side and covered the tally, which is the one thing on this
        // screen that must never be obscured.
        ZStack(alignment: .topLeading) {
            ForEach(shown.reversed(), id: \.card.id) { entry in
                layer(entry)
            }
        }
        .frame(width: cardWidth * 1.9, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discard-trail")
        .accessibilityLabel("Cards played, newest first")
        .animation(motion.animation(Motion.cardFlight), value: pile.count)
    }
}
