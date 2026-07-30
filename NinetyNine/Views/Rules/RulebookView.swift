//
//  RulebookView.swift
//  The rulebook, as a browsable reference rather than a wall of prose.
//
//  99 has a lot of rules and several of them are genuinely surprising. The card
//  reference draws real card faces beside each entry, because "the 9 sets the
//  tally to 99" lands faster next to an actual nine.
//

import SwiftUI

struct RulebookView: View {
    let onBack: () -> Void

    @State private var expanded: Set<String> = ["goal"]

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    ForEach(RuleSection.all) { section in
                        sectionCard(section)
                    }

                    cardReference

                    Text("Ninety-Nine · rules v1.0")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.ivoryFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 110)
                }
                .padding(22)
                .tableContentWidth()
            }

            VStack {
                Spacer()
                BrassButton(title: "Back", isProminent: false, action: onBack)
                    .padding(22)
                    .tableContentWidth()
                    .background(
                        LinearGradient(
                            colors: [.clear, Palette.feltShadow.opacity(0.95)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How to play").labelStyle()
            Text("Ninety-Nine")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
            Text("Add cards to a running tally. Never go over 99. Outlast everyone else.")
                .font(Typography.body)
                .foregroundStyle(Palette.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sections

    private func sectionCard(_ section: RuleSection) -> some View {
        let isOpen = expanded.contains(section.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.shared.play(.select)
                withAnimation(Motion.panel) {
                    if isOpen { expanded.remove(section.id) } else { expanded.insert(section.id) }
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: section.glyph)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.brassMid)
                        .frame(width: 24)
                    Text(section.title)
                        .font(Typography.sectionTitle)
                        .foregroundStyle(Palette.ivory)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.ivoryFaint)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                }
                .padding(15)
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(section.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(Palette.brassMid)
                                .frame(width: 4, height: 4)
                                .padding(.top, 7)
                            Text(point)
                                .font(Typography.body)
                                .foregroundStyle(Palette.ivory.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Card reference

    private var cardReference: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Every card").labelStyle()
            ForEach(Rank.allCases, id: \.self) { rank in
                HStack(spacing: 13) {
                    CardFaceView(card: Card(id: rank.hashValue, rank: rank, suit: referenceSuit(rank)))
                        .frame(width: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rank.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.ivory)
                        Text(rank.abilitySummary)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ivoryDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.35), lineWidth: 1)
        )
    }

    /// Alternate suits down the reference list so it doesn't read as one long
    /// column of spades.
    private func referenceSuit(_ rank: Rank) -> Suit {
        let index = Rank.allCases.firstIndex(of: rank) ?? 0
        return Suit.allCases[index % Suit.allCases.count]
    }
}

// MARK: - Content

struct RuleSection: Identifiable {
    let id: String
    let title: String
    let glyph: String
    let points: [String]

    static let all: [RuleSection] = [
        RuleSection(
            id: "goal",
            title: "The goal",
            glyph: "target",
            points: [
                "Every card you play adds its value to a shared tally. The tally must never go above 99.",
                "If you can't play a legal card, you can gamble on your well or skip your turn.",
                "A failed well gamble knocks you out. The last player left wins.",
            ]
        ),
        RuleSection(
            id: "turn",
            title: "Taking a turn",
            glyph: "arrow.right.circle",
            points: [
                "Play one legal card from your hand, face up, onto the pile. If you have a legal card, playing it is mandatory.",
                "Afterwards you draw back up to your hand limit.",
                "Cards you can't legally play are dimmed. Tap one to see why.",
            ]
        ),
        RuleSection(
            id: "lock",
            title: "The suit lock (8)",
            glyph: "lock.fill",
            points: [
                "Playing an 8 adds 8 and locks the suit. Everyone after you must follow it.",
                "Only cards of the locked suit are legal — including 8s. An 8 of the locked suit may rename it.",
                "The lock only breaks when somebody can't follow it and skips.",
            ]
        ),
        RuleSection(
            id: "nine",
            title: "The 9 and the 100",
            glyph: "bolt.fill",
            points: [
                "A 9 sets the tally to exactly 99, whatever it was before. Brutal for whoever plays next.",
                "There is one way past 99: if the very next card is the Ace of the same suit as that 9, played as a 1, the tally hits 100.",
                "The single card played after a 100 has its value forced negative — a King becomes −10. A 9 or a 10 can't take that slot.",
            ]
        ),
        RuleSection(
            id: "negative",
            title: "Going below zero",
            glyph: "thermometer.snowflake",
            points: [
                "From a tally of exactly 0 you may play a 10 to push the tally negative.",
                "Climbing back out, you must land on exactly 0 — no jumping straight from negative to positive.",
                "Once back at 0, it's a fresh start: you can dive again or resume climbing.",
            ]
        ),
        RuleSection(
            id: "queens",
            title: "Poisonous queens",
            glyph: "drop.fill",
            points: [
                "A Queen is wild — she copies the value and ability of any card you name.",
                "The moment anybody draws a Queen from the deck, queens turn poisonous for the rest of the game.",
                "Every Queen still held in hand is immediately exiled to its owner's poison pile, and each one permanently lowers that player's hand limit by one, down to a floor of three.",
            ]
        ),
        RuleSection(
            id: "snackoo",
            title: "Snackoo",
            glyph: "sparkles",
            points: [
                "Holding three of a kind, or three poisoned queens? Declare Snackoo.",
                "It's free and doesn't cost you a turn. Discard the three, draw three fresh, and the tally is untouched.",
            ]
        ),
        RuleSection(
            id: "well",
            title: "The well",
            glyph: "arrow.down.circle.fill",
            points: [
                "You start with two face-down well cards and can only touch them when you have no legal card in hand.",
                "The well hands you one of the two at random — you don't choose.",
                "Playable? You play it and draw two bonus cards. Unplayable? You're out on the spot.",
                "You can always skip instead. It's safe now, but you'll owe two plays on your next turn.",
            ]
        ),
        RuleSection(
            id: "skip",
            title: "Skipping and elimination",
            glyph: "forward.fill",
            points: [
                "A skip costs you two plays next turn, both fully legal.",
                "You can't skip twice in a row — on a turn where you owe plays you must play or use the well.",
                "An eliminated player's cards are shuffled back into the deck, and play continues without them.",
            ]
        ),
    ]
}
