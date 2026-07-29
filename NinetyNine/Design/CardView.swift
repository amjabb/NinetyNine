//
//  CardView.swift
//  The card itself: face, back, and the flip between them.
//
//  Everything is drawn at runtime from vectors, so one implementation serves the
//  9pt mini-cards in an opponent's fan and the 260pt hero card in the well
//  reveal without a single raster asset.
//

import SwiftUI

/// Standard poker proportions (2.5 × 3.5 in).
let cardAspectRatio: CGFloat = 0.714

// MARK: - Card face

struct CardFaceView: View {
    let card: Card
    /// Dims and desaturates the face for a card that can't legally be played.
    var isPlayable: Bool = true
    /// Draws the value the card will actually contribute, for cards whose value
    /// is contextual (a Queen mid-impersonation, a forced-negative King).
    var valueOverlay: String?

    private var ink: Color { Palette.suitColor(card.suit) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let corner = size.width * 0.075
            // Real cards keep the index small — roughly a fifth of the card's
            // width. Larger than this and it crowds the pip field.
            let indexSize = size.width * 0.215
            let inset = size.width * 0.05

            ZStack {
                // Stock + border. Two nested strokes: a hairline dark edge for
                // the card's cut, and an inner keyline like a real print.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Palette.cardStockGradient)

                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.22), lineWidth: max(0.5, size.width * 0.006))

                RoundedRectangle(cornerRadius: corner * 0.72, style: .continuous)
                    .strokeBorder(ink.opacity(0.10), lineWidth: max(0.5, size.width * 0.004))
                    .padding(inset * 0.72)

                // Central content. The pip field has to clear the corner index
                // strip or the left column collides with it on low ranks; a court
                // panel has no columns, so it can run wider.
                if card.rank.isCourt {
                    CourtPanel(card: card)
                        .padding(.horizontal, size.width * 0.185)
                        .padding(.vertical, size.height * 0.105)
                } else {
                    PipField(card: card)
                        .padding(.horizontal, size.width * 0.26)
                        .padding(.vertical, size.height * 0.115)
                }

                // Corner indices, point-symmetric like a real card.
                CornerIndex(card: card, fontSize: indexSize)
                    .padding(inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                CornerIndex(card: card, fontSize: indexSize)
                    .rotationEffect(.degrees(180))
                    .padding(inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                // Contextual value chip (e.g. "−10" on a King in the forced slot).
                // Centred, because this appears when the player is being asked to
                // judge a value — clarity beats purity here.
                if let valueOverlay {
                    Text(valueOverlay)
                        .font(Typography.counter(size.width * 0.21, weight: .black))
                        .foregroundStyle(Palette.cardStock)
                        .padding(.horizontal, size.width * 0.10)
                        .padding(.vertical, size.width * 0.04)
                        .background(
                            Capsule()
                                .fill(Palette.cardInk.opacity(0.92))
                                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        )
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            // A specular sheen across the stock. Subtle — it's paper, not glass.
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .clear, .black.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.softLight)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .saturation(isPlayable ? 1 : 0.32)
            .opacity(isPlayable ? 1 : 0.55)
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(card.accessibleName)
        .accessibilityHint(isPlayable ? card.rank.abilitySummary : "Not playable right now")
    }
}

// MARK: - Corner index

private struct CornerIndex: View {
    let card: Card
    let fontSize: CGFloat

    var body: some View {
        VStack(spacing: fontSize * 0.02) {
            Text(card.rank.label)
                .font(Typography.cardIndex(fontSize))
                // "10" is two glyphs wide; squeeze it so both indices occupy the
                // same box and the card stays visually balanced.
                .tracking(card.rank == .ten ? -fontSize * 0.09 : 0)
                .foregroundStyle(Palette.suitColor(card.suit))
            SuitShape(suit: card.suit)
                .fill(Palette.suitColor(card.suit))
                .frame(width: fontSize * 0.62, height: fontSize * 0.62)
        }
        .fixedSize()
    }
}

// MARK: - Pip field

/// Suit outlines are taller than they are wide; this keeps pips from being
/// squashed regardless of the field's own aspect.
private let pipAspect: CGFloat = 1.12

private struct PipField: View {
    let card: Card

    var body: some View {
        GeometryReader { geometry in
            let pips = PipLayout.pips(for: card.rank)
            let field = geometry.size

            // The tightest rows in a standard layout (the 9's centre pip, the
            // 10's inter-row pips) sit 1/6 of the field apart, so pip height must
            // stay under that or they collide. Width is capped independently so
            // the three columns keep an even gap.
            let heightLimit = field.height * 0.150
            let widthLimit = field.width * 0.30
            let pipWidth = card.rank == .ace
                ? field.width * 0.62
                : min(widthLimit, heightLimit / pipAspect)
            let pipHeight = pipWidth * pipAspect

            ForEach(pips) { pip in
                SuitShape(suit: card.suit)
                    .fill(Palette.suitColor(card.suit))
                    .frame(width: pipWidth, height: pipHeight)
                    .rotationEffect(.degrees(pip.isInverted ? 180 : 0))
                    .position(
                        x: pipWidth / 2 + pip.x * (geometry.size.width - pipWidth),
                        y: pipHeight / 2 + pip.y * (geometry.size.height - pipHeight)
                    )
            }
        }
    }
}

// MARK: - Court cards

/// Court cards get an engraved monogram panel: one large suit watermark with the
/// rank letter struck over it, framed by a hairline double keyline and a pair of
/// rules. A single strong centred mark reads far better at hand size than a
/// mirrored pair of small ones, which just looks like a doubled letter.
private struct CourtPanel: View {
    let card: Card

    private var ink: Color { Palette.suitColor(card.suit) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let corner = size.width * 0.11

            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(ink.opacity(0.045))

                // Oversized suit watermark, bled off the panel's edges.
                SuitShape(suit: card.suit)
                    .fill(ink.opacity(0.24))
                    .frame(width: size.width * 0.94, height: size.width * 1.05)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

                // Double keyline.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(ink.opacity(0.5), lineWidth: max(0.6, size.width * 0.020))
                RoundedRectangle(cornerRadius: corner * 0.7, style: .continuous)
                    .strokeBorder(ink.opacity(0.22), lineWidth: max(0.5, size.width * 0.011))
                    .padding(size.width * 0.06)

                // Rules above and below the monogram.
                VStack {
                    CourtRule(ink: ink)
                    Spacer()
                    CourtRule(ink: ink)
                }
                .padding(.vertical, size.height * 0.10)
                .padding(.horizontal, size.width * 0.16)

                Text(card.rank.label)
                    .font(.system(size: size.height * 0.40, weight: .black, design: .serif))
                    .foregroundStyle(ink)
                    .shadow(color: Palette.cardStock.opacity(0.7), radius: size.width * 0.03)
            }
        }
    }
}

/// A hairline with a small lozenge at its centre — the simplest ornament that
/// still reads as engraving rather than as a divider.
private struct CourtRule: View {
    let ink: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                Rectangle()
                    .fill(ink.opacity(0.35))
                    .frame(height: max(0.5, width * 0.022))
                SuitDiamond()
                    .fill(ink.opacity(0.5))
                    .frame(width: width * 0.14, height: width * 0.14)
            }
            .frame(height: width * 0.14)
        }
        .frame(height: 6)
    }
}

private struct SuitDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Card back

/// A guilloche rosette in brass over deep crimson. Built from rotated,
/// overlapping ellipses — the same trick used on banknotes, and it produces a
/// moiré-free pattern at any resolution.
struct CardBackView: View {
    /// Set for cards that are hidden but *significant* — a well card, a poisoned
    /// queen — which get a brass edge instead of the plain back.
    var isHighlighted: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let corner = size.width * 0.075
            let inset = size.width * 0.075

            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Palette.cardBackField, Palette.cardBackFieldDeep],
                            center: .center,
                            startRadius: 0,
                            endRadius: size.width
                        )
                    )

                GuillocheRosette()
                    .stroke(Palette.brassMid.opacity(0.5), lineWidth: max(0.4, size.width * 0.006))
                    .padding(inset)

                // Inner keyline frame.
                RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
                    .strokeBorder(Palette.brassMid.opacity(0.65), lineWidth: max(0.5, size.width * 0.010))
                    .padding(inset * 0.7)

                // Centre medallion.
                ZStack {
                    Circle()
                        .fill(Palette.cardBackFieldDeep)
                        .overlay(Circle().strokeBorder(Palette.brassRing, lineWidth: max(0.8, size.width * 0.016)))
                    Text("99")
                        .font(.system(size: size.width * 0.20, weight: .black, design: .serif))
                        .tracking(-size.width * 0.012)
                        .foregroundStyle(Palette.brassFace)
                }
                .frame(width: size.width * 0.40, height: size.width * 0.40)

                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? AnyShapeStyle(Palette.brassRing) : AnyShapeStyle(Color.black.opacity(0.35)),
                        lineWidth: max(0.8, size.width * (isHighlighted ? 0.022 : 0.008))
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Overlapping rotated ellipses — a classic guilloche construction.
private struct GuillocheRosette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let petals = 14
        let radiusX = rect.width * 0.50
        let radiusY = rect.height * 0.26

        for index in 0..<petals {
            let angle = Double(index) / Double(petals) * .pi
            var petal = Path(ellipseIn: CGRect(
                x: -radiusX, y: -radiusY,
                width: radiusX * 2, height: radiusY * 2
            ))
            petal = petal.applying(
                CGAffineTransform(rotationAngle: angle)
                    .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))
            )
            path.addPath(petal)
        }
        return path
    }
}

// MARK: - Flippable card

/// A card that can be shown face-down and flipped face-up. The flip swaps
/// content at the halfway point of a 3D rotation, which is what makes it read as
/// one physical object turning rather than two views cross-fading.
struct FlippableCard: View {
    let card: Card
    var isFaceUp: Bool
    var isPlayable: Bool = true
    var isHighlighted: Bool = false

    private var angle: Double { isFaceUp ? 0 : 180 }

    var body: some View {
        ZStack {
            CardFaceView(card: card, isPlayable: isPlayable)
                .opacity(isFaceUp ? 1 : 0)
            CardBackView(isHighlighted: isHighlighted)
                .opacity(isFaceUp ? 0 : 1)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
    }
}

// MARK: - Shadow

extension View {
    /// The shadow a card casts on the felt. Two shadows: a tight contact shadow
    /// and a wide ambient one. A single shadow always looks like a sticker.
    func cardShadow(lift: CGFloat = 0) -> some View {
        self
            .shadow(color: .black.opacity(0.45), radius: 2 + lift * 0.5, x: 0, y: 1 + lift * 0.2)
            .shadow(color: .black.opacity(0.30), radius: 10 + lift * 1.6, x: 0, y: 6 + lift * 0.8)
    }
}

// MARK: - Rank helpers

extension Rank {
    var isCourt: Bool { self == .jack || self == .queen || self == .king }
}

// MARK: - Previews

#Preview("Faces") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(Suit.allCases, id: \.self) { suit in
                HStack(spacing: 6) {
                    ForEach(Rank.allCases, id: \.self) { rank in
                        CardFaceView(card: Card(id: rank.hashValue, rank: rank, suit: suit))
                            .frame(width: 52)
                    }
                }
            }
            HStack(spacing: 12) {
                CardBackView().frame(width: 90)
                CardBackView(isHighlighted: true).frame(width: 90)
                CardFaceView(
                    card: Card(id: 1, rank: .king, suit: .spades),
                    valueOverlay: "−10"
                ).frame(width: 90)
                CardFaceView(
                    card: Card(id: 2, rank: .seven, suit: .hearts),
                    isPlayable: false
                ).frame(width: 90)
            }
        }
        .padding()
    }
    .background(Palette.feltGradient)
}
