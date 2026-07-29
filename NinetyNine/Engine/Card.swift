//
//  Card.swift
//  The atomic vocabulary of 99: suits, ranks, and cards.
//
//  This file — and everything else in Engine/ — is deliberately free of any
//  UI framework import. The engine is a pure, deterministic state machine so
//  it can be exhaustively unit tested and reused unchanged (server, watch,
//  whatever comes later).
//

import Foundation

// MARK: - Suit

enum Suit: String, CaseIterable, Codable, Hashable, Sendable {
    case spades = "S"
    case hearts = "H"
    case diamonds = "D"
    case clubs = "C"

    /// The glyph drawn on card faces and in the suit-lock badge.
    var glyph: String {
        switch self {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        case .clubs: return "♣"
        }
    }

    var isRed: Bool { self == .hearts || self == .diamonds }

    /// Spelled out for VoiceOver and for the "locked to Hearts" banner.
    var displayName: String {
        switch self {
        case .spades: return "Spades"
        case .hearts: return "Hearts"
        case .diamonds: return "Diamonds"
        case .clubs: return "Clubs"
        }
    }
}

// MARK: - Rank

enum Rank: String, CaseIterable, Codable, Hashable, Sendable {
    case ace = "A"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"
    case ten = "10"
    case jack = "J"
    case queen = "Q"
    case king = "K"

    /// What's printed in the card's corner index.
    var label: String { rawValue }

    var displayName: String {
        switch self {
        case .ace: return "Ace"
        case .jack: return "Jack"
        case .queen: return "Queen"
        case .king: return "King"
        default: return rawValue
        }
    }

    /// True for ranks that carry a special ability rather than a plain value.
    var isSpecial: Bool {
        switch self {
        case .ace, .four, .eight, .nine, .ten, .jack, .queen, .king: return true
        default: return false
        }
    }

    /// One-line reminder surfaced in the UI so players never have to leave the
    /// table to remember what a card does.
    var abilitySummary: String {
        switch self {
        case .ace: return "Worth 1 or 11 — you choose"
        case .four: return "Worth 0, and reverses turn order"
        case .eight: return "Worth 8, and locks the suit"
        case .nine: return "Slams the tally to exactly 99"
        case .ten: return "Worth −10"
        case .jack: return "Worth 0 — a free pass"
        case .queen: return "Wild — copies any card you name"
        case .king: return "Worth 10"
        default: return "Worth \(rawValue)"
        }
    }
}

// MARK: - Card

/// A single physical card. `id` is unique per *instance* (not per rank+suit)
/// so SwiftUI can track a specific card through deal → hand → discard
/// animations, and so a reshuffled deck never collides with itself.
struct Card: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let rank: Rank
    let suit: Suit

    var shortName: String { "\(rank.label)\(suit.glyph)" }
    var accessibleName: String { "\(rank.displayName) of \(suit.displayName)" }
}

// MARK: - Deck construction

enum Deck {
    /// A fresh, ordered 52-card deck. Ids are assigned deterministically from
    /// position, which keeps seeded games perfectly reproducible.
    static func standard() -> [Card] {
        var cards: [Card] = []
        cards.reserveCapacity(52)
        var nextID = 0
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                cards.append(Card(id: nextID, rank: rank, suit: suit))
                nextID += 1
            }
        }
        return cards
    }
}
