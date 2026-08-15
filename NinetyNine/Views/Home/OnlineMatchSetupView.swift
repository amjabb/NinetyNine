//
//  OnlineMatchSetupView.swift
//  The deal, chosen before anybody is invited.
//
//  Online, these three choices are not preferences — they are the match. The
//  player who starts it fixes the deal for everybody, so they get their own
//  screen to make them on rather than a row tucked under a mode picker, and the
//  invite step comes afterwards. Nobody should be asked "who do you want to
//  play?" before they've decided what the game is.
//

import SwiftUI

struct OnlineMatchSetupView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var session = GameCenterSession.shared

    /// Called once the deal is settled — this is where Game Center takes over
    /// and asks who's playing.
    let onFindPlayers: () -> Void
    let onBack: () -> Void

    private var maxDeal: Int {
        Rules.maxCardsDealt(forPlayerCount: settings.onlinePlayerCount)
    }

    private var currentDeal: Int {
        min(max(settings.cardsDealt, Rules.minCardsDealt), maxDeal)
    }

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    BrassSegments(
                        title: "Players",
                        options: (2...6).map { ($0, "\($0)") },
                        selection: $settings.onlinePlayerCount
                    )
                    .onChange(of: settings.onlinePlayerCount) { _, _ in clampDeal() }

                    cardsDealtSection
                    autoWellToggle
                    dealSummary

                    Text("You're setting this for everyone. Whoever joins plays the deal you pick here.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ivoryFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .tableContentWidth()
                .padding(.bottom, 150)
            }

            VStack {
                Spacer()
                VStack(spacing: 10) {
                    BrassButton(
                        title: "Find players",
                        subtitle: "invite a friend, or match with anyone",
                        icon: "person.2.fill",
                        isProminent: true,
                        isEnabled: session.canPlayOnline,
                        action: onFindPlayers
                    )
                    BrassButton(title: "Back", isProminent: false, action: onBack)
                }
                .padding(24)
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
        .onAppear { clampDeal() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Online").labelStyle()
            Text("A new match")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
        }
    }

    private var cardsDealtSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Cards to deal").labelStyle()
                Spacer()
                Text("\(currentDeal)")
                    .font(Typography.counter(15, weight: .heavy))
                    .foregroundStyle(Palette.brassLight)
            }
            HStack(spacing: 10) {
                stepper(icon: "minus") {
                    settings.cardsDealt = max(Rules.minCardsDealt, currentDeal - 1)
                }
                track
                stepper(icon: "plus") {
                    settings.cardsDealt = min(maxDeal, currentDeal + 1)
                }
            }
            Text("Two of them go to each well, so you'd start holding \(currentDeal - Rules.wellSize). Up to \(maxDeal) with \(settings.onlinePlayerCount) players.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ivoryFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepper(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.play(.select)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.ivory)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var track: some View {
        HStack(spacing: 5) {
            ForEach(Array(Rules.minCardsDealt...12), id: \.self) { value in
                let filled = value <= currentDeal
                let available = value <= maxDeal
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(filled
                        ? AnyShapeStyle(Palette.brassFace)
                        : AnyShapeStyle(Color.white.opacity(available ? 0.12 : 0.04)))
                    .frame(height: 22)
            }
        }
        .animation(Motion.panel, value: settings.cardsDealt)
    }

    /// Offered online for a different reason than on one device: there's no
    /// phone to pass, but there is a lap of the table where nobody can play
    /// while everybody buries — and online that lap can take a day.
    private var autoWellToggle: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bank wells automatically")
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(Palette.ivory)
                Text("Skip the burying round so the first card can be played straight away. The well is picked face down either way.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ivoryFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $settings.onlineAutoAssignWells)
                .labelsHidden()
                .tint(Palette.brass)
                .accessibilityIdentifier("online.autoWell")
        }
    }

    private var dealSummary: some View {
        let total = settings.onlinePlayerCount * currentDeal
        return VStack(alignment: .leading, spacing: 5) {
            Text("The deal").labelStyle()
            HStack {
                Text("\(settings.onlinePlayerCount) × (\(currentDeal - Rules.wellSize) + \(Rules.wellSize) well)")
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(Palette.ivory)
                Spacer()
                Text("\(total) of 52 dealt")
                    .font(Typography.counter(13, weight: .bold))
                    .foregroundStyle(Palette.brassLight)
            }
            Text("\(52 - total) cards left in the draw pile.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ivoryFaint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.5), lineWidth: 1)
        )
    }

    private func clampDeal() {
        if settings.cardsDealt > maxDeal { settings.cardsDealt = maxDeal }
        if settings.cardsDealt < Rules.minCardsDealt { settings.cardsDealt = Rules.minCardsDealt }
    }
}
