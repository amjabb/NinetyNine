//
//  SeedSearchTests.swift
//  The shuffle seeds the UI tests depend on.
//
//  A UI test that needs a particular opening hand — a pair to run together, say
//  — can't wait for one to turn up by luck. The app accepts `-uitest-seed` to pin
//  the shuffle, and this file is where those numbers come from and what keeps
//  them honest: if a change to dealing moves the hands around, it fails here with
//  a clear reason instead of surfacing as a UI test that mysteriously can't find
//  a card.
//

import XCTest
@testable import NinetyNine

@MainActor
final class SeedSearchTests: XCTestCase {

    /// The table SetPlayUITests launches: two opponents, Sharp, a 6-card deal.
    private func openingHand(seed: UInt32) async -> PlayerView? {
        let model = GameViewModel.solo(
            difficulty: .sharp, opponentCount: 2, cardsDealt: 6,
            playerName: "You", dealerID: nil, seed: seed
        )
        await model.begin()
        return model.view
    }

    /// Pinned by SetPlayUITests. Seed 1 opens with the human to act and a pair of
    /// a *plain* rank — no Ace or 8 — so the run goes from long press straight to
    /// Play with no declaration in between.
    func testSeedOneOpensWithAPlayableRunOfAPlainRank() async throws {
        let dealt = await openingHand(seed: 1)
        let view = try XCTUnwrap(dealt)
        XCTAssertEqual(view.currentPlayerID, view.youID, "The human has to be on turn")

        let context = view.rulesContext()
        let me = context.players[context.currentPlayerIndex]
        let runnable = Rules.playableSetRanks(for: me, in: context)

        XCTAssertFalse(
            runnable.filter { !$0.isSpecial }.isEmpty,
            "Seed 1 no longer deals a plain pair — pick a new seed and update SetPlayUITests"
        )
    }

    /// The seed argument has to actually change the deal, or the pin is silently
    /// useless.
    func testDifferentSeedsDealDifferentHands() async throws {
        let dealtOne = await openingHand(seed: 1)
        let dealtTwo = await openingHand(seed: 99)
        let one = try XCTUnwrap(dealtOne)
        let two = try XCTUnwrap(dealtTwo)
        XCTAssertNotEqual(one.yourHand.map(\.id), two.yourHand.map(\.id))
    }

    /// The same seed twice deals the same hand — the basis for both the pin and
    /// for online replay.
    func testTheSameSeedDealsTheSameHand() async throws {
        let dealtFirst = await openingHand(seed: 1)
        let dealtSecond = await openingHand(seed: 1)
        let first = try XCTUnwrap(dealtFirst)
        let second = try XCTUnwrap(dealtSecond)
        XCTAssertEqual(first.yourHand.map(\.id), second.yourHand.map(\.id))
    }
}
