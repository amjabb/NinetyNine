//
//  RootView.swift
//  Temporary design gallery — used to eyeball the drawn assets in the
//  Simulator before the real screens are built on top of them.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            TableBackground(lockedSuit: .spades, pressure: 0.9)
            ScrollView {
                VStack(spacing: 18) {
                    TallyGauge(tally: 92, suitLock: .spades, isClockwise: true)
                        .frame(height: 230)

                    ForEach([Suit.spades, .hearts], id: \.self) { suit in
                        HStack(spacing: 3) {
                            ForEach(Rank.allCases, id: \.self) { rank in
                                CardFaceView(card: Card(id: rank.hashValue ^ suit.hashValue, rank: rank, suit: suit))
                                    .frame(width: 50)
                            }
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach([Rank.ace, .five, .seven, .nine, .ten], id: \.self) { rank in
                            CardFaceView(card: Card(id: rank.hashValue, rank: rank, suit: .diamonds))
                                .frame(width: 50)
                        }
                        ForEach([Rank.jack, .queen, .king], id: \.self) { rank in
                            CardFaceView(card: Card(id: rank.hashValue, rank: rank, suit: .clubs))
                                .frame(width: 50)
                        }
                    }
                    HStack(spacing: 10) {
                        CardBackView().frame(width: 82)
                        CardBackView(isHighlighted: true).frame(width: 82)
                        CardFaceView(card: Card(id: 1, rank: .king, suit: .spades), valueOverlay: "−10")
                            .frame(width: 82)
                        CardFaceView(card: Card(id: 2, rank: .seven, suit: .hearts), isPlayable: false)
                            .frame(width: 82)
                    }
                    HStack(spacing: 14) {
                        TallyDeltaChip(delta: 8)
                        TallyDeltaChip(delta: -10)
                        TallyDeltaChip(delta: 0)
                    }
                    Text("99").font(Typography.wordmark).brassFoil()
                }
                .padding(12)
            }
        }
    }
}
