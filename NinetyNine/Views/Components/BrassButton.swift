//
//  BrassButton.swift
//  The app's one button. Prominent variant is brass-filled; the quiet variant is
//  an outline. Two variants is enough — a third would just dilute the hierarchy.
//

import SwiftUI

struct BrassButton: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var isProminent: Bool = true
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            guard isEnabled else {
                Haptics.shared.play(.rejected)
                return
            }
            Haptics.shared.play(.select)
            SoundEngine.shared.play(.tap, volume: 0.5)
            action()
        } label: {
            HStack(spacing: 9) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                }
                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.8)
                    }
                }
            }
            .foregroundStyle(isProminent ? Palette.feltShadow : Palette.ivory)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isProminent ? Palette.brassLight.opacity(0.7) : Palette.brassDeep.opacity(0.8),
                        lineWidth: 1
                    )
            )
            // A press should be felt in the geometry, not just the colour.
            .scaleEffect(isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .animation(Motion.cardLift, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }

    @ViewBuilder
    private var background: some View {
        if isProminent {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.brassFace)
                .shadow(color: Palette.brass.opacity(0.4), radius: 14, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.06))
        }
    }
}

/// A labelled row of mutually exclusive choices, used throughout setup and
/// settings. A stock SwiftUI Picker would work and would look like every other
/// app; this reads as part of the table.
struct BrassSegments<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).labelStyle()
            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selection
                    Button {
                        Haptics.shared.play(.select)
                        SoundEngine.shared.play(.tap, volume: 0.4)
                        withAnimation(Motion.panel) { selection = option.value }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Palette.feltShadow : Palette.ivory.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(isSelected
                                        ? AnyShapeStyle(Palette.brassFace)
                                        : AnyShapeStyle(Color.white.opacity(0.06)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Palette.brassDeep.opacity(isSelected ? 0.9 : 0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }
}
