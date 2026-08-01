//
//  Motion.swift
//  Named animation curves, so timing is a design decision made once.
//
//  Every curve here is a spring with an explicit duration and damping rather
//  than a bare `.default`, because the whole feel of a card game lives in how
//  cards settle. `Motion.respectingReduceMotion` is the single funnel that
//  honours the accessibility setting — no view should reach for `.animation`
//  directly.
//

import SwiftUI

enum Motion {

    /// A card leaving the hand for the discard pile. Slightly underdamped so it
    /// overshoots and settles — cards have mass.
    static let cardFlight = Animation.spring(duration: 0.42, bounce: 0.22)

    /// A card lifting under the finger. Fast and crisp; any lag here feels broken.
    static let cardLift = Animation.spring(duration: 0.22, bounce: 0.30)
    /// One beat of the well shuffle. Quick and slightly springy — a shuffle is
    /// a flick of the wrist, not a considered move, and at a slower duration the
    /// four beats read as four separate animations rather than one gesture.
    static let shuffleStep = Animation.spring(duration: 0.19, bounce: 0.42)

    /// The hand fan re-flowing after a card leaves.
    static let handReflow = Animation.spring(duration: 0.5, bounce: 0.14)

    /// Dealing. Staggered per card by `dealStagger`.
    static let deal = Animation.spring(duration: 0.55, bounce: 0.18)
    static let dealStagger = 0.055

    /// The tally counting up or down. Deliberately not a spring — a counter
    /// should feel mechanical, not bouncy.
    static let tallyTick = Animation.timingCurve(0.16, 0.9, 0.2, 1.0, duration: 0.55)

    /// A 9 slamming the tally to 99. Violent and short.
    static let slam = Animation.spring(duration: 0.28, bounce: 0.45)

    /// Big narrative beats: the well reveal, an elimination, the win.
    static let drama = Animation.spring(duration: 0.7, bounce: 0.12)
    static let dramaSlow = Animation.timingCurve(0.2, 0.8, 0.1, 1.0, duration: 1.1)

    /// Screen-to-screen. Custom, because the default push is the single most
    /// recognisable "this is a stock app" tell.
    static let screen = Animation.spring(duration: 0.55, bounce: 0.08)

    /// Sheets, banners, and anything that slides in from an edge.
    static let panel = Animation.spring(duration: 0.4, bounce: 0.16)

    /// Ambient loops — the felt sheen, the brass shimmer, a pulsing warning.
    static func breathe(_ period: Double) -> Animation {
        .easeInOut(duration: period).repeatForever(autoreverses: true)
    }

    static func sweep(_ period: Double) -> Animation {
        .linear(duration: period).repeatForever(autoreverses: false)
    }
}

// MARK: - Reduce Motion

/// Reads the accessibility setting once, high in the view tree, and hands it
/// down. Views ask `motion.animation(_:)` instead of using curves directly, so
/// honouring the setting can't be forgotten in one place.
struct MotionBudget {
    var reduceMotion: Bool

    /// The curve to actually use. Under Reduce Motion, movement collapses to a
    /// short cross-fade rather than being removed entirely — state changes still
    /// need to be perceivable.
    func animation(_ animation: Animation) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }

    /// Decorative, never-ending motion is dropped completely under Reduce Motion.
    func ambient(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Scale/offset magnitudes get damped rather than zeroed.
    func displacement(_ value: CGFloat) -> CGFloat {
        reduceMotion ? value * 0.25 : value
    }

    var allowsParallax: Bool { !reduceMotion }
}

private struct MotionBudgetKey: EnvironmentKey {
    static let defaultValue = MotionBudget(reduceMotion: false)
}

extension EnvironmentValues {
    var motion: MotionBudget {
        get { self[MotionBudgetKey.self] }
        set { self[MotionBudgetKey.self] = newValue }
    }
}
