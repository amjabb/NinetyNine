//
//  OnlineMatchesView.swift
//  Your matches in progress — open one, or get rid of one.
//
//  This used to be Apple's `GKTurnBasedMatchmakerViewController`, which shows
//  the same list and offers the same swipe. The reason it isn't any more is the
//  swipe: GameKit will not remove a match you are still playing, its list has no
//  way to tell you that, and so the row leaves and comes straight back. Doing it
//  here means the delete can leave the match first, which is what makes it work.
//

import SwiftUI
import GameKit

struct OnlineMatchesView: View {
    let onOpen: (GKTurnBasedMatch) -> Void
    let onNewMatch: () -> Void
    let onBack: () -> Void

    @ObservedObject private var library = MatchLibrary.shared
    @ObservedObject private var session = GameCenterSession.shared
    @State private var pendingDelete: MatchLibrary.Entry?

    var body: some View {
        ZStack {
            TableBackground(pressure: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if library.isLoading && library.entries.isEmpty {
                        placeholder("Reading your matches…")
                    } else if library.entries.isEmpty {
                        placeholder("Nothing in progress. Start a match and invite somebody.")
                    } else {
                        ForEach(library.entries) { entry in
                            row(entry)
                        }
                        Text("Tap a match to open it, or the bin to remove it. Removing one that's still going quits it for you first — the other players will see that.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.ivoryFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .padding(22)
                .tableContentWidth()
                .padding(.bottom, 150)
            }

            VStack {
                Spacer()
                VStack(spacing: 10) {
                    BrassButton(
                        title: "Start a new match",
                        icon: "plus.circle.fill",
                        isProminent: true,
                        action: onNewMatch
                    )
                    BrassButton(title: "Back", isProminent: false, action: onBack)
                }
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
        .task { await library.reload() }
        // A turn landing while this list is open changes what it should say.
        // Watching the stamp rather than the counts on purpose: a turn passing
        // between two *other* players moves the list without moving a count.
        .onChange(of: session.matchCountsChangedAt) { _, _ in
            Task { await library.reload() }
        }
        // A real two-way binding, not `.constant`: a confirmation dialog can be
        // dismissed by tapping outside it, and a constant binding would leave
        // `pendingDelete` set and re-present the sheet on every redraw.
        .confirmationDialog(
            "Remove this match?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let entry = pendingDelete else { return }
                pendingDelete = nil
                Task { await library.delete(entry) }
            }
            Button("Keep it", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.isFinished == true
                ? "It's over — this just clears it off the list."
                : "This match is still going. Removing it quits for you, and the other players will see that.")
        }
        .alert("Couldn't remove that", isPresented: Binding(
            get: { library.lastError != nil },
            set: { if !$0 { library.lastError = nil } }
        )) {
            Button("OK") { library.lastError = nil }
        } message: {
            Text(library.lastError ?? "")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Online").labelStyle()
            Text(library.entries.isEmpty ? "Your matches" : "\(library.entries.count) match\(library.entries.count == 1 ? "" : "es")")
                .font(Typography.title)
                .foregroundStyle(Palette.ivory)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.ivoryDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.black.opacity(0.30))
            )
    }

    /// Tap the row to open the match; the trash button removes it.
    ///
    /// Deliberately a visible control rather than the swipe Game Center uses.
    /// A swipe on a card that isn't inside a `List` has to be hand-rolled, and a
    /// hand-rolled horizontal drag inside a `ScrollView` fights the scroll — a
    /// worse trade than a button, on the one screen whose entire reason for
    /// existing is that removing a match should visibly work.
    private func row(_ entry: MatchLibrary.Entry) -> some View {
        let isDeleting = library.deleting.contains(entry.id)
        return HStack(spacing: 10) {
            Button {
                guard !isDeleting else { return }
                Haptics.shared.play(.select)
                onOpen(entry.match)
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(tint(for: entry))
                        .frame(width: 9, height: 9)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.opponentSummary)
                            .font(Typography.bodyEmphasised)
                            .foregroundStyle(Palette.ivory)
                            .lineLimit(1)
                        Text(entry.statusLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(tint(for: entry))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.ivoryFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityLabel("\(entry.opponentSummary). \(entry.statusLine).")
            .accessibilityHint("Opens this match.")

            Button {
                Haptics.shared.play(.select)
                pendingDelete = entry
            } label: {
                Group {
                    if isDeleting {
                        ProgressView().tint(Palette.ivoryDim)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.ivoryDim)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityLabel("Remove this match")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    entry.isYourTurn
                        ? Palette.brassDeep.opacity(0.9)
                        : Palette.brassDeep.opacity(0.35),
                    lineWidth: 1
                )
        )
        .opacity(isDeleting ? 0.45 : 1)
    }

    private func tint(for entry: MatchLibrary.Entry) -> Color {
        if entry.isFinished { return Palette.ivoryFaint }
        if entry.isWaitingForPlayers { return Palette.brassMid }
        return entry.isYourTurn ? Palette.safe : Palette.ivoryDim
    }
}
