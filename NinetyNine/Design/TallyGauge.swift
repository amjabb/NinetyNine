//
//  TallyGauge.swift
//  The centre of the table and the centre of the game.
//
//  Everything a player needs to judge their next move is here: the number, how
//  close it is to 99, which direction play is moving, whether a suit is locked,
//  and whether the next card is forced negative. It is deliberately the largest
//  thing on screen.
//

import SwiftUI

struct TallyGauge: View {
    let tally: Int
    /// The value before the last change — drives the delta chip and the sweep.
    var previousTally: Int?
    var suitLock: Suit?
    var isForcedNegative: Bool = false
    var isClockwise: Bool = true
    /// Set while a 9 is landing, for the slam treatment.
    var isSlamming: Bool = false

    @Environment(\.motion) private var motion
    @State private var shimmerPhase: Double = 0
    /// Drives the travelling direction arrow. Its own phase, not the shimmer's:
    /// the shimmer breathes in and out, and an arrow that ran backwards half the
    /// time would say the opposite of what it means.
    @State private var arrowPhase: Double = 0

    private var pressure: Double {
        tally > 0 ? min(1, Double(tally) / 99.0) : 0
    }

    private var accent: Color {
        Palette.tallyColor(pressure: pressure, isNegative: tally < 0)
    }

    /// The arc sweeps 270°, leaving a gap at the bottom where the delta chip and
    /// the direction indicator live.
    private let sweep: Double = 270
    private let startAngle: Double = 135

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let ringWidth = side * 0.075

            ZStack {
                // Track.
                GaugeArc(startAngle: startAngle, sweep: sweep, progress: 1)
                    .stroke(Color.black.opacity(0.45), style: .init(lineWidth: ringWidth, lineCap: .round))

                // The ring itself points the way play is going.
                DirectionRing(
                    startAngle: startAngle,
                    sweep: sweep,
                    isClockwise: isClockwise,
                    phase: arrowPhase
                )
                .stroke(
                    // Bright and reasonably heavy: at brass-on-brass they
                    // disappeared into the ring they're drawn on.
                    Palette.brassLight.opacity(0.95),
                    style: .init(lineWidth: ringWidth * 0.34, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: Palette.feltShadow.opacity(0.8), radius: 1)
                .frame(width: side, height: side)

                // Tick marks every 10, longer at 50, longest at 99.
                GaugeTicks(startAngle: startAngle, sweep: sweep)
                    .stroke(Palette.ivory.opacity(0.20), lineWidth: max(1, side * 0.005))
                    .frame(width: side, height: side)

                // Filled progress.
                GaugeArc(startAngle: startAngle, sweep: sweep, progress: pressure)
                    .stroke(
                        AngularGradient(
                            colors: [accent.opacity(0.55), accent, Palette.brassLight.opacity(0.9)],
                            center: .center,
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(startAngle + sweep * pressure)
                        ),
                        style: .init(lineWidth: ringWidth, lineCap: .round)
                    )
                    .shadow(color: accent.opacity(0.7), radius: side * 0.05)
                    .animation(motion.animation(isSlamming ? Motion.slam : Motion.tallyTick), value: pressure)

                // Negative territory: the arc runs the other way in cool blue,
                // so a negative tally is unmistakable at a glance.
                if tally < 0 {
                    GaugeArc(startAngle: startAngle, sweep: -sweep, progress: min(1, Double(-tally) / 30.0))
                        .stroke(
                            Palette.negative,
                            style: .init(lineWidth: ringWidth, lineCap: .round)
                        )
                        .shadow(color: Palette.negative.opacity(0.8), radius: side * 0.05)
                        .animation(motion.animation(Motion.tallyTick), value: tally)
                }

                // Brass bezel, inside and out.
                Circle()
                    .strokeBorder(Palette.brassRing, lineWidth: max(1, side * 0.011))
                    .frame(width: side, height: side)
                    .opacity(0.75)

                Circle()
                    .strokeBorder(Palette.brassRing, lineWidth: max(1, side * 0.008))
                    .frame(width: side - ringWidth * 2.6, height: side - ringWidth * 2.6)
                    .opacity(0.5)

                // The number.
                centreStack(side: side)

                // Ceiling marker at 99.
                CeilingMarker(angle: startAngle + sweep)
                    .frame(width: side, height: side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                // Danger halo — a slow pulse once the tally is genuinely lethal.
                if pressure > 0.88 {
                    Circle()
                        .stroke(Palette.dangerGlow.opacity(0.5), lineWidth: side * 0.02)
                        .frame(width: side * (1 + 0.04 * shimmerPhase), height: side * (1 + 0.04 * shimmerPhase))
                        .opacity(0.35 + 0.4 * (1 - shimmerPhase))
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                if let ambient = motion.ambient(Motion.breathe(1.1)) {
                    withAnimation(ambient) { shimmerPhase = 1 }
                }
                // One way, forever. Reduce Motion leaves it parked, which is
                // fine — the wording underneath still says which way play goes.
                if let travel = motion.ambient(
                    .linear(duration: 3.4).repeatForever(autoreverses: false)
                ) {
                    withAnimation(travel) { arrowPhase = 1 }
                }
            }
            .onChange(of: isClockwise) { _, _ in
                // Restart so the reversal reads as a reversal rather than the
                // arrow continuing on its way.
                arrowPhase = 0
                guard let travel = motion.ambient(
                    .linear(duration: 3.4).repeatForever(autoreverses: false)
                ) else { return }
                withAnimation(travel) { arrowPhase = 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tally")
        .accessibilityValue(accessibilityValue)
    }

    // MARK: Centre

    @ViewBuilder
    private func centreStack(side: CGFloat) -> some View {
        VStack(spacing: side * 0.005) {
            if isForcedNegative {
                Text("Forced negative")
                    .font(.system(size: side * 0.058, weight: .bold))
                    .foregroundStyle(Palette.negative)
                    .tracking(0.6)
                    .transition(.opacity)
            } else if let suitLock {
                HStack(spacing: side * 0.028) {
                    // The pip carries the information; the word is just a label,
                    // so the pip is the thing that gets bigger. At parity with
                    // the text it was the hardest-working glyph on the table and
                    // the easiest to miss.
                    SuitShape(suit: suitLock)
                        .fill(suitLock.isRed ? Palette.dangerGlow : Palette.ivory)
                        .frame(width: side * 0.115, height: side * 0.115)
                        .shadow(
                            color: (suitLock.isRed ? Palette.dangerGlow : Palette.ivory).opacity(0.5),
                            radius: side * 0.02
                        )
                    Text("Locked")
                        .font(.system(size: side * 0.056, weight: .bold))
                        .foregroundStyle(Palette.ivory.opacity(0.85))
                }
                .transition(.opacity)
            } else {
                Text("Tally")
                    .font(.system(size: side * 0.055, weight: .semibold))
                    .tracking(side * 0.012)
                    .foregroundStyle(Palette.ivoryDim)
                    .textCase(.uppercase)
            }

            Text("\(tally)")
                .font(Typography.tally(side * 0.36))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.55), radius: side * 0.04)
                .contentTransition(.numericText(value: Double(tally)))
                .animation(motion.animation(isSlamming ? Motion.slam : Motion.tallyTick), value: tally)

            // Headroom: the single most useful derived number in the game.
            if tally >= 0 {
                Text(headroomText)
                    .font(Typography.counter(side * 0.062, weight: .semibold))
                    .foregroundStyle(pressure > 0.88 ? Palette.dangerGlow : Palette.ivoryDim)
            } else {
                Text("below zero")
                    .font(.system(size: side * 0.052, weight: .semibold))
                    .foregroundStyle(Palette.negative.opacity(0.9))
            }

        }
    }

    private var headroomText: String {
        let room = 99 - tally
        if room == 0 { return "no room left" }
        if room == 1 { return "1 to spare" }
        return "\(room) to spare"
    }

    private var accessibilityValue: String {
        var parts = ["\(tally)"]
        if tally >= 0 { parts.append("\(99 - tally) below the ceiling") }
        if let suitLock { parts.append("suit locked to \(suitLock.displayName)") }
        if isForcedNegative { parts.append("the next card is forced negative") }
        parts.append(isClockwise ? "play is clockwise" : "play is counter-clockwise")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Arc geometry

private struct GaugeArc: Shape {
    var startAngle: Double
    var sweep: Double
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2 - min(rect.width, rect.height) * 0.0375
        guard progress > 0.0001 else { return path }
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweep * progress),
            clockwise: sweep < 0
        )
        return path
    }
}

/// Arrowheads set into the gauge's ring, all pointing the way play is going.
///
/// Not a label and not one moving marker: the ring *becomes* directional, the
/// way a one-way street is marked. Direction is a property of the circle the
/// tally already lives on, so drawing it as part of that circle says it without
/// anybody having to read a word — and it stays legible at a glance from across
/// a table, which "CCW" in a corner never did.
///
/// Each head is a shallow V sitting on the arc: apex a little ahead along the
/// direction of travel, tails a little behind and to either side of the ring's
/// width. They drift slowly, because a still arrow is read once and then stops
/// being seen.
private struct DirectionRing: Shape {
    var startAngle: Double
    var sweep: Double
    var isClockwise: Bool
    /// 0...1. Slides the whole set along the arc.
    var phase: Double
    /// How many heads to space around the sweep.
    var count: Int = 7

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let radius = side / 2 - side * 0.0375
        let centre = CGPoint(x: rect.midX, y: rect.midY)

        // Half the angular length of one head, and how far its tails sit either
        // side of the ring's centre line.
        let halfSpan = 5.5
        let spread = side * 0.019
        let direction: Double = isClockwise ? 1 : -1

        let step = sweep / Double(count)
        for index in 0..<count {
            // Drift by one full gap, so the set flows without ever leaving a
            // hole at either end of the arc.
            let along = Double(index) * step + phase * step
            let centreAngle = startAngle + along.truncatingRemainder(dividingBy: sweep)

            let apex = centreAngle + halfSpan * direction
            let tail = centreAngle - halfSpan * direction

            let apexPoint = point(centre: centre, radius: radius, degrees: apex)
            let outerTail = point(centre: centre, radius: radius + spread, degrees: tail)
            let innerTail = point(centre: centre, radius: radius - spread, degrees: tail)

            path.move(to: outerTail)
            path.addLine(to: apexPoint)
            path.addLine(to: innerTail)
        }
        return path
    }

    private func point(centre: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * Double.pi / 180
        return CGPoint(
            x: centre.x + radius * CGFloat(Foundation.cos(radians)),
            y: centre.y + radius * CGFloat(Foundation.sin(radians))
        )
    }
}

private struct GaugeTicks: Shape {
    var startAngle: Double
    var sweep: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let outer = side / 2 - side * 0.088
        let centre = CGPoint(x: rect.midX, y: rect.midY)

        for value in stride(from: 0, through: 90, by: 10) {
            let fraction = Double(value) / 99.0
            let angle = CGFloat((startAngle + sweep * fraction) * .pi / 180)
            let length = value % 50 == 0 ? side * 0.040 : side * 0.024
            let inner = outer - length
            path.move(to: CGPoint(
                x: centre.x + cos(angle) * inner,
                y: centre.y + sin(angle) * inner
            ))
            path.addLine(to: CGPoint(
                x: centre.x + cos(angle) * outer,
                y: centre.y + sin(angle) * outer
            ))
        }
        return path
    }
}

/// The hard stop at 99, drawn as a brass pin with a label.
private struct CeilingMarker: View {
    let angle: Double

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2 - side * 0.0375
            let radians: CGFloat = angle * .pi / 180
            let position = CGPoint(
                x: geometry.size.width / 2 + cos(radians) * radius,
                y: geometry.size.height / 2 + sin(radians) * radius
            )
            ZStack {
                Circle()
                    .fill(Palette.brassFace)
                    .frame(width: side * 0.055, height: side * 0.055)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                Text("99")
                    .font(.system(size: side * 0.055, weight: .black, design: .serif))
                    .foregroundStyle(Palette.brassLight)
                    .shadow(color: .black.opacity(0.8), radius: 3)
                    // Pushed clear of the arc so the label never sits on the ring.
                    .offset(x: side * 0.095, y: side * 0.068)
            }
            .position(position)
        }
    }
}

// MARK: - Delta chip

/// The floating "+8" / "−10" that rises off the gauge after a play. Small, but
/// it's what makes an arithmetic game feel physical.
struct TallyDeltaChip: View {
    let delta: Int

    private var isPositive: Bool { delta > 0 }

    var body: some View {
        Text(delta == 0 ? "±0" : (isPositive ? "+\(delta)" : "−\(abs(delta))"))
            .font(Typography.counter(22, weight: .black))
            .foregroundStyle(Palette.ivory)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(
                        delta == 0 ? Palette.ivoryFaint
                            : (isPositive ? Palette.danger : Palette.safe)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

#Preview {
    ZStack {
        TableBackground(lockedSuit: .hearts, pressure: 0.95)
        VStack(spacing: 24) {
            TallyGauge(tally: 92, suitLock: .hearts, isClockwise: true).frame(height: 260)
            HStack(spacing: 16) {
                TallyDeltaChip(delta: 8)
                TallyDeltaChip(delta: -10)
                TallyDeltaChip(delta: 0)
            }
        }
        .padding()
    }
}
