//
//  BlindDealOrderTests.swift
//  The well is picked by position, so position must not encode rank.
//

import XCTest
@testable import NinetyNine

final class BlindDealOrderTests: XCTestCase {

    /// Position in `Rank.allCases`, ace low — the same ordering `sorted` uses.
    private func rankIndex(_ rank: Rank) -> Int {
        Rank.allCases.firstIndex(of: rank) ?? 0
    }

    private func engine(seed: UInt32, players: Int = 3, dealt: Int = 9) throws -> GameEngine {
        let seats = (0..<players).map {
            (id: "p\($0)", name: "P\($0)", kind: PlayerState.PlayerKind.human)
        }
        return try GameEngine(seats: seats, dealerIndex: 0, cardsDealt: dealt, seed: seed)
    }

    /// The bug this guards: hands used to be sorted at the deal, so slot 0 was
    /// always the lowest card and the last slot the highest. A "blind" pick by
    /// position was then a perfectly informed pick by rank.
    func testTheDealIsNotSortedWhileWellsAreBeingChosen() throws {
        var sortedDeals = 0
        var total = 0
        for seed in UInt32(1)...40 {
            let game = try engine(seed: seed)
            XCTAssertTrue(game.state.isChoosingWells)
            for player in game.state.players {
                total += 1
                if player.hand == GameEngine.sorted(player.hand) { sortedDeals += 1 }
            }
        }
        // A 9-card hand lands in sorted order by chance about once in 362,880
        // deals, so anything above a stray hit means the deal is being sorted.
        XCTAssertLessThan(
            sortedDeals, max(2, total / 20),
            "\(sortedDeals) of \(total) hands were in sorted order — the blind pick leaks rank"
        )
    }

    /// And the other half of the promise: once the well is buried and you can
    /// actually see the cards, the hand is tidy.
    func testTheHandIsSortedOnceTheWellsAreBuried() throws {
        for seed in UInt32(1)...10 {
            let game = try engine(seed: seed)
            while game.state.isChoosingWells {
                let chooser = try XCTUnwrap(game.state.wellChooserID)
                try game.chooseWell(slots: [0, 1], by: chooser)
            }
            for player in game.state.players {
                XCTAssertEqual(
                    player.hand, GameEngine.sorted(player.hand),
                    "seed \(seed): \(player.name)'s hand should be sorted once it's visible"
                )
            }
        }
    }

    /// Banking slot 0 and slot 1 should not systematically bank low cards.
    func testBankingTheTopOfTheFanIsNotBankingYourLowestCards() throws {
        var wellTotal = 0
        var handTotal = 0
        var wellCards = 0
        var handCards = 0
        for seed in UInt32(1)...60 {
            let game = try engine(seed: seed)
            while game.state.isChoosingWells {
                let chooser = try XCTUnwrap(game.state.wellChooserID)
                try game.chooseWell(slots: [0, 1], by: chooser)
            }
            for player in game.state.players {
                wellTotal += player.well.reduce(0) { $0 + rankIndex($1.rank) }
                wellCards += player.well.count
                handTotal += player.hand.reduce(0) { $0 + rankIndex($1.rank) }
                handCards += player.hand.count
            }
        }
        let wellMean = Double(wellTotal) / Double(wellCards)
        let handMean = Double(handTotal) / Double(handCards)
        XCTAssertLessThan(
            abs(wellMean - handMean), 1.4,
            "well averages \(wellMean) vs hand \(handMean) — position still predicts rank"
        )
    }
}
