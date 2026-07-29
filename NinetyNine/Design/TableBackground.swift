//
//  TableBackground.swift
//  The felt the whole game sits on.
//
//  Three layers, in order: a lit radial gradient, a procedurally generated
//  fibre-noise texture (tiled, generated once, cached), and a vignette. The
//  noise is what stops a large flat gradient from banding on OLED — and it's
//  what makes the surface read as *cloth*.
//

import SwiftUI
import CoreMotion

struct TableBackground: View {
    /// A suit watermark shown while a suit lock is active.
    var lockedSuit: Suit?
    /// 0...1 — drives how much red bleeds into the table edges as the tally
    /// climbs. Tension you can feel before you read the number.
    var pressure: Double = 0

    @Environment(\.motion) private var motion
    @StateObject private var tilt = TiltProvider()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.feltGradient
                    .ignoresSafeArea()

                // Cloth fibre.
                FeltTexture()
                    .opacity(0.5)
                    .blendMode(.overlay)
                    .ignoresSafeArea()

                // Heat at the edges as the tally approaches 99.
                RadialGradient(
                    colors: [.clear, Palette.danger.opacity(0.30 * pressureCurve)],
                    center: .center,
                    startRadius: geometry.size.width * 0.20,
                    endRadius: geometry.size.width * 1.05
                )
                .blendMode(.plusLighter)
                .ignoresSafeArea()
                .animation(motion.animation(Motion.tallyTick), value: pressure)

                // Suit-lock watermark, parallaxed against the felt so the table
                // has a sense of depth when the device moves.
                if let lockedSuit {
                    SuitShape(suit: lockedSuit)
                        .fill(
                            LinearGradient(
                                colors: [Palette.ivory.opacity(0.09), Palette.ivory.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: geometry.size.width * 0.78, height: geometry.size.width * 0.78)
                        .offset(
                            x: motion.allowsParallax ? tilt.offset.width * 14 : 0,
                            y: (motion.allowsParallax ? tilt.offset.height * 14 : 0) - geometry.size.height * 0.06
                        )
                        .transition(.scale(scale: 1.4).combined(with: .opacity))
                        .animation(motion.animation(Motion.drama), value: lockedSuit)
                }

                // Vignette. Always last, always subtle.
                RadialGradient(
                    colors: [.clear, .clear, .black.opacity(0.55)],
                    center: .center,
                    startRadius: geometry.size.width * 0.28,
                    endRadius: geometry.size.width * 1.0
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .onAppear { if motion.allowsParallax { tilt.start() } }
            .onDisappear { tilt.stop() }
        }
        .ignoresSafeArea()
    }

    /// Bias the heat toward the top of the range — the table shouldn't glow red
    /// at a tally of 40.
    private var pressureCurve: Double {
        let p = min(max(pressure, 0), 1)
        return p * p * p
    }
}

// MARK: - Felt texture

/// A tiled, cached noise bitmap. Generated once per process at a small size and
/// stretched by the tiling, which costs essentially nothing to draw.
private struct FeltTexture: View {
    var body: some View {
        if let image = FeltTextureRenderer.shared.image {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
        } else {
            Color.clear
        }
    }
}

private final class FeltTextureRenderer {
    static let shared = FeltTextureRenderer()
    let image: UIImage?

    private init() {
        let side = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        // Deterministic noise, so the texture is identical every launch.
        var generator = SeededGenerator(seed: 0x9E37_79B9)
        image = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))

            // Short directional strokes read as woven fibre; pure per-pixel
            // noise reads as television static.
            cgContext.setLineWidth(0.7)
            for _ in 0..<2600 {
                let x = Double(generator.next() % UInt64(side))
                let y = Double(generator.next() % UInt64(side))
                let horizontal = generator.next() % 2 == 0
                let length = 1.0 + Double(generator.next() % 3)
                let bright = Double(generator.next() % 100) / 100.0
                let white = bright > 0.5 ? 0.72 : 0.28
                cgContext.setStrokeColor(UIColor(white: white, alpha: 0.16).cgColor)
                cgContext.move(to: CGPoint(x: x, y: y))
                cgContext.addLine(to: CGPoint(
                    x: x + (horizontal ? length : 0),
                    y: y + (horizontal ? 0 : length)
                ))
                cgContext.strokePath()
            }
        }
    }
}

// MARK: - Device tilt

/// Feeds a normalised −1...1 tilt for parallax. Silently no-ops on hardware
/// without a device-motion sensor (including the Simulator), so callers never
/// need to branch.
@MainActor
final class TiltProvider: ObservableObject {
    @Published var offset: CGSize = .zero

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Low-pass filtered so the parallax glides instead of jittering.
            let targetX = max(-1, min(1, motion.attitude.roll / 0.6))
            let targetY = max(-1, min(1, (motion.attitude.pitch - 0.6) / 0.6))
            self.offset = CGSize(
                width: self.offset.width * 0.85 + targetX * 0.15,
                height: self.offset.height * 0.85 + targetY * 0.15
            )
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }
}
