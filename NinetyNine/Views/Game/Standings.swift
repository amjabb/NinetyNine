//
//  Standings.swift
//  Turning elimination order into a finishing position, and a position into
//  words.
//
//  This lives outside the view because it's easy to get backwards and worth
//  testing: in 99 the *first* player knocked out finishes *last*, so the two
//  numbers run in opposite directions.
//

import Foundation

enum Standings {

    /// Convert an elimination rank into a finishing position.
    ///
    /// `eliminationRank` is 1 for the first player knocked out. With `total`
    /// players, that player finishes `total`th. The runner-up — the last one
    /// eliminated — has rank `total - 1` and finishes 2nd. The winner is never
    /// eliminated and always finishes 1st.
    static func position(eliminationRank: Int?, of total: Int) -> Int {
        guard let rank = eliminationRank else { return 1 }
        return max(1, min(total, total - rank + 1))
    }

    /// The headline shown to a player who lost, given their finishing position.
    static func placementHeadline(position: Int, of total: Int) -> String {
        if position <= 1 { return "Winner" }
        if position == 2 { return "Runner-up" }
        if position == total { return "First one out" }
        return "\(ordinal(position)) of \(total)"
    }

    static func ordinal(_ value: Int) -> String {
        switch value {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(value)th"
        }
    }
}
