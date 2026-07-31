//
//  DeclarationSheet.swift
//  "How are you playing that card?"
//
//  This is where 99's cleverest rules live, so it's where the UI has to work
//  hardest. Every option shows the tally it would produce, so choosing between
//  an Ace as 1 or 11 is a glance rather than a calculation. Options that would be
//  illegal never appear at all — the engine filters them before we get here.
//

import SwiftUI

struct DeclarationSheet: View {
    let choice: GameViewModel.PendingChoice
    let currentTally: Int
    /// Resolves an option to the tally it would produce.
    let projected: (Declaration) -> Int?
    let onChoose: (Declaration) -> Void
    let onCancel: () -> Void

    @Environment(\.motion) private var motion
    /// Which rank a Queen is being played as, once that's been picked and the
    /// sheet still needs a second answer.
    @State private var queenRank: Rank?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                header

                CardFaceView(card: choice.card)
                    .frame(width: 96)
                    .cardShadow(lift: 12)

                optionList

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
            }
            .padding(22)
            .background(sheetBackground)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            // Scrim. Tapping it is the same as Back — a modal you can't dismiss
            // by tapping outside always feels like a trap.
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
        )
        .transition(.opacity)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 5) {
            Text(choice.isFromWell ? "The well delivered" : title)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.ivory)
                .multilineTextAlignment(.center)
            Text(choice.card.rank.abilitySummary)
                .font(Typography.caption)
                .foregroundStyle(Palette.ivoryDim)
                .multilineTextAlignment(.center)
        }
    }

    private var title: String {
        switch choice.card.rank {
        case .ace: return "One, or eleven?"
        case .eight: return "Lock a suit?"
        case .queen: return "What is she copying?"
        default: return "Choose how to play it"
        }
    }

    // MARK: Options

    @ViewBuilder
    private var optionList: some View {
        switch choice.card.rank {
        case .ace:
            HStack(spacing: 12) {
                ForEach(aceOptions, id: \.self) { declaration in
                    optionTile(
                        headline: declaration.aceValue == .one ? "1" : "11",
                        caption: nil,
                        declaration: declaration,
                        isWide: true
                    )
                }
            }

        case .eight:
            lockOptions

        case .queen:
            // Copying a rank can itself need an answer — an Ace's value, an 8's
            // suit — so the Queen resolves in two steps rather than guessing.
            if let rank = queenRank {
                queenFollowUp(for: rank)
            } else {
                queenGrid
            }

        default:
            VStack(spacing: 10) {
                ForEach(choice.options, id: \.self) { declaration in
                    optionTile(headline: "Play it", caption: nil, declaration: declaration, isWide: true)
                }
            }
        }
    }

    private var aceOptions: [Declaration] {
        choice.options.filter { $0.aceValue != nil && $0.queenAs == nil }
    }

    private func suitOptions(queenAs: Rank? = nil) -> [Declaration] {
        choice.options.filter { $0.lockSuit != nil && $0.queenAs == queenAs }
    }

    /// Locking is optional — an 8 may be played and lock nothing. This is the
    /// option the sheet used to drop on the floor: it filtered the list on
    /// `lockSuit != nil`, and declining a lock has no suit by definition.
    private func declineOption(queenAs: Rank? = nil) -> Declaration? {
        choice.options.first { $0.declinesLock && $0.queenAs == queenAs }
    }

    /// Four suits, and the choice not to lock at all.
    @ViewBuilder
    private func lockChoices(queenAs: Rank? = nil) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(suitOptions(queenAs: queenAs), id: \.self) { declaration in
                    suitTile(declaration)
                }
            }
            if let decline = declineOption(queenAs: queenAs) {
                Button {
                    Haptics.shared.play(.select)
                    onChoose(decline)
                } label: {
                    VStack(spacing: 2) {
                        Text("Lock nothing")
                            .font(Typography.bodyEmphasised)
                            .foregroundStyle(Palette.ivory)
                        Text("Play the 8 and leave the suit open")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ivoryDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.brassDeep.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("declaration-lock-nothing")
                .accessibilityLabel("Leave the suit open")
            }
        }
    }

    private var lockOptions: some View { lockChoices() }

    /// The second step for a Queen whose copied rank still needs an answer.
    @ViewBuilder
    private func queenFollowUp(for rank: Rank) -> some View {
        VStack(spacing: 12) {
            Text("She's an \(rank.displayName). Now what?")
                .font(Typography.caption)
                .foregroundStyle(Palette.ivoryDim)

            switch rank {
            case .eight:
                lockChoices(queenAs: .eight)
            case .ace:
                HStack(spacing: 12) {
                    ForEach(choice.options.filter { $0.queenAs == .ace }, id: \.self) { declaration in
                        optionTile(
                            headline: declaration.aceValue == .one ? "1" : "11",
                            caption: nil,
                            declaration: declaration,
                            isWide: true
                        )
                    }
                }
            default:
                EmptyView()
            }

            Button("Pick a different card") {
                Haptics.shared.play(.select)
                withAnimation(motion.animation(Motion.panel)) { queenRank = nil }
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.ivoryDim)
        }
    }

    /// A Queen can be almost anything, so the options are grouped by the rank
    /// being copied, with any nested choice (Ace value, locked suit) resolved in
    /// a second step to keep the first screen readable.
    private var queenGrid: some View {
        let ranks = Rank.allCases.filter { rank in
            rank != .queen && choice.options.contains { $0.queenAs == rank }
        }
        return VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 8), count: 4), spacing: 8) {
                ForEach(ranks, id: \.self) { rank in
                    queenTile(for: rank)
                }
            }
        }
    }

    @ViewBuilder
    private func queenTile(for rank: Rank) -> some View {
        // Prefer the option that keeps the tally lowest — the safest reading of
        // an ambiguous rank, and the one shown on the tile.
        let candidates = choice.options.filter { $0.queenAs == rank }
        // An 8 needs a suit (or an explicit refusal) and an Ace needs a value.
        // Those aren't ties to be broken by tally — the sheet used to pick one
        // silently, which meant a Queen played as an 8 never asked at all.
        let needsFollowUp = rank == .eight || rank == .ace
        let best = candidates.min { lhs, rhs in
            (projected(lhs) ?? .max) < (projected(rhs) ?? .max)
        }
        if let best {
            Button {
                Haptics.shared.play(.select)
                if needsFollowUp {
                    withAnimation(motion.animation(Motion.panel)) { queenRank = rank }
                } else {
                    onChoose(best)
                }
            } label: {
                VStack(spacing: 2) {
                    Text(rank.label)
                        .font(.system(size: 22, weight: .heavy, design: .serif))
                        .foregroundStyle(Palette.ivory)
                    if let value = projected(best) {
                        Text("→ \(value)")
                            .font(Typography.counter(11, weight: .bold))
                            .foregroundStyle(tallyTint(value))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.brassDeep.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func suitTile(_ declaration: Declaration) -> some View {
        let suit = declaration.lockSuit ?? .spades
        return Button {
            Haptics.shared.play(.select)
            onChoose(declaration)
        } label: {
            VStack(spacing: 6) {
                SuitShape(suit: suit)
                    .fill(suit.isRed ? Palette.dangerGlow : Palette.ivory)
                    .frame(width: 26, height: 28)
                Text(suit.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.ivoryDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.brassDeep.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lock the suit to \(suit.displayName)")
    }

    private func optionTile(
        headline: String,
        caption: String?,
        declaration: Declaration,
        isWide: Bool
    ) -> some View {
        let value = projected(declaration)
        return Button {
            Haptics.shared.play(.select)
            onChoose(declaration)
        } label: {
            VStack(spacing: 3) {
                Text(headline)
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(Palette.ivory)
                if let value {
                    Text("tally → \(value)")
                        .font(Typography.counter(13, weight: .bold))
                        .foregroundStyle(tallyTint(value))
                }
                if let caption {
                    Text(caption)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ivoryDim)
                }
            }
            .frame(maxWidth: isWide ? .infinity : nil)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.brassDeep.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(headline)\(value.map { ", tally becomes \($0)" } ?? "")")
    }

    private func tallyTint(_ value: Int) -> Color {
        Palette.tallyColor(
            pressure: value > 0 ? Double(value) / 99.0 : 0,
            isNegative: value < 0
        )
    }

    // MARK: Chrome

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
            .shadow(color: .black.opacity(0.6), radius: 26, y: 10)
    }
}
