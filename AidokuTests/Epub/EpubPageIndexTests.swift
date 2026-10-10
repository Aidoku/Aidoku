//
//  EpubPageIndexTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

@testable import Aidoku
import Foundation
import Testing

/// The page index is the arithmetic behind a toolbar that describes a whole book. Its failures are
/// off-by-ones in a number the reader sees on every page turn, and a wrong answer is
/// indistinguishable from a right one without knowing the counts, so every case here states the
/// counts it expects.
@Suite
struct EpubPageIndexTests {
    private static let spine = ["a.xhtml", "b.xhtml", "c.xhtml"]

    private static func measured(_ counts: [Int]) -> EpubPageIndex {
        var index = EpubPageIndex(spinePaths: spine)
        for (position, count) in counts.enumerated() {
            index.setPageCount(count, forDocumentAt: position)
        }
        return index
    }

    @Test func anUnmeasuredBookKnowsOnlyItsSpine() {
        let index = EpubPageIndex(spinePaths: Self.spine)

        #expect(index.documentCount == 3)
        #expect(index.measuredDocumentCount == 0)
        #expect(!index.isComplete)
        #expect(index.total == 0)
        #expect(index.bookPage(forDocumentAt: 0, page: 0) == nil)
        #expect(index.position(ofBookPage: 0) == nil)
    }

    @Test func theTotalIsTheSumOfTheCounts() {
        let index = Self.measured([4, 3, 5])

        #expect(index.isComplete)
        #expect(index.total == 12)
        #expect(index.measuredDocumentCount == 3)
    }

    /// The prefix sum, stated by hand: document 1 starts at 4, document 2 at 7.
    @Test func aBookPageIsTheDocumentsStartPlusThePage() {
        let index = Self.measured([4, 3, 5])

        #expect(index.bookPage(forDocumentAt: 0, page: 0) == 0)
        #expect(index.bookPage(forDocumentAt: 0, page: 3) == 3)
        #expect(index.bookPage(forDocumentAt: 1, page: 0) == 4)
        #expect(index.bookPage(forDocumentAt: 1, page: 2) == 6)
        #expect(index.bookPage(forDocumentAt: 2, page: 0) == 7)
        #expect(index.bookPage(forDocumentAt: 2, page: 4) == 11)
    }

    /// The inverse of the case above, over every page of the book, so the two cannot drift apart.
    @Test func aPositionRoundTripsThroughItsBookPage() throws {
        let index = Self.measured([4, 3, 5])

        for page in 0..<index.total {
            let position = try #require(index.position(ofBookPage: page))
            #expect(index.bookPage(forDocumentAt: position.document, page: position.page) == page)
        }
    }

    @Test func boundariesFallInTheDocumentTheyStart() throws {
        let index = Self.measured([4, 3, 5])

        #expect(index.position(ofBookPage: 3) == .init(document: 0, page: 3))
        #expect(index.position(ofBookPage: 4) == .init(document: 1, page: 0))
        #expect(index.position(ofBookPage: 6) == .init(document: 1, page: 2))
        #expect(index.position(ofBookPage: 7) == .init(document: 2, page: 0))
    }

    @Test func pagesOutsideTheBookHaveNoPosition() {
        let index = Self.measured([4, 3, 5])

        #expect(index.position(ofBookPage: -1) == nil)
        #expect(index.position(ofBookPage: 12) == nil)
        #expect(index.bookPage(forDocumentAt: 0, page: 4) == nil)
        #expect(index.bookPage(forDocumentAt: 3, page: 0) == nil)
        #expect(index.bookPage(forDocumentAt: 0, page: -1) == nil)
    }

    /// The measurement pass walks the spine in order, so the answers become available from the
    /// front. A document whose predecessors are unmeasured cannot be placed at all.
    @Test func aPositionNeedsEveryEarlierDocumentMeasured() {
        var index = EpubPageIndex(spinePaths: Self.spine)
        index.setPageCount(5, forDocumentAt: 2)

        #expect(index.total == 5)
        #expect(!index.isComplete)
        // Its own count is known, but nothing can say how many pages precede it.
        #expect(index.pageCount(forDocumentAt: 2) == 5)
        #expect(index.bookPage(forDocumentAt: 2, page: 0) == nil)

        index.setPageCount(4, forDocumentAt: 0)
        #expect(index.bookPage(forDocumentAt: 0, page: 1) == 1)
        // Document 1 is still missing, so document 2 is still unplaceable.
        #expect(index.bookPage(forDocumentAt: 2, page: 0) == nil)

        index.setPageCount(3, forDocumentAt: 1)
        #expect(index.bookPage(forDocumentAt: 2, page: 0) == 7)
    }

    /// A page beyond the measured run may belong to any document that follows, so it is refused
    /// rather than guessed at.
    @Test func aPositionBeyondTheMeasuredRunIsRefused() {
        var index = EpubPageIndex(spinePaths: Self.spine)
        index.setPageCount(4, forDocumentAt: 0)

        #expect(index.position(ofBookPage: 3) == .init(document: 0, page: 3))
        #expect(index.position(ofBookPage: 4) == nil)
    }

    /// Every count belongs to a viewport, so a rotation invalidates all of them.
    @Test func invalidatingKeepsTheSpineAndForgetsTheCounts() {
        var index = Self.measured([4, 3, 5])
        index.invalidate()

        #expect(index.documentCount == 3)
        #expect(index.spinePaths == Self.spine)
        #expect(index.total == 0)
        #expect(index.measuredDocumentCount == 0)
        #expect(!index.isComplete)
    }

    @Test func remeasuringReplacesACount() {
        var index = Self.measured([4, 3, 5])
        index.setPageCount(6, forDocumentAt: 0)

        #expect(index.total == 14)
        #expect(index.bookPage(forDocumentAt: 1, page: 0) == 6)
    }

    /// The renderer reports at least one page for an empty document, so a count below one is a
    /// caller error rather than a state to represent.
    @Test func aDocumentOccupiesAtLeastOnePage() {
        var index = Self.measured([4, 3, 5])
        index.setPageCount(0, forDocumentAt: 1)

        #expect(index.pageCount(forDocumentAt: 1) == 1)
        #expect(index.total == 10)
    }

    /// `(page + anchor) / total` — the caller says where within the page the reading position
    /// sits (the leading edge for one column or scroll, the last column's edge for a spread), and
    /// the index turns it into a place in the book.
    @Test func progressionPlacesTheAnchorWithinThePage() throws {
        let index = Self.measured([4, 3, 5])

        #expect(try #require(index.progression(forDocumentAt: 0, page: 0, anchor: 0)) == 0)
        #expect(try #require(index.progression(forDocumentAt: 2, page: 4, anchor: 0.5)) == 11.5 / 12)

        // Document 1 starts at book page 4 of the book's 12.
        let anchored = try #require(index.progression(forDocumentAt: 1, page: 0, anchor: 0.5))
        #expect(abs(anchored - 4.5 / 12) < 0.000_001)
    }

    /// The restore path computes `floor(fraction * total + ε)` — the page containing the place —
    /// so the same layout must land on the same page for every page of the book and every anchor;
    /// the anchor is a claim about other layouts, not a drift on this one.
    @Test func progressionRoundTripsExactlyOnTheSameLayout() throws {
        let index = Self.measured([4, 3, 5])
        let anchors: [Double] = [0, 0.5]
        for anchor in anchors {
            for page in 0..<12 {
                let position = try #require(index.position(ofBookPage: page))
                let fraction = try #require(
                    index.progression(forDocumentAt: position.document, page: position.page, anchor: anchor)
                )
                #expect(min(Int(fraction * Double(index.total) + 0.01), index.total - 1) == page)
            }
        }
    }

    /// A fraction of a lower bound overstates how far through the book the reader is, and this
    /// value is written to storage.
    @Test func progressionIsWithheldUntilTheBookIsMeasured() {
        var index = EpubPageIndex(spinePaths: Self.spine)
        index.setPageCount(4, forDocumentAt: 0)
        index.setPageCount(3, forDocumentAt: 1)

        #expect(index.bookPage(forDocumentAt: 1, page: 2) == 6)
        #expect(index.progression(forDocumentAt: 1, page: 2, anchor: 0) == nil)

        index.setPageCount(5, forDocumentAt: 2)
        #expect(index.progression(forDocumentAt: 1, page: 2, anchor: 0) != nil)
    }

    @Test func aSinglePageBookDoesNotDivideByZero() throws {
        var index = EpubPageIndex(spinePaths: ["only.xhtml"])
        index.setPageCount(1, forDocumentAt: 0)

        #expect(index.total == 1)
        #expect(try #require(index.progression(forDocumentAt: 0, page: 0, anchor: 0)) == 0)
    }

    @Test func anEmptySpineIsNotComplete() {
        let index = EpubPageIndex(spinePaths: [])

        #expect(index.documentCount == 0)
        #expect(index.total == 0)
        #expect(!index.isComplete)
        #expect(index.position(ofBookPage: 0) == nil)
    }
}
