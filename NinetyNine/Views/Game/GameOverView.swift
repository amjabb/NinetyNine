//
//  GameOverView.swift
//  Win and loss screens.
//
//  A win gets a brass shower and the wordmark; a loss gets a quiet, honest
//  placing and the reason. Losing screens that shout at you are how games lose
//  players — this one tells you where you finished and offers the rematch.
//

import SwiftUI

struct GameOverView: View {
    let outcome: GameViewModel.Outcome
    /// Final standings, already ordered. Built from elimination order rather
    /// than from a GameState, so this screen never holds hidden cards either.
    let standings: [(participant: MatchParticipant, position: Int)]
    /// Whose result the headline is about. In pass-and-play this is whoever is
    /// holding the device.
    let subjectID: String?
    let winnerName: String?
    /// Pass-and-play shares one screen, so the copy addresses the table rather
    /// than a single player.
    let isSharedDevice: Bool
    let onRematch: () -> Void
    let onExit: () -> Void

    @Environment(\.motion) private var motion
    @State private var hasAppeared = false

    private var didWin: Bool { outcome == .won }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            if didWin && !motion.reduceMotion {
                BrassShower()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                headline

                standingsList

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    BrassButton(title: "Rematch", icon: "arrow.clockwise", isProminent: true, action: onRematch)
                    BrassButton(title: "Back to menu", isProminent: false, action: onExit)
                }
                .padding(.horizontal, 4)
            }
            .padding(28)
            .scaleEffect(hasAppeared ? 1 : 0.92)
            .opacity(hasAppeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(motion.animation(Motion.drama)) { hasAppeared = true }
        }
        .transition(.opacity)
    }

    // MARK: Headline

    private var headline: some View {
        VStack(spacing: 8) {
            if didWin {
                Text("LAST ONE STANDING")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(Palette.brassMid)
                Text(isSharedDevice ? (winnerName ?? "Winner") : "You win")
                    .font(.system(size: 46, weight: .black, design: .serif))
                    .brassFoil()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            } else {
                Text("ELIMINATED")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(Palette.danger)
                Text(placementText)
                    .font(.system(size: 38, weight: .black, design: .serif))
                    .foregroundStyle(Palette.ivory)
            }

            Text(subtitle)
                .font(Typography.body)
                .foregroundStyle(Palette.ivoryDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var placementText: String {
        guard case .lost(let placed) = outcome else { return "" }
        return Standings.placementHeadline(position: placed, of: standings.count)
    }

    private var subtitle: String {
        if didWin {
            let opponents = max(0, standings.count - 1)
            return "You outlasted \(opponents) \(opponents == 1 ? "opponent" : "opponents")."
        }
        if let winnerName {
            return "\(winnerName) took the table. The first player out deals next."
        }
        return "The table is done."
    }


    // MARK: Standings

    /// Finishing order, reconstructed from elimination ranks. The winner sits at
    /// the top; everyone else appears in reverse knockout order.
    private var standingsList: some View {
        VStack(spacing: 6) {
            ForEach(standings, id: \.participant.id) { entry in
                let isSubject = entry.participant.id == subjectID
                HStack(spacing: 10) {
                    Text("\(entry.position)")
                        .font(Typography.counter(13, weight: .heavy))
                        .foregroundStyle(entry.position == 1 ? Palette.brassLight : Palette.ivoryFaint)
                        .frame(width: 20)
                    // On a shared device everyone is a real person by name;
                    // calling one of them "You" would be meaningless to the
                    // others reading the same screen.
                    Text(isSubject && !isSharedDevice ? "You" : entry.participant.name)
                        .font(.system(size: 15, weight: isSubject ? .bold : .medium))
                        .foregroundStyle(isSubject ? Palette.ivory : Palette.ivory.opacity(0.75))
                    Spacer()
                    if entry.position == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.brassFace)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSubject ? Color.white.opacity(0.09) : Color.white.opacity(0.03))
                )
            }
        }
    }
}

// MARK: - Brass shower

/// Falling brass flakes for the victory screen. Deterministic seeding keeps it
/// identical each time, which makes it feel authored rather than random.
private struct BrassShower: View {
    @State private var phase: Double = 0

    private struct Flake {
        var x: Double
        var size: Double
        var delay: Double
        var duration: Double
        var spin: Double
        var tint: Color
    }

    private let flakes: [Flake] = {
        var generator = SeededGenerator(seed: 0x9911)
        func next(_ upper: Int) -> Double { Double(generator.next() % UInt64(upper)) }
        return (0..<70).map { _ in
            Flake(
                x: next(1000) / 1000,
                size: 4 + next(9),
                delay: next(2200) / 1000,
                duration: 2.4 + next(1800) / 1000,
                spin: 180 + next(540),
                tint: [Palette.brassLight, Palette.brassMid, Palette.brass, Palette.brassDeep][Int(next(4))]
            )
        }
    }()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(flakes.enumerated()), id: \.offset) { index, flake in
                    Rectangle()
                        .fill(flake.tint)
                        .frame(width: flake.size, height: flake.size * 1.9)
                        .rotationEffect(.degrees(phase * flake.spin + Double(index)))
                        .position(
                            x: flake.x * geometry.size.width,
                            y: -30 + travel(flake) * (geometry.size.height + 90)
                        )
                        .opacity(opacity(flake))
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 4.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }

    private func travel(_ flake: Flake) -> Double {
        let local = (phase * 4.6 - flake.delay) / flake.duration
        return local.truncatingRemainder(dividingBy: 1.0) < 0 ? 0 : max(0, min(1.15, local))
    }

    private func opacity(_ flake: Flake) -> Double {
        let t = travel(flake)
        if t <= 0 { return 0 }
        return t > 0.85 ? max(0, (1.15 - t) / 0.3) : 0.9
    }
}
