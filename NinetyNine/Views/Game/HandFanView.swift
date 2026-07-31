//
//  HandFanView.swift
//  The player's hand, fanned along an arc.
//
//  Cards sit on a circular arc and are rotated tangent to it, which is how a
//  real fanned hand behaves — a flat row of upright cards is the giveaway that
//  nobody thought about it. The fan tightens automatically as the hand grows so
//  a 12-card hand still fits without cards escaping the screen.
//
//  Interaction: tap to play, or drag a card upward past a threshold to throw it.
//  Both routes end in the same call, so there's no second code path to keep
//  correct. A long press is the separate, deliberate gesture for playing several
//  of a rank at once — see SetPlaySheet for why it isn't on the tap path.
//

import SwiftUI

struct HandFanView: View {
    let cards: [Card]
    let playableIDs: Set<Int>
    /// Card the player is being asked to declare for — hidden from the fan while
    /// it's presented in the sheet.
    var suppressedCardID: Int?
    var rejectedCardID: Int?
    var isInteractive: Bool
    /// Staggered entrance for the opening deal.
    var isDealing: Bool
    var onPlay: (Card) -> Void
    /// Long press. Opens the run builder when the card has company of its rank.
    var onLongPress: (Card) -> Void = { _ in }

    @Environment(\.motion) private var motion
    @State private var draggingID: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var pressedID: Int?

    /// Past this much upward travel, releasing plays the card.
    private let throwThreshold: CGFloat = 64

    var body: some View {
        GeometryReader { geometry in
            let layout = FanLayout(
                cardCount: cards.count,
                availableWidth: geometry.size.width,
                availableHeight: geometry.size.height
            )

            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    cardView(card, index: index, layout: layout, container: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        // `.contain` rather than a label on the container: an accessibilityLabel
        // here would replace every card's own label with "Your hand", which both
        // makes the hand unusable with VoiceOver and hides the cards from UI
        // tests. Each card describes itself.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your hand")
    }

    // MARK: - One card

    @ViewBuilder
    private func cardView(_ card: Card, index: Int, layout: FanLayout, container: CGSize) -> some View {
        let placement = layout.placement(at: index)
        let isPlayable = playableIDs.contains(card.id)
        let isDragging = draggingID == card.id
        let isRejected = rejectedCardID == card.id
        let isPressed = pressedID == card.id
        let isSuppressed = suppressedCardID == card.id

        // How far into the throw the drag is, 0...1 — drives the lift preview.
        let throwProgress = isDragging ? min(1, max(0, -dragOffset.height / throwThreshold)) : 0
        let lift = isPressed || isDragging ? 1.0 : 0.0

        CardFaceView(card: card, isPlayable: isPlayable)
            .frame(width: layout.cardWidth)
            .cardShadow(lift: motion.displacement(10 * lift + 14 * throwProgress))
            .rotationEffect(.degrees(isDragging ? placement.angle * 0.25 : placement.angle))
            .scaleEffect(isDragging ? 1.10 : (isPressed ? 1.05 : 1.0), anchor: .bottom)
            .offset(
                x: placement.x + (isDragging ? dragOffset.width : 0),
                y: placement.y
                    + (isDragging ? dragOffset.height : 0)
                    - motion.displacement(isPressed ? 22 : 0)
            )
            // A dead card that's just been tapped shakes rather than moving.
            .modifier(ShakeEffect(shakes: isRejected ? 3 : 0))
            .opacity(isSuppressed ? 0 : 1)
            .zIndex(isDragging ? 1_000 : Double(index))
            .allowsHitTesting(isInteractive && !isSuppressed)
            // Order matters: the long press has to be recognised before the
            // drag, or lifting a card to throw it would start a 0.4s timer that
            // fires the moment the drag settles.
            .onLongPressGesture(minimumDuration: 0.4) { onLongPress(card) }
            .gesture(dragGesture(for: card, isPlayable: isPlayable))
            .onTapGesture { onPlay(card) }
            // Stable identity for UI tests, and a value VoiceOver can read to
            // answer "can I play this?" without trial and error.
            .accessibilityIdentifier("hand-card-\(card.id)")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isPlayable ? "Playable" : "Not playable")
            // Deal-in: each card arrives from the deck position, staggered.
            .offset(y: isDealing ? motion.displacement(340) : 0)
            .opacity(isDealing ? 0 : (isSuppressed ? 0 : 1))
            .animation(
                motion.animation(Motion.deal).delay(isDealing ? 0 : Double(index) * Motion.dealStagger),
                value: isDealing
            )
            .animation(motion.animation(Motion.handReflow), value: cards.count)
            .animation(motion.animation(Motion.cardLift), value: isPressed)
            .animation(motion.animation(Motion.cardLift), value: isDragging)
    }

    private func dragGesture(for card: Card, isPlayable: Bool) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if draggingID != card.id {
                    draggingID = card.id
                    if isPlayable {
                        Haptics.shared.play(.cardLift)
                    }
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let travelled = -value.translation.height
                draggingID = nil
                withAnimation(motion.animation(Motion.handReflow)) { dragOffset = .zero }
                if travelled > throwThreshold {
                    onPlay(card)
                }
            }
    }
}

// MARK: - Fan geometry

/// Places cards along a shallow arc, sized so the whole fan is guaranteed to fit
/// the width it's given.
///
/// The card width is *derived* from the space available and the number of cards
/// rather than picked and hoped for — an earlier version chose a width first and
/// let a 6-card hand overflow the screen by 37pt on each side.
struct FanLayout {
    let cardCount: Int
    let cardWidth: CGFloat
    /// Horizontal distance between adjacent card centres.
    private let step: CGFloat
    private let anglePerCard: Double
    private let arcRadius: CGFloat

    init(cardCount: Int, availableWidth: CGFloat, availableHeight: CGFloat) {
        self.cardCount = cardCount
        let count = max(1, cardCount)

        // Larger hands overlap more heavily, so the fan tightens instead of
        // spilling. `stepFactor` is the fraction of a card width between centres.
        let stepFactor: CGFloat = count <= 7 ? 0.62 : 0.46

        // Solve for the width that makes the fan exactly fit:
        //   cardWidth + (count - 1) * stepFactor * cardWidth <= availableWidth
        // Rotation adds a little to each card's bounding box, hence the 0.93.
        let fitted = availableWidth * 0.93 / (1 + stepFactor * CGFloat(count - 1))
        // Then clamp: a floor keeps cards tappable, a ceiling stops a 5-card hand
        // from looking like a billboard. Height is also respected so the fan
        // never overflows vertically.
        let heightLimited = availableHeight * 0.82 * cardAspectRatio
        self.cardWidth = min(max(min(fitted, heightLimited), 40), 84)
        self.step = self.cardWidth * stepFactor

        let totalSpread: Double
        switch count {
        case 0...5: totalSpread = 18
        case 6...8: totalSpread = 26
        case 9...10: totalSpread = 32
        default: totalSpread = 38
        }
        self.anglePerCard = count > 1 ? totalSpread / Double(count - 1) : 0
        // A gentle arc: the outermost cards sit ~12pt lower than the centre ones,
        // like a hand actually held in the fingers.
        self.arcRadius = self.cardWidth * 4.2
    }

    struct Placement {
        var x: CGFloat
        var y: CGFloat
        var angle: Double
    }

    func placement(at index: Int) -> Placement {
        guard cardCount > 0 else { return Placement(x: 0, y: 0, angle: 0) }
        let middle = Double(cardCount - 1) / 2
        let offsetFromMiddle = Double(index) - middle
        let angle = offsetFromMiddle * anglePerCard
        let radians = angle * .pi / 180

        return Placement(
            x: CGFloat(offsetFromMiddle) * step,
            // Shift the whole arc up by its own depth so the *lowest* card sits on
            // the frame's bottom edge instead of hanging past it.
            y: (1 - cos(radians)) * arcRadius - maxArcDrop,
            angle: angle
        )
    }

    /// How far below the centre card the outermost cards fall.
    var maxArcDrop: CGFloat {
        guard cardCount > 1 else { return 0 }
        let halfSpread = anglePerCard * Double(cardCount - 1) / 2
        return (1 - cos(halfSpread * .pi / 180)) * arcRadius
    }

    /// Total width the fan will occupy, for callers that need to verify the fit.
    var totalWidth: CGFloat {
        cardWidth + step * CGFloat(max(0, cardCount - 1))
    }
}

// MARK: - Shake

/// A quick horizontal shake, for rejecting an illegal tap. Uses a sine so the
/// motion decays naturally into place rather than snapping.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: sin(shakes * .pi * 2) * 8, y: 0)
        )
    }
}
