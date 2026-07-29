//
//  RecordView.swift
//  Lifetime record and achievements.
//

import SwiftUI

struct RecordView: View {
    let onBack: () -> Void

    @ObservedObject private var records = Records.shared

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    headlineStats
                    detailStats
                    achievements
                    Spacer(minLength: 100)
                }
                .padding(22)
            }

            VStack {
                Spacer()
                BrassButton(title: "Back", isProminent: false, action: onBack)
                    .padding(22)
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
            Text("Your record").labelStyle()
            Text(records.stats.gamesPlayed == 0 ? "Nothing yet" : "\(records.stats.gamesPlayed) games")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
        }
    }

    // MARK: Headline

    private var headlineStats: some View {
        HStack(spacing: 10) {
            bigStat(value: "\(records.stats.gamesWon)", label: "Wins", tint: Palette.brassLight)
            bigStat(value: "\(Int(records.stats.winRate * 100))%", label: "Win rate", tint: Palette.safe)
            bigStat(value: "\(records.stats.bestStreak)", label: "Best streak", tint: Palette.caution)
        }
    }

    private func bigStat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Typography.counter(26, weight: .black))
                .foregroundStyle(tint)
            Text(label).labelStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Detail

    private var detailStats: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.label)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ivory.opacity(0.82))
                    Spacer()
                    Text(row.value)
                        .font(Typography.counter(15, weight: .bold))
                        .foregroundStyle(Palette.brassLight)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(index % 2 == 0 ? Color.white.opacity(0.03) : .clear)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.35), lineWidth: 1)
        )
    }

    private var rows: [(label: String, value: String)] {
        let stats = records.stats
        return [
            ("Nines slammed", "\(stats.ninesPlayed)"),
            ("Hundreds reached", "\(stats.hundredsReached)"),
            ("Suits locked", "\(stats.suitsLocked)"),
            ("Snackoos declared", "\(stats.snackoosDeclared)"),
            ("Wells survived", "\(stats.wellsSurvived)"),
            ("Wells that ended you", "\(stats.wellsFatal)"),
            ("Queens exiled", "\(stats.queensPoisoned)"),
            ("Opponents eliminated", "\(stats.opponentsEliminated)"),
            ("Tightest survival", stats.tightestSurvival >= 99 ? "—" : "\(stats.tightestSurvival) to spare"),
            ("Deepest negative", stats.deepestNegative == 0 ? "—" : "\(stats.deepestNegative)"),
        ]
    }

    // MARK: Achievements

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Achievements").labelStyle()
                Spacer()
                Text("\(records.unlocked.count) of \(Achievement.allCases.count)")
                    .font(Typography.counter(11, weight: .bold))
                    .foregroundStyle(Palette.brassMid)
            }

            ForEach(Achievement.allCases) { achievement in
                achievementRow(achievement)
            }
        }
    }

    private func achievementRow(_ achievement: Achievement) -> some View {
        let isUnlocked = records.unlocked.contains(achievement)
        let target = achievement.target()
        let progress = achievement.progress(in: records.stats)

        return HStack(spacing: 13) {
            Image(systemName: isUnlocked ? achievement.glyph : "lock.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isUnlocked ? AnyShapeStyle(Palette.brassFace) : AnyShapeStyle(Palette.ivoryFaint))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.title)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(isUnlocked ? Palette.ivory : Palette.ivoryDim)
                Text(achievement.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ivoryFaint)
                    .fixedSize(horizontal: false, vertical: true)

                // Progress bar for the counted achievements, so locked entries
                // still show momentum instead of a flat "not yet".
                if let target, !isUnlocked {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule()
                                .fill(Palette.brassMid.opacity(0.8))
                                .frame(width: geometry.size.width * min(1, Double(progress) / Double(target)))
                        }
                    }
                    .frame(height: 3)
                    Text("\(min(progress, target)) / \(target)")
                        .font(Typography.counter(9, weight: .bold))
                        .foregroundStyle(Palette.ivoryFaint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isUnlocked ? Color.white.opacity(0.055) : Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isUnlocked ? Palette.brassDeep.opacity(0.8) : Palette.ivoryFaint.opacity(0.18),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(achievement.title). \(achievement.detail) \(isUnlocked ? "Unlocked." : "Locked.")")
    }
}
