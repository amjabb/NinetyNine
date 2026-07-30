//
//  Layout.swift
//  Size-class handling.
//
//  The game is composed for a phone: a gauge you read at a glance and a fan you
//  reach with a thumb. Stretched to a 13" iPad that composition falls apart —
//  the wordmark becomes a speck and the buttons become runways.
//
//  Rather than pretend, the content is held to a phone-shaped measure and
//  centred, with the felt filling the rest of the screen. That's a deliberate
//  look (and a common one for card games) instead of an accidental one.
//

import SwiftUI

enum Layout {
    /// The widest the interactive content is allowed to get. Roughly the width
    /// of a large phone, which is what the layout was designed against.
    static let maxContentWidth: CGFloat = 540
}

extension View {
    /// Constrain to a phone-shaped measure and centre horizontally. The caller's
    /// background is expected to fill the full screen behind it.
    func tableContentWidth() -> some View {
        frame(maxWidth: Layout.maxContentWidth)
            .frame(maxWidth: .infinity)
    }
}
