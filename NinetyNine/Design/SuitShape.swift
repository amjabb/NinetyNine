//
//  SuitShape.swift
//  Hand-built vector paths for the four suits.
//
//  These are real Bézier outlines rather than text glyphs or SF Symbols, for
//  three reasons: they stay crisp at pip size *and* at watermark size, their
//  proportions are tuned for a card face (a font's ♠ is designed to sit on a
//  text baseline, not to be a pip), and they can be filled with a gradient.
//
//  Every path is authored in the unit square and scaled by the shape's rect, so
//  the same source draws a 9pt pip and a 300pt background watermark.
//

import SwiftUI

struct SuitShape: Shape, Equatable {
    let suit: Suit

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Suits aren't square; inset to the natural aspect of each so a set of
        // pips reads as evenly weighted rather than evenly *boxed*.
        let box = rect.insetBy(
            dx: rect.width * Self.horizontalInset(suit),
            dy: rect.height * Self.verticalInset(suit)
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: box.minX + box.width * x, y: box.minY + box.height * y)
        }

        switch suit {
        case .hearts:
            path.move(to: point(0.50, 1.00))
            path.addCurve(to: point(0.00, 0.30), control1: point(0.48, 0.74), control2: point(0.00, 0.60))
            path.addCurve(to: point(0.36, 0.00), control1: point(0.00, 0.09), control2: point(0.21, 0.00))
            path.addCurve(to: point(0.50, 0.15), control1: point(0.45, 0.00), control2: point(0.50, 0.07))
            path.addCurve(to: point(0.64, 0.00), control1: point(0.50, 0.07), control2: point(0.55, 0.00))
            path.addCurve(to: point(1.00, 0.30), control1: point(0.79, 0.00), control2: point(1.00, 0.09))
            path.addCurve(to: point(0.50, 1.00), control1: point(1.00, 0.60), control2: point(0.52, 0.74))
            path.closeSubpath()

        case .diamonds:
            path.move(to: point(0.50, 0.00))
            path.addCurve(to: point(1.00, 0.50), control1: point(0.66, 0.18), control2: point(0.86, 0.36))
            path.addCurve(to: point(0.50, 1.00), control1: point(0.86, 0.64), control2: point(0.66, 0.82))
            path.addCurve(to: point(0.00, 0.50), control1: point(0.34, 0.82), control2: point(0.14, 0.64))
            path.addCurve(to: point(0.50, 0.00), control1: point(0.14, 0.36), control2: point(0.34, 0.18))
            path.closeSubpath()

        case .spades:
            // Inverted heart above a flared stem.
            path.move(to: point(0.50, 0.00))
            path.addCurve(to: point(1.00, 0.56), control1: point(0.62, 0.16), control2: point(1.00, 0.34))
            path.addCurve(to: point(0.68, 0.84), control1: point(1.00, 0.74), control2: point(0.86, 0.84))
            path.addCurve(to: point(0.53, 0.77), control1: point(0.61, 0.84), control2: point(0.56, 0.81))
            // Stem, right side down.
            path.addCurve(to: point(0.70, 1.00), control1: point(0.56, 0.87), control2: point(0.62, 0.96))
            path.addLine(to: point(0.30, 1.00))
            path.addCurve(to: point(0.47, 0.77), control1: point(0.38, 0.96), control2: point(0.44, 0.87))
            path.addCurve(to: point(0.32, 0.84), control1: point(0.44, 0.81), control2: point(0.39, 0.84))
            path.addCurve(to: point(0.00, 0.56), control1: point(0.14, 0.84), control2: point(0.00, 0.74))
            path.addCurve(to: point(0.50, 0.00), control1: point(0.00, 0.34), control2: point(0.38, 0.16))
            path.closeSubpath()

        case .clubs:
            let lobe = box.width * 0.30
            // Three lobes.
            path.addEllipse(in: CGRect(
                x: point(0.50, 0.00).x - lobe, y: point(0.50, 0.00).y,
                width: lobe * 2, height: lobe * 2
            ))
            path.addEllipse(in: CGRect(
                x: box.minX, y: point(0.00, 0.44).y,
                width: lobe * 2, height: lobe * 2
            ))
            path.addEllipse(in: CGRect(
                x: box.maxX - lobe * 2, y: point(0.00, 0.44).y,
                width: lobe * 2, height: lobe * 2
            ))
            // Flared stem, drawn last so it unions into the lobes.
            path.move(to: point(0.50, 0.52))
            path.addCurve(to: point(0.72, 1.00), control1: point(0.55, 0.74), control2: point(0.60, 0.92))
            path.addLine(to: point(0.28, 1.00))
            path.addCurve(to: point(0.50, 0.52), control1: point(0.40, 0.92), control2: point(0.45, 0.74))
            path.closeSubpath()
        }

        return path
    }

    private static func horizontalInset(_ suit: Suit) -> CGFloat {
        switch suit {
        case .hearts: return 0.02
        case .diamonds: return 0.14
        case .spades: return 0.05
        case .clubs: return 0.01
        }
    }

    private static func verticalInset(_ suit: Suit) -> CGFloat {
        switch suit {
        case .hearts: return 0.05
        case .diamonds: return 0.01
        case .spades: return 0.02
        case .clubs: return 0.04
        }
    }
}

// MARK: - Pip layouts

/// Where the pips go, in normalised coordinates inside the card's inner panel.
/// These follow the standard three-column / seven-row grid used by real poker
/// decks — which is why an 8 has its two extra pips *between* the rows rather
/// than in a fourth column.
enum PipLayout {

    struct Pip: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        /// Real cards rotate every pip in the lower half by 180°, so the card
        /// reads identically from either end.
        var isInverted: Bool { y > 0.5 }
    }

    static func pips(for rank: Rank) -> [Pip] {
        let coordinates: [(CGFloat, CGFloat)]
        switch rank {
        case .ace:
            coordinates = [(0.5, 0.5)]
        case .two:
            coordinates = [(0.5, 0.0), (0.5, 1.0)]
        case .three:
            coordinates = [(0.5, 0.0), (0.5, 0.5), (0.5, 1.0)]
        case .four:
            coordinates = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]
        case .five:
            coordinates = [(0.0, 0.0), (1.0, 0.0), (0.5, 0.5), (0.0, 1.0), (1.0, 1.0)]
        case .six:
            coordinates = [(0.0, 0.0), (1.0, 0.0), (0.0, 0.5), (1.0, 0.5), (0.0, 1.0), (1.0, 1.0)]
        case .seven:
            coordinates = [
                (0.0, 0.0), (1.0, 0.0), (0.5, 0.25),
                (0.0, 0.5), (1.0, 0.5), (0.0, 1.0), (1.0, 1.0),
            ]
        case .eight:
            coordinates = [
                (0.0, 0.0), (1.0, 0.0), (0.5, 0.25),
                (0.0, 0.5), (1.0, 0.5), (0.5, 0.75),
                (0.0, 1.0), (1.0, 1.0),
            ]
        case .nine:
            coordinates = [
                (0.0, 0.0), (1.0, 0.0),
                (0.0, 1.0 / 3.0), (1.0, 1.0 / 3.0),
                (0.5, 0.5),
                (0.0, 2.0 / 3.0), (1.0, 2.0 / 3.0),
                (0.0, 1.0), (1.0, 1.0),
            ]
        case .ten:
            coordinates = [
                (0.0, 0.0), (1.0, 0.0),
                (0.5, 1.0 / 6.0),
                (0.0, 1.0 / 3.0), (1.0, 1.0 / 3.0),
                (0.0, 2.0 / 3.0), (1.0, 2.0 / 3.0),
                (0.5, 5.0 / 6.0),
                (0.0, 1.0), (1.0, 1.0),
            ]
        case .jack, .queen, .king:
            coordinates = [] // court cards get a panel, not pips
        }
        return coordinates.enumerated().map { Pip(id: $0.offset, x: $0.element.0, y: $0.element.1) }
    }
}
