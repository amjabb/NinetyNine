//
//  SettingsView.swift
//

import SwiftUI

struct SettingsView: View {
    let onBack: () -> Void

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var records = Records.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsResetConfirmation = false

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    group("Feel") {
                        toggleRow(
                            "Sound",
                            detail: "Procedurally generated. Respects the silent switch.",
                            isOn: $settings.soundEnabled
                        )
                        toggleRow(
                            "Haptics",
                            detail: "Custom Core Haptics patterns per event.",
                            isOn: $settings.hapticsEnabled
                        )
                    }

                    group("Play") {
                        toggleRow(
                            "Coaching",
                            detail: "Explain why a card can't be played when you tap it.",
                            isOn: $settings.coachingEnabled
                        )
                    }

                    if reduceMotion {
                        infoCard(
                            icon: "figure.walk.motion",
                            title: "Reduce Motion is on",
                            detail: "Card flight, parallax, and the victory shower are damped or disabled to match your system setting."
                        )
                    }

                    group("Data") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Everything stays on this device. No account, no analytics, no network — the app never makes a request.")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.ivoryDim)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                Haptics.shared.play(.select)
                                showsResetConfirmation = true
                            } label: {
                                Text("Reset record and achievements")
                                    .font(Typography.bodyEmphasised)
                                    .foregroundStyle(Palette.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    about

                    Spacer(minLength: 100)
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
        .alert("Reset everything?", isPresented: $showsResetConfirmation) {
            Button("Reset", role: .destructive) { records.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your games, streaks, and achievements will be cleared. This can't be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preferences").labelStyle()
            Text("Settings")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).labelStyle()
            VStack(spacing: 14) { content() }
                .padding(15)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Palette.brassDeep.opacity(0.35), lineWidth: 1)
                )
        }
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(Palette.ivory)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ivoryFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Palette.brass)
        }
        .accessibilityElement(children: .combine)
    }

    private func infoCard(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.brassMid)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(Palette.ivory)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ivoryDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Palette.brass.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Palette.brassDeep.opacity(0.5), lineWidth: 1)
        )
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("About").labelStyle()
            Text("Ninety-Nine")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Palette.ivory)
            Text("Version \(Bundle.main.appVersion) (\(Bundle.main.appBuild))")
                .font(Typography.caption)
                .foregroundStyle(Palette.ivoryDim)
            Text("Every card, suit, and sound in this app is generated in code — no image or audio assets at all.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ivoryFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    var appBuild: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
