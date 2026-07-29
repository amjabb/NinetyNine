//
//  Typography.swift
//  Type is doing real work here, so it gets real rules.
//
//  Three voices, no more:
//    * Display — New York (system serif) at heavy weights, tightly tracked.
//      Used for the wordmark, the tally, and card indices. Serif at scale is
//      what stops the game reading as a utility app.
//    * Numeric — rounded, monospaced digits. Any number that *changes* must not
//      reflow the layout while it does.
//    * Voice — the default text face for prose, at a generous line height.
//

import SwiftUI

enum Typography {

    // MARK: Display

    static func display(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// The wordmark. Heavy serif, tracked in tight so "99" reads as a mark
    /// rather than as two digits.
    static let wordmark = display(84, weight: .black)
    static let title = display(30, weight: .bold)
    static let sectionTitle = display(19, weight: .semibold)

    // MARK: Numeric

    /// Any tally-like number. Monospaced digits are non-negotiable for a value
    /// that ticks — proportional digits make the whole gauge jitter.
    static func tally(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
            .monospacedDigit()
    }

    static func counter(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    // MARK: Card faces

    /// Card corner indices. Serif, because that's what a real card uses, and it
    /// keeps the 6/9 and 10 legible at small sizes.
    static func cardIndex(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    // MARK: Voice

    static let body = Font.system(size: 16, weight: .regular)
    static let bodyEmphasised = Font.system(size: 16, weight: .semibold)
    static let caption = Font.system(size: 13, weight: .medium)

    /// Small, wide, uppercase. For labels that sit next to a value and must not
    /// compete with it.
    static let label = Font.system(size: 11, weight: .semibold)
}

// MARK: - Reusable text treatments

extension View {
    /// Small-caps-style label: uppercase, widely tracked, dimmed.
    func labelStyle(_ color: Color = Palette.ivoryDim) -> some View {
        self
            .font(Typography.label)
            .tracking(1.6)
            .foregroundStyle(color)
            .textCase(.uppercase)
    }

    /// Brass foil fill with an inner shadow, for headings and the wordmark.
    func brassFoil() -> some View {
        self
            .foregroundStyle(Palette.brassFace)
            .shadow(color: Palette.brassShadow.opacity(0.6), radius: 0, x: 0, y: 1)
            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
    }
}
