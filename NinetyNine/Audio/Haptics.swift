//
//  Haptics.swift
//  Core Haptics patterns, one per game event.
//
//  These are authored patterns rather than UIImpactFeedbackGenerator calls,
//  because the stock generators only offer three intensities and a card game
//  needs texture: a card *flick* is a sharp transient, the tally climbing is a
//  soft continuous swell, a 9 landing is a double-thump. That difference is most
//  of what makes a game feel physical in the hand.
//

import Foundation
import CoreHaptics
import UIKit

@MainActor
final class Haptics {
    static let shared = Haptics()

    var isEnabled: Bool = true

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private init() {
        prepare()
    }

    private func prepare() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // The engine is stopped aggressively by the system; restart it rather
            // than silently losing haptics for the rest of the session.
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { _ in }
            engine.playsHapticsOnly = true
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    // MARK: - Vocabulary

    enum Feedback {
        /// A card leaving the hand — one crisp transient.
        case cardFlick
        /// A card landing on the discard pile, slightly softer than the flick.
        case cardLand
        /// Picking a card up.
        case cardLift
        /// The tally climbing: intensity scales with how close to 99 it gets.
        case tallyClimb(pressure: Double)
        /// The tally dropping — a relieved, downward swell.
        case tallyDrop
        /// A 9 slamming to 99. The heaviest thing in the game.
        case slam
        /// Reaching 100.
        case hundred
        /// A suit lock snapping shut.
        case lock
        /// Turn order reversing.
        case reverse
        /// Snackoo — a triple rattle.
        case snackoo
        /// A queen being exiled.
        case poison
        /// The well card turning over: a long rising tension then a beat.
        case wellReveal
        /// Surviving the well.
        case wellSurvive
        /// Elimination.
        case eliminated
        /// Winning.
        case victory
        /// An illegal tap — a short, blunt refusal.
        case rejected
        /// Your turn beginning.
        case turnStart
        /// Generic UI selection.
        case select
    }

    func play(_ feedback: Feedback) {
        guard isEnabled else { return }
        guard supportsHaptics, let engine else {
            playFallback(feedback)
            return
        }
        do {
            let pattern = try pattern(for: feedback)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            playFallback(feedback)
        }
    }

    // MARK: - Pattern authoring

    private func pattern(for feedback: Feedback) throws -> CHHapticPattern {
        switch feedback {
        case .cardFlick:
            return try CHHapticPattern(events: [transient(at: 0, intensity: 0.55, sharpness: 0.85)], parameters: [])

        case .cardLand:
            return try CHHapticPattern(events: [transient(at: 0, intensity: 0.75, sharpness: 0.45)], parameters: [])

        case .cardLift:
            return try CHHapticPattern(events: [transient(at: 0, intensity: 0.30, sharpness: 0.70)], parameters: [])

        case .tallyClimb(let pressure):
            // The closer to the ceiling, the sharper and stronger the tick — so a
            // dangerous play *feels* dangerous before you read the number.
            let p = min(max(pressure, 0), 1)
            return try CHHapticPattern(events: [
                transient(at: 0, intensity: Float(0.35 + 0.55 * p), sharpness: Float(0.3 + 0.6 * p)),
            ], parameters: [])

        case .tallyDrop:
            return try CHHapticPattern(events: [
                continuous(at: 0, duration: 0.18, intensity: 0.45, sharpness: 0.2),
            ], parameterCurves: [
                CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        .init(relativeTime: 0, value: 0.7),
                        .init(relativeTime: 0.18, value: 0.1),
                    ],
                    relativeTime: 0
                ),
            ])

        case .slam:
            // Two hits: the impact, then the settle. A single event reads as a tap.
            return try CHHapticPattern(events: [
                transient(at: 0, intensity: 1.0, sharpness: 0.9),
                continuous(at: 0.02, duration: 0.20, intensity: 0.8, sharpness: 0.25),
                transient(at: 0.16, intensity: 0.55, sharpness: 0.35),
            ], parameters: [])

        case .hundred:
            return try CHHapticPattern(events: [
                transient(at: 0, intensity: 1.0, sharpness: 1.0),
                transient(at: 0.09, intensity: 0.8, sharpness: 0.8),
                transient(at: 0.18, intensity: 0.9, sharpness: 0.6),
                continuous(at: 0.22, duration: 0.4, intensity: 0.6, sharpness: 0.2),
            ], parameters: [])

        case .lock:
            return try CHHapticPattern(events: [
                transient(at: 0, intensity: 0.6, sharpness: 1.0),
                transient(at: 0.07, intensity: 0.9, sharpness: 0.95),
            ], parameters: [])

        case .reverse:
            return try CHHapticPattern(events: [
                continuous(at: 0, duration: 0.14, intensity: 0.5, sharpness: 0.6),
                continuous(at: 0.16, duration: 0.14, intensity: 0.5, sharpness: 0.3),
            ], parameters: [])

        case .snackoo:
            return try CHHapticPattern(events: [
                transient(at: 0.00, intensity: 0.7, sharpness: 0.8),
                transient(at: 0.08, intensity: 0.8, sharpness: 0.85),
                transient(at: 0.16, intensity: 0.95, sharpness: 0.9),
            ], parameters: [])

        case .poison:
            return try CHHapticPattern(events: [
                continuous(at: 0, duration: 0.32, intensity: 0.5, sharpness: 0.1),
            ], parameterCurves: [
                CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        .init(relativeTime: 0, value: 0.2),
                        .init(relativeTime: 0.16, value: 0.8),
                        .init(relativeTime: 0.32, value: 0.05),
                    ],
                    relativeTime: 0
                ),
            ])

        case .wellReveal:
            // A slow swell that resolves into a single beat — the haptic
            // equivalent of a drum roll.
            return try CHHapticPattern(events: [
                continuous(at: 0, duration: 0.55, intensity: 0.6, sharpness: 0.3),
                transient(at: 0.58, intensity: 1.0, sharpness: 0.8),
            ], parameterCurves: [
                CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        .init(relativeTime: 0, value: 0.05),
                        .init(relativeTime: 0.45, value: 0.85),
                        .init(relativeTime: 0.55, value: 0.3),
                    ],
                    relativeTime: 0
                ),
            ])

        case .wellSurvive:
            return try CHHapticPattern(events: [
                transient(at: 0, intensity: 0.8, sharpness: 0.5),
                transient(at: 0.10, intensity: 0.6, sharpness: 0.7),
                transient(at: 0.19, intensity: 0.45, sharpness: 0.9),
            ], parameters: [])

        case .eliminated:
            return try CHHapticPattern(events: [
                transient(at: 0, intensity: 1.0, sharpness: 0.25),
                continuous(at: 0.05, duration: 0.6, intensity: 0.7, sharpness: 0.1),
            ], parameterCurves: [
                CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        .init(relativeTime: 0, value: 0.9),
                        .init(relativeTime: 0.6, value: 0.0),
                    ],
                    relativeTime: 0
                ),
            ])

        case .victory:
            var events: [CHHapticEvent] = []
            // Rising triple flourish.
            for (index, time) in [0.0, 0.13, 0.26].enumerated() {
                events.append(transient(
                    at: time,
                    intensity: Float(0.6 + Double(index) * 0.13),
                    sharpness: Float(0.4 + Double(index) * 0.2)
                ))
            }
            events.append(continuous(at: 0.32, duration: 0.5, intensity: 0.7, sharpness: 0.35))
            return try CHHapticPattern(events: events, parameters: [])

        case .rejected:
            return try CHHapticPattern(events: [
                transient(at: 0, intensity: 0.5, sharpness: 0.15),
                transient(at: 0.06, intensity: 0.35, sharpness: 0.15),
            ], parameters: [])

        case .turnStart:
            return try CHHapticPattern(events: [
                transient(at: 0, intensity: 0.4, sharpness: 0.5),
                transient(at: 0.11, intensity: 0.55, sharpness: 0.6),
            ], parameters: [])

        case .select:
            return try CHHapticPattern(events: [transient(at: 0, intensity: 0.35, sharpness: 0.6)], parameters: [])
        }
    }

    private func transient(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private func continuous(
        at time: TimeInterval,
        duration: TimeInterval,
        intensity: Float,
        sharpness: Float
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    // MARK: - Fallback

    /// Devices without Core Haptics (and the Simulator) still get *something*,
    /// mapped to the closest stock generator.
    private func playFallback(_ feedback: Feedback) {
        switch feedback {
        case .cardFlick, .cardLift, .select:
            UISelectionFeedbackGenerator().selectionChanged()
        case .cardLand, .lock, .turnStart, .reverse:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .tallyClimb, .tallyDrop, .snackoo, .poison, .wellReveal:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .slam, .hundred, .eliminated:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .wellSurvive, .victory:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .rejected:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
