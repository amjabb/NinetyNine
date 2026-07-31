//
//  SetPlaySheet.swift
//  "How many of those are you playing?"
//
//  Playing two or more of a rank at once is powerful and situational, so it is
//  deliberately *not* on the tap path: tapping a card always plays exactly that
//  card. This is reached only by a long press. The author's constraint was
//  explicit — an ever-present "play them all" affordance would be noise for the
//  whole game and a misfire risk in the endgame, when a hand of nines and jacks
//  is being hoarded on purpose.
//
//  Everything about the run lives on one screen: which copies, how many, what it
//  does to the tally, and — for Aces, 8s and 4s — the declaration. Chaining a
//  count picker into a separate declaration sheet would put two modals between a
//  long press and a card landing.
//

import SwiftUI

struct SetPlaySheet: View {
    let pending: GameViewModel.PendingSet
    let currentTally: Int
    let declarations: [Declaration]
    /// Resolves a declaration to the tally the run would produce.
    let projected: (Declaration) -> Int?
    let onToggle: (Card) -> Void
    let onPlay: (Declaration) -> Void
    let onCancel: () -> Void

    @Environment(\.motion) private var motion
    @State private var chosen: Declaration?

    /// The declaration the Play button will use: whatever's been picked, or the
    /// only option when there's no choice to make.
    private var effectiveDeclaration: Declaration? {
        if let chosen, declarations.contains(chosen) { return chosen }
        return declarations.count == 1 ? declarations[0] : nil
    }

    private var needsAChoice: Bool { declarations.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                header
                cardStrip

                if needsAChoice {
                    declarationRow
                } else {
                    tallyPreview
                }

                playButton
                backButton
            }
            .padding(22)
            .background(sheetBackground)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        // `.contain` is load-bearing: an identifier on a plain container is
        // pushed down onto its children and overwrites theirs, which hides every
        // card and button in here from both VoiceOver and the tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("set-play-sheet")
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 5) {
            Text("Play a run")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.brassLight)
            Text(subtitle)
                .font(Typography.caption)
                .foregroundStyle(Palette.ivoryDim)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard pending.canPlay else {
            return "Pick at least two \(pending.rank.plural)."
        }
        let count = pending.selected.count
        if pending.rank == .four {
            // The one rule people get wrong: fours compound, they don't merge.
            return count % 2 == 0
                ? "\(count.spelledOut.capitalized) reversals cancel out — play carries on the way it's going."
                : "\(count.spelledOut.capitalized) reversals — the direction flips."
        }
        return "Tap to add or drop a card. They land one after another."
    }

    // MARK: - The cards

    /// Every copy of the rank in hand, selected ones raised. Selection order is
    /// play order, and it's numbered, because with a 5 that ordering is the
    /// difference between legal and a bust.
    private var cardStrip: some View {
        HStack(spacing: 10) {
            ForEach(pending.available) { card in
                selectableCard(card)
            }
        }
        .frame(height: 108)
        .animation(motion.animation(Motion.cardLift), value: pending.selected)
    }

    @ViewBuilder
    private func selectableCard(_ card: Card) -> some View {
        let position = pending.selected.firstIndex { $0.id == card.id }
        let isSelected = position != nil

        Button {
            onToggle(card)
        } label: {
            ZStack(alignment: .top) {
                CardFaceView(card: card)
                    .frame(width: 62)
                    .cardShadow(lift: motion.displacement(isSelected ? 12 : 3))
                    .opacity(isSelected ? 1 : 0.42)
                    .scaleEffect(isSelected ? 1.0 : 0.92)
                    .offset(y: motion.displacement(isSelected ? -8 : 0))

                if let position {
                    orderBadge(position + 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("set-card-\(card.id)")
        .accessibilityLabel("\(card.rank.displayName) of \(card.suit.displayName)")
        .accessibilityValue(
            position.map { "In the run, position \($0 + 1)" } ?? "Not in the run"
        )
        .accessibilityAddTraits(.isButton)
    }

    /// Play order, not just membership — with a 5 near the ceiling the order is
    /// what decides whether the run is legal.
    private func orderBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(Typography.label)
            .foregroundStyle(Palette.feltEdge)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Palette.brassLight))
            .offset(y: motion.displacement(-18))
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Outcome

    private var tallyPreview: some View {
        let result = effectiveDeclaration.flatMap(projected)
        return HStack(spacing: 10) {
            Text("\(currentTally)")
                .font(Typography.tally(24))
                .foregroundStyle(Palette.ivoryDim)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.ivoryDim.opacity(0.6))
            Text(result.map(String.init) ?? "—")
                .font(Typography.tally(24))
                .foregroundStyle(result == nil ? Palette.danger : Palette.brassLight)
                .contentTransition(.numericText())
        }
        .animation(motion.animation(Motion.panel), value: result)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            result.map { "Tally goes from \(currentTally) to \($0)" } ?? "That run isn't legal"
        )
    }

    /// Aces, 8s and Queens-as-something need one declaration for the whole run —
    /// you can't play one Ace as 1 and the next as 11.
    private var declarationRow: some View {
        VStack(spacing: 8) {
            Text("One choice for the whole run")
                .font(Typography.caption)
                .foregroundStyle(Palette.ivoryDim)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(declarations.enumerated()), id: \.offset) { _, declaration in
                        let isChosen = effectiveDeclaration == declaration
                        Button {
                            Haptics.shared.play(.select)
                            withAnimation(motion.animation(Motion.panel)) { chosen = declaration }
                        } label: {
                            VStack(spacing: 3) {
                                Text(label(for: declaration))
                                    .font(Typography.bodyEmphasised)
                                    .foregroundStyle(isChosen ? Palette.feltEdge : Palette.ivory)
                                if let tally = projected(declaration) {
                                    Text("→ \(tally)")
                                        .font(Typography.caption)
                                        .foregroundStyle(
                                            isChosen ? Palette.feltEdge.opacity(0.72) : Palette.ivoryDim
                                        )
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isChosen ? Palette.brassLight : Color.white.opacity(0.07))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("set-declaration-\(label(for: declaration))")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func label(for declaration: Declaration) -> String {
        if declaration.declinesLock { return "No lock" }
        if let suit = declaration.lockSuit { return "\(suit.glyph) \(suit.displayName)" }
        if let value = declaration.aceValue { return value == .eleven ? "11 each" : "1 each" }
        if let rank = declaration.queenAs { return "As \(rank.displayName)" }
        return "Play"
    }

    // MARK: - Buttons

    private var playButton: some View {
        Button {
            if let declaration = effectiveDeclaration { onPlay(declaration) }
        } label: {
            Text(playTitle)
                .font(Typography.bodyEmphasised)
                .foregroundStyle(Palette.feltEdge)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.brassLight)
                )
        }
        .buttonStyle(.plain)
        .disabled(effectiveDeclaration == nil || !pending.canPlay)
        .opacity(effectiveDeclaration == nil || !pending.canPlay ? 0.4 : 1)
        .accessibilityIdentifier("set-play-confirm")
    }

    private var playTitle: String {
        guard pending.canPlay else { return "Pick two or more" }
        if needsAChoice && effectiveDeclaration == nil { return "Choose one" }
        return "Play \(pending.selected.count.spelledOut) \(pending.rank.plural)"
    }

    private var backButton: some View {
        Button(action: onCancel) {
            Text("Back")
                .font(Typography.bodyEmphasised)
                .foregroundStyle(Palette.ivoryDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("set-play-cancel")
    }

    /// Deliberately identical to DeclarationSheet's — these are two forms of the
    /// same question and shouldn't look like two different features.
    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Palette.feltEdge.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Palette.brassDeep.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
    }
}

// MARK: - Small numbers, spelled out

extension Int {
    /// "two Sixes" reads better than "2 Sixes" at the sizes this is used at.
    /// Only the range a hand can actually hold is spelled out.
    var spelledOut: String {
        switch self {
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        case 5: return "five"
        default: return String(self)
        }
    }
}
