//
//  SeededRandom.swift
//  Deterministic RNG so tests can pin exact deals and so a "replay this seed"
//  feature stays possible.
//

import Foundation

/// mulberry32 — small, fast, and good enough for shuffling a card deck.
/// Matches the generator used by the original JS engine so ported test
/// fixtures produce comparable deals.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt32

    init(seed: UInt32) {
        self.state = seed
    }

    private mutating func nextUInt32() -> UInt32 {
        state = state &+ 0x6D2B_79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t = t ^ (t &+ ((t ^ (t >> 7)) &* (t | 61)))
        return t ^ (t >> 14)
    }

    mutating func next() -> UInt64 {
        let high = UInt64(nextUInt32())
        let low = UInt64(nextUInt32())
        return (high << 32) | low
    }
}

/// The engine funnels *every* random decision through this box so a game is
/// either fully deterministic (seeded) or fully system-random, with no
/// accidental mixing of the two.
final class RandomSource {
    private var generator: SeededGenerator
    private let isSeeded: Bool

    init(seed: UInt32? = nil) {
        if let seed {
            self.generator = SeededGenerator(seed: seed)
            self.isSeeded = true
        } else {
            self.generator = SeededGenerator(seed: UInt32.random(in: 0...UInt32.max))
            self.isSeeded = false
        }
        _ = isSeeded // retained for clarity/debugging
    }

    func shuffled<T>(_ items: [T]) -> [T] {
        var array = items
        guard array.count > 1 else { return array }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            let j = Int(generator.next() % UInt64(i + 1))
            array.swapAt(i, j)
        }
        return array
    }

    func int(below upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(generator.next() % UInt64(upperBound))
    }

    func double() -> Double {
        Double(generator.next() % 1_000_000) / 1_000_000.0
    }
}
