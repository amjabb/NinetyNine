//
//  Palette.swift
//  The game's colour language.
//
//  The table is a dark, desaturated emerald rather than casino green, lit from
//  above so the felt falls off into shadow at the edges. Everything metallic is
//  brass, not yellow — brass has a warm-to-cool gradient across its face, which
//  is what makes gilt read as metal instead of as a flat colour.
//

import SwiftUI

enum Palette {

    // MARK: - The table

    static let feltCore = Color(hex: 0x0C2E26)
    static let feltMid = Color(hex: 0x07211B)
    static let feltEdge = Color(hex: 0x03110E)
    static let feltShadow = Color(hex: 0x010907)

    /// Lit-from-above felt. Off-centre so the highlight sits where a player's
    /// eyes go first, and stretched vertically to suggest a wide table.
    static let feltGradient = RadialGradient(
        colors: [feltCore, feltMid, feltEdge, feltShadow],
        center: UnitPoint(x: 0.5, y: 0.36),
        startRadius: 8,
        endRadius: 620
    )

    // MARK: - Brass

    static let brass = Color(hex: 0xC9992F)
    static let brassLight = Color(hex: 0xF4DE9B)
    static let brassMid = Color(hex: 0xD8AE45)
    static let brassDeep = Color(hex: 0x8A6318)
    static let brassShadow = Color(hex: 0x4A3208)

    /// A metal face needs at least three stops and a hard specular band —
    /// two-stop "gold" gradients always read as plastic.
    static var brassFace: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: brassDeep, location: 0.00),
                .init(color: brassMid, location: 0.22),
                .init(color: brassLight, location: 0.42),
                .init(color: brassLight, location: 0.48),
                .init(color: brass, location: 0.62),
                .init(color: brassDeep, location: 0.88),
                .init(color: brassShadow, location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Sweeping variant for rings and arcs, where a linear ramp would look wrong.
    static var brassRing: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: brassDeep, location: 0.00),
                .init(color: brassLight, location: 0.14),
                .init(color: brass, location: 0.30),
                .init(color: brassShadow, location: 0.46),
                .init(color: brassMid, location: 0.62),
                .init(color: brassLight, location: 0.78),
                .init(color: brass, location: 0.90),
                .init(color: brassDeep, location: 1.00),
            ],
            center: .center
        )
    }

    // MARK: - Cards

    static let cardStock = Color(hex: 0xF8F4E9)
    static let cardStockEdge = Color(hex: 0xE4DCC7)
    static let cardInk = Color(hex: 0x1A1B1E)
    static let cardRed = Color(hex: 0xB8322C)
    static let cardBackField = Color(hex: 0x7A1F2B)
    static let cardBackFieldDeep = Color(hex: 0x4A1019)

    static var cardStockGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFDFAF2), cardStock, cardStockEdge],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Semantic

    static let ivory = Color(hex: 0xF2ECDD)
    static let ivoryDim = Color(hex: 0xA8A08C)
    static let ivoryFaint = Color(hex: 0x6E6857)

    static let safe = Color(hex: 0x4FA97B)
    static let caution = Color(hex: 0xE0A33C)
    static let danger = Color(hex: 0xD6453F)
    static let dangerGlow = Color(hex: 0xFF6B5E)
    static let poison = Color(hex: 0x9B59C4)
    static let negative = Color(hex: 0x4A9BD1)

    /// The tally's colour at a given pressure (0 = miles of room, 1 = pinned at
    /// 99). Interpolated through green → brass → amber → red so the ramp reads
    /// as heat rather than as three discrete states.
    static func tallyColor(pressure: Double, isNegative: Bool) -> Color {
        if isNegative { return negative }
        let p = min(max(pressure, 0), 1)
        switch p {
        case ..<0.45: return blend(safe, brassMid, (p / 0.45))
        case ..<0.78: return blend(brassMid, caution, (p - 0.45) / 0.33)
        default: return blend(caution, danger, (p - 0.78) / 0.22)
        }
    }

    static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let t = min(max(t, 0), 1)
        let ca = a.rgbComponents, cb = b.rgbComponents
        return Color(
            red: ca.r + (cb.r - ca.r) * t,
            green: ca.g + (cb.g - ca.g) * t,
            blue: ca.b + (cb.b - ca.b) * t
        )
    }

    static func suitColor(_ suit: Suit) -> Color {
        suit.isRed ? cardRed : cardInk
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    var rgbComponents: (r: Double, g: Double, b: Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #else
        return (0, 0, 0)
        #endif
    }
}
