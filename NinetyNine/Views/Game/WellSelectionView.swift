//
//  WellSelectionView.swift
//  "Two of these. You don't get to know which."
//
//  The well is your only way out when nothing in hand is legal, and its whole
//  tension comes from not knowing what's down there. So the pick is blind: your
//  deal is face down, you choose two positions, and only then do you see the
//  cards you kept.
//
//  An earlier version of this screen showed the faces. It looked better and it
//  ruined the game — you'd have known your outs from the first turn, and the
//  well reveal, the most dramatic moment in a round, would have been a
//  formality. Nothing here can leak a face: the view is handed a *count*, not
//  cards. The redaction happens back in `PlayerView`, where a mistake can't
//  reach the wire.
//

import SwiftUI

struct WellSelectionView: View {
    let playerName: String
    /// How many face-down cards were dealt to choose from.
    let slotCount: Int
    let wellSize: Int
    var isSharedDevice: Bool
    /// Chosen positions, in the order they were picked.
    let onConfirm: ([Int]) -> Void

    @Environment(\.motion) private var motion
    @State private var chosen: [Int] = []
    @State private var hasAppeared = false

    private var isReady: Bool { chosen.count == wellSize }
    /// With the smallest legal deal there is nothing to decide.
    private var isForced: Bool { slotCount <= wellSize }

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                dealtRow
                Spacer().frame(height: 22)
                wellSlots
                Spacer(minLength: 8)
                confirmButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            // Keeps the composition together on an iPad instead of stranding the
            // header, the deal and the button at three corners of a large screen.
            .tableContentWidth()
        }
        .onAppear {
            if isForced { chosen = Array(0..<slotCount) }
            withAnimation(motion.animation(Motion.deal)) { hasAppeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("well-selection")
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            if isSharedDevice {
                Text(playerName.uppercased())
                    .font(Typography.label)
                    .tracking(2)
                    .foregroundStyle(Palette.brass)
            }
            Text("Bury two, blind")
                .font(Typography.title)
                .foregroundStyle(Palette.brassLight)
            Text(subtitle)
                .font(Typography.caption)
                .foregroundStyle(Palette.ivoryDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if isForced {
            return "You were dealt \(slotCount), so two of them are your well whether you like it or not."
        }
        if isReady {
            return "Those two are your well. You'll see the rest in a moment — and these, not until you're stuck."
        }
        if chosen.isEmpty {
            return "Your deal is face down. Bury \(wellSize) of it as your well — "
                + "nobody knows what's in a well, including you."
        }
        return "One more."
    }

    // MARK: - The face-down deal

    private var dealtRow: some View {
        VStack(spacing: 10) {
            Text("YOUR DEAL")
                .font(Typography.label)
                .tracking(1.6)
                .foregroundStyle(Palette.ivoryFaint)

            // Sized to fit rather than scrolled. Every card here is face down
            // and identical, so a card hidden off the edge is indistinguishable
            // from a card that isn't there — and on a blind pick the *count* is
            // the only information on screen. An earlier scrolling version also
            // left-aligned itself on an iPad, stranding the row against one edge
            // while the well slots below sat centred.
            GeometryReader { geometry in
                let width = cardWidth(fitting: geometry.size.width)
                HStack(spacing: cardSpacing) {
                    // Array-wrapped: the bare range initialiser is for constant
                    // counts and caches the first one it sees.
                    ForEach(Array(0..<max(0, slotCount)), id: \.self) { slot in
                        faceDownCard(slot, width: width)
                    }
                }
                .frame(width: geometry.size.width, alignment: .center)
                // Generous headroom: a chosen card lifts and carries a badge
                // above its own top edge, and at 10 it was being clipped.
                .padding(.top, 26)
                .padding(.bottom, 10)
            }
            .frame(height: maximumCardWidth / cardAspectRatio + 40)
        }
    }

    private var maximumCardWidth: CGFloat { 66 }
    private var cardSpacing: CGFloat { 8 }

    /// Shrink the cards until the whole deal fits the width it's given. The
    /// floor is a tappable target — below that, scrolling would be the lesser
    /// evil, but a legal deal never gets there on any supported device.
    private func cardWidth(fitting available: CGFloat) -> CGFloat {
        let count = CGFloat(max(1, slotCount))
        let usable = max(0, available - 8) - cardSpacing * (count - 1)
        return max(38, min(maximumCardWidth, usable / count))
    }

    @ViewBuilder
    private func faceDownCard(_ slot: Int, width: CGFloat) -> some View {
        let position = chosen.firstIndex(of: slot)
        let isChosen = position != nil

        Button {
            toggle(slot)
        } label: {
            ZStack(alignment: .top) {
                CardBackView()
                    .frame(width: width, height: width / cardAspectRatio)
                    .cardShadow(lift: motion.displacement(isChosen ? 14 : 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Palette.brassLight, lineWidth: isChosen ? 2 : 0)
                    )
                    .offset(y: motion.displacement(isChosen ? -10 : 0))

                if let position {
                    Text("\(position + 1)")
                        .font(Typography.label)
                        .foregroundStyle(Palette.feltEdge)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Palette.brassLight))
                        .offset(y: motion.displacement(-20))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .offset(y: hasAppeared ? 0 : motion.displacement(300))
            .animation(
                motion.animation(Motion.deal).delay(Double(slot) * Motion.dealStagger),
                value: hasAppeared
            )
        }
        .buttonStyle(.plain)
        .disabled(isForced)
        .accessibilityIdentifier("well-candidate-\(slot)")
        // No rank, no suit. There is nothing true to say about a face-down card,
        // and saying anything here would leak it to VoiceOver.
        .accessibilityLabel("Card \(slot + 1), face down")
        .accessibilityValue(isChosen ? "In your well" : "Kept")
        .accessibilityAddTraits(.isButton)
        .animation(motion.animation(Motion.cardLift), value: chosen)
    }

    // MARK: - The well

    private var wellSlots: some View {
        HStack(spacing: 14) {
            ForEach(0..<wellSize, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Palette.brass.opacity(index < chosen.count ? 0 : 0.45),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                        .frame(width: 74, height: 74 / cardAspectRatio)

                    if index < chosen.count {
                        CardBackView()
                            .frame(width: 74, height: 74 / cardAspectRatio)
                            .cardShadow(lift: 12)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "questionmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Palette.brass.opacity(0.5))
                    }
                }
            }
        }
        .animation(motion.animation(Motion.cardLift), value: chosen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your well: \(chosen.count) of \(wellSize) chosen")
    }

    // MARK: - Confirm

    private var confirmButton: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.shared.play(.cardFlick)
                SoundEngine.shared.play(.cardFlick)
                onConfirm(chosen)
            } label: {
                Text(isReady ? "Bury them" : "Pick \(wellSize - chosen.count) more")
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(Palette.feltEdge)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Palette.brassLight)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isReady)
            .opacity(isReady ? 1 : 0.4)
            .accessibilityIdentifier("well-confirm")

            if !isForced {
                Text("Tap a buried card again to take it back.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ivoryFaint)
                    .opacity(chosen.isEmpty ? 0 : 1)
            }
        }
    }

    private func toggle(_ slot: Int) {
        guard !isForced else { return }
        Haptics.shared.play(.select)
        withAnimation(motion.animation(Motion.cardLift)) {
            if let index = chosen.firstIndex(of: slot) {
                chosen.remove(at: index)
            } else if chosen.count < wellSize {
                chosen.append(slot)
            }
        }
    }
}
