//
//  PresentationTests.swift
//  Tests for the presentation-layer maths that is easy to get backwards.
//

import XCTest
@testable import NinetyNine

final class StandingsTests: XCTestCase {

    // MARK: - Elimination rank to finishing position

    func testWinnerHasNoEliminationRankAndFinishesFirst() {
        XCTAssertEqual(Standings.position(eliminationRank: nil, of: 4), 1)
    }

    func testFirstPlayerEliminatedFinishesLast() {
        // The direction that's easy to invert: eliminated first == finished last.
        XCTAssertEqual(Standings.position(eliminationRank: 1, of: 3), 3)
        XCTAssertEqual(Standings.position(eliminationRank: 1, of: 6), 6)
    }

    func testLastPlayerEliminatedIsRunnerUp() {
        // With 3 players, the second elimination is the runner-up.
        XCTAssertEqual(Standings.position(eliminationRank: 2, of: 3), 2)
        // With 6 players, the fifth elimination is the runner-up.
        XCTAssertEqual(Standings.position(eliminationRank: 5, of: 6), 2)
    }

    func testMiddlePositions() {
        XCTAssertEqual(Standings.position(eliminationRank: 2, of: 5), 4)
        XCTAssertEqual(Standings.position(eliminationRank: 3, of: 5), 3)
    }

    func testPositionIsClampedIntoRange() {
        XCTAssertEqual(Standings.position(eliminationRank: 99, of: 3), 1)
        XCTAssertEqual(Standings.position(eliminationRank: 0, of: 3), 3)
    }

    // MARK: - Headlines

    func testLastPlaceIsNotCalledRunnerUp() {
        // The exact regression: finishing last in a 3-player game once produced
        // "Runner-up".
        XCTAssertEqual(Standings.placementHeadline(position: 3, of: 3), "First one out")
        XCTAssertEqual(Standings.placementHeadline(position: 2, of: 3), "Runner-up")
    }

    func testHeadlinesAcrossATable() {
        XCTAssertEqual(Standings.placementHeadline(position: 2, of: 6), "Runner-up")
        XCTAssertEqual(Standings.placementHeadline(position: 3, of: 6), "3rd of 6")
        XCTAssertEqual(Standings.placementHeadline(position: 4, of: 6), "4th of 6")
        XCTAssertEqual(Standings.placementHeadline(position: 6, of: 6), "First one out")
    }

    func testHeadlineForTwoPlayerGame() {
        // With two players, second place is both runner-up and first out.
        // Runner-up is the kinder and more accurate framing.
        XCTAssertEqual(Standings.placementHeadline(position: 2, of: 2), "Runner-up")
    }

    func testOrdinals() {
        XCTAssertEqual(Standings.ordinal(1), "1st")
        XCTAssertEqual(Standings.ordinal(2), "2nd")
        XCTAssertEqual(Standings.ordinal(3), "3rd")
        XCTAssertEqual(Standings.ordinal(4), "4th")
        XCTAssertEqual(Standings.ordinal(11), "11th")
    }
}

final class FanLayoutTests: XCTestCase {

    /// The fan must fit the width it's given, for every legal hand size. An
    /// earlier layout picked a card width first and let a 6-card hand overflow
    /// the screen by 37pt on each side.
    func testFanFitsAvailableWidthForEveryHandSize() {
        // Narrowest supported phone width minus the table's horizontal padding,
        // through to a large iPad.
        for availableWidth in [292.0, 346.0, 374.0, 402.0, 430.0, 700.0] as [CGFloat] {
            for cardCount in 1...14 {
                let layout = FanLayout(
                    cardCount: cardCount,
                    availableWidth: availableWidth,
                    availableHeight: 178
                )
                XCTAssertLessThanOrEqual(
                    layout.totalWidth, availableWidth,
                    "A \(cardCount)-card fan overflows \(availableWidth)pt"
                )
            }
        }
    }

    func testCardsStayLargeEnoughToTap() {
        // Apple's 44pt minimum applies to the *tappable* area; cards overlap, so
        // the exposed sliver plus height keeps them reachable. The width floor is
        // what stops a 12-card hand becoming unusable slivers.
        let layout = FanLayout(cardCount: 12, availableWidth: 374, availableHeight: 178)
        XCTAssertGreaterThanOrEqual(layout.cardWidth, 40)
    }

    func testFanNeverExceedsItsHeight() {
        let height: CGFloat = 178
        for cardCount in 1...12 {
            let layout = FanLayout(cardCount: cardCount, availableWidth: 374, availableHeight: height)
            let cardHeight = layout.cardWidth / cardAspectRatio
            XCTAssertLessThanOrEqual(
                cardHeight, height,
                "A \(cardCount)-card fan is taller than its frame"
            )
        }
    }

    func testArcIsShiftedSoTheLowestCardSitsOnTheBottomEdge() {
        // Every card's y must be <= 0 (measured up from the bottom-anchored
        // frame), otherwise the outermost cards hang off the bottom of the screen.
        let layout = FanLayout(cardCount: 6, availableWidth: 374, availableHeight: 178)
        for index in 0..<6 {
            XCTAssertLessThanOrEqual(
                layout.placement(at: index).y, 0.01,
                "Card \(index) hangs below the fan's frame"
            )
        }
    }

    func testFanIsHorizontallyCentred() {
        let layout = FanLayout(cardCount: 7, availableWidth: 374, availableHeight: 178)
        let first = layout.placement(at: 0).x
        let last = layout.placement(at: 6).x
        XCTAssertEqual(first, -last, accuracy: 0.001, "The fan should be symmetric about the centre")
        XCTAssertEqual(layout.placement(at: 3).x, 0, accuracy: 0.001, "The middle card should be centred")
    }

    func testSingleCardHandIsCentredAndFlat() {
        let layout = FanLayout(cardCount: 1, availableWidth: 374, availableHeight: 178)
        let placement = layout.placement(at: 0)
        XCTAssertEqual(placement.x, 0, accuracy: 0.001)
        XCTAssertEqual(placement.angle, 0, accuracy: 0.001)
        XCTAssertEqual(layout.maxArcDrop, 0, accuracy: 0.001)
    }

    func testEmptyHandDoesNotCrash() {
        let layout = FanLayout(cardCount: 0, availableWidth: 374, availableHeight: 178)
        XCTAssertEqual(layout.placement(at: 0).x, 0)
    }
}

final class PaletteTests: XCTestCase {

    /// The tally colour ramp must be monotonic in "danger" — a player glancing at
    /// the gauge should never see it get calmer as the tally climbs.
    func testTallyColourRampIsContinuous() {
        // Sample the ramp and check the red channel rises and green falls overall.
        let low = Palette.tallyColor(pressure: 0.05, isNegative: false).rgbComponents
        let mid = Palette.tallyColor(pressure: 0.6, isNegative: false).rgbComponents
        let high = Palette.tallyColor(pressure: 0.99, isNegative: false).rgbComponents

        XCTAssertGreaterThan(mid.r, low.r, "Mid tally should be warmer than a low one")
        XCTAssertGreaterThan(high.r / max(high.g, 0.001), mid.r / max(mid.g, 0.001),
                             "A near-99 tally should be markedly redder")
    }

    func testNegativeTalliesGetTheCoolColour() {
        let negative = Palette.tallyColor(pressure: 0, isNegative: true).rgbComponents
        XCTAssertGreaterThan(negative.b, negative.r, "A negative tally should read as cool/blue")
    }

    func testPressureIsClamped() {
        // Out-of-range input must not produce a wild colour.
        let over = Palette.tallyColor(pressure: 5, isNegative: false).rgbComponents
        let atCeiling = Palette.tallyColor(pressure: 1, isNegative: false).rgbComponents
        XCTAssertEqual(over.r, atCeiling.r, accuracy: 0.001)
        XCTAssertEqual(over.g, atCeiling.g, accuracy: 0.001)
    }
}

final class PipLayoutTests: XCTestCase {

    func testPipCountsMatchRanks() {
        XCTAssertEqual(PipLayout.pips(for: .ace).count, 1)
        XCTAssertEqual(PipLayout.pips(for: .two).count, 2)
        XCTAssertEqual(PipLayout.pips(for: .five).count, 5)
        XCTAssertEqual(PipLayout.pips(for: .nine).count, 9)
        XCTAssertEqual(PipLayout.pips(for: .ten).count, 10)
    }

    func testCourtCardsHaveNoPips() {
        for rank in [Rank.jack, .queen, .king] {
            XCTAssertTrue(PipLayout.pips(for: rank).isEmpty, "\(rank) should use a court panel")
        }
    }

    func testPipsStayInsideTheUnitField() {
        for rank in Rank.allCases {
            for pip in PipLayout.pips(for: rank) {
                XCTAssertTrue((0...1).contains(pip.x), "\(rank) pip x out of range: \(pip.x)")
                XCTAssertTrue((0...1).contains(pip.y), "\(rank) pip y out of range: \(pip.y)")
            }
        }
    }

    func testLowerHalfPipsAreInverted() {
        // Real cards rotate every pip below the midline.
        let pips = PipLayout.pips(for: .ten)
        XCTAssertTrue(pips.filter { $0.y > 0.5 }.allSatisfy { $0.isInverted })
        XCTAssertTrue(pips.filter { $0.y <= 0.5 }.allSatisfy { !$0.isInverted })
    }

    /// The bug that made 7s through 10s overlap: pip size is derived from the
    /// tightest row spacing, so that spacing must never be smaller than 1/6.
    func testMinimumRowSpacingIsOneSixth() {
        for rank in Rank.allCases {
            let ys = Set(PipLayout.pips(for: rank).map { ($0.y * 600).rounded() / 600 }).sorted()
            guard ys.count > 1 else { continue }
            for index in 1..<ys.count {
                let gap = ys[index] - ys[index - 1]
                XCTAssertGreaterThanOrEqual(
                    gap, 1.0 / 6.0 - 0.001,
                    "\(rank) has rows only \(gap) apart, which the pip size can't accommodate"
                )
            }
        }
    }
}
