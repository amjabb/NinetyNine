//
//  AIStrengthTests.swift
//  Does the harder opponent actually win more?
//
//  A difficulty tier is a claim, and claims about AI strength are the easiest
//  thing in a codebase to get wrong — heuristics that read well can play badly,
//  and nobody notices because the games still look like games. So the tiers play
//  each other, many times, on pinned seeds.
//

import XCTest
@testable import NinetyNine

final class AIStrengthTests: XCTestCase {

    /// Play one game to its end and return the winner's id.
    private func playOut(
        seats: [(String, String, PlayerState.PlayerKind)],
        seed: UInt32
    ) throws -> String? {
        let engine = try GameEngine(seats: seats, dealerIndex: seats.count - 1, cardsDealt: 7, seed: seed)

        // Wells first, each by its own player's judgement.
        var guardCount = 0
        while let chooser = engine.state.wellChooserID, guardCount < 12 {
            guardCount += 1
            guard let seat = engine.state.index(of: chooser) else { break }
            let difficulty = engine.state.players[seat].kind.difficulty ?? .sharp
            let slots = AIPlayer(difficulty: difficulty)
                .chooseWellSlots(dealtCount: engine.state.players[seat].hand.count)
            try engine.chooseWell(slots: slots, by: chooser)
        }

        var turns = 0
        while !engine.state.isOver && turns < 4_000 {
            turns += 1
            let current = engine.state.currentPlayer
            let ai = AIPlayer(difficulty: current.kind.difficulty ?? .sharp)
            guard let move = ai.nextMove(for: current.id, engine: engine) else { break }

            switch move.kind {
            case .play(let cardID, let declaration):
                if engine.state.pendingWell?.card.id == cardID {
                    try engine.resolveWell(by: current.id, declaration: declaration)
                } else {
                    try engine.play(cardID: cardID, by: current.id, declaration: declaration)
                }
            case .useWell:
                try engine.drawFromWell(by: current.id, slot: 0)
            case .skip:
                try engine.skip(by: current.id)
            case .snackoo(let kind):
                try engine.declareSnackoo(by: current.id, kind: kind)
            case .snackooWell:
                try engine.snackooWellCard(by: current.id)
            case .concede:
                if engine.state.pendingWell != nil {
                    try engine.concedeWellCard(by: current.id)
                } else {
                    try engine.concedeStranded(by: current.id)
                }
            }
        }
        return engine.state.winnerID
    }

    /// Head to head over many deals. Seats alternate so neither tier gets the
    /// advantage of always leading.
    private func winRate(
        _ challenger: Difficulty, against defender: Difficulty, games: Int = 60
    ) throws -> Double {
        var wins = 0
        var played = 0
        for seed in UInt32(1)...UInt32(games) {
            let challengerFirst = seed.isMultiple(of: 2)
            let seats: [(String, String, PlayerState.PlayerKind)] = challengerFirst
                ? [("x", "X", .ai(challenger)), ("y", "Y", .ai(defender))]
                : [("x", "X", .ai(defender)), ("y", "Y", .ai(challenger))]
            guard let winner = try playOut(seats: seats, seed: seed) else { continue }
            played += 1
            let challengerID = challengerFirst ? "x" : "y"
            if winner == challengerID { wins += 1 }
        }
        XCTAssertGreaterThan(played, games / 2, "Too many games failed to finish to judge anything")
        return Double(wins) / Double(max(1, played))
    }

    func testMercilessBeatsRuthless() throws {
        let rate = try winRate(.merciless, against: .ruthless)
        print("MERCILESS vs RUTHLESS: \(Int(rate * 100))%")
        XCTAssertGreaterThan(
            rate, 0.55,
            "The new top tier should be meaningfully stronger than the old one, not just different"
        )
    }

    func testMercilessBeatsCasualHeavily() throws {
        let rate = try winRate(.merciless, against: .casual)
        print("MERCILESS vs CASUAL: \(Int(rate * 100))%")
        XCTAssertGreaterThan(rate, 0.62, "It should be well clear of the easiest tier")
    }

    /// The existing ladder should still hold.
    func testRuthlessBeatsCasual() throws {
        let rate = try winRate(.ruthless, against: .casual)
        print("RUTHLESS vs CASUAL: \(Int(rate * 100))%")
        XCTAssertGreaterThan(rate, 0.5)
    }
}
