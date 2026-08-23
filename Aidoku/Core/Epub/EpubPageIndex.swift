//
//  EpubPageIndex.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation

/// Where a page sits in a whole book, given page counts that arrive one spine document at a time.
///
/// One ePub is one chapter, so the toolbar's page counter and slider describe a book rather than a
/// spine document. That total is not available when a book opens: a count belongs to a document
/// laid out at a viewport, and measuring one costs a load. The counts therefore arrive
/// progressively, and every question asked of this type has to be answerable while it is
/// incomplete.
///
/// It answers three, and the arithmetic is prefix sums over the counts:
///   - what is the book's total, which is a lower bound until every document is measured
///   - which page of the book is page *p* of document *d*
///   - which document and page does book page *n* fall in, which is what a dragged slider needs
///
/// A position needs every *preceding* document measured, not every document, so the answers become
/// available from the front of the spine as measurement walks it. Where they cannot be answered
/// they are `nil` rather than approximated. A total that grows is honest; a position that moves
/// under the reader because a document it had already passed was counted late is not.
///
/// Nothing here touches UIKit or WebKit. It is arithmetic over a spine, and it is what both the
/// current page-turn mechanism and a future web-view-per-page one would ask.
struct EpubPageIndex {
    /// Spine document paths in reading order, as `chapters.flatMap(\.hrefs)` yields them.
    let spinePaths: [String]

    /// Page counts by spine position, `nil` where the document has not been measured yet.
    private var counts: [Int?]

    /// A place in the book: which spine document, and which page within it. Both zero-based.
    struct Position: Equatable {
        let document: Int
        let page: Int
    }

    init(spinePaths: [String]) {
        self.spinePaths = spinePaths
        self.counts = Array(repeating: nil, count: spinePaths.count)
    }

    var documentCount: Int {
        spinePaths.count
    }

    /// How many documents have been measured, in any order.
    var measuredDocumentCount: Int {
        counts.reduce(into: 0) { total, count in
            if count != nil { total += 1 }
        }
    }

    /// True once every document has a count, and therefore once `total` is the book's real total.
    var isComplete: Bool {
        !counts.isEmpty && counts.allSatisfy { $0 != nil }
    }

    /// The sum of what is known, which is a lower bound on the book until `isComplete`.
    ///
    /// Displaying this as though it were final is what the counter must avoid; see the risk
    /// recorded in `SLICE-3-SPEC.md`. It is exposed because a lower bound is the right input to a
    /// progress indicator that knows it is provisional.
    var total: Int {
        counts.reduce(into: 0) { total, count in
            if let count { total += count }
        }
    }

    /// Records a measurement, replacing any earlier one for the same document.
    ///
    /// Re-measuring is normal rather than exceptional: every count belongs to a viewport, so a
    /// rotation invalidates all of them and the pass runs again.
    ///
    /// A document occupies at least one page even when it is empty, which is what the renderer
    /// reports, so a count below one is a caller error and is clamped rather than stored.
    mutating func setPageCount(_ count: Int, forDocumentAt index: Int) {
        guard counts.indices.contains(index) else { return }
        counts[index] = max(count, 1)
    }

    func pageCount(forDocumentAt index: Int) -> Int? {
        counts.indices.contains(index) ? counts[index] : nil
    }

    /// Forgets every measurement, keeping the spine.
    ///
    /// Called when the viewport changes, since a count measured at one size describes a layout that
    /// no longer exists.
    mutating func invalidate() {
        counts = Array(repeating: nil, count: spinePaths.count)
    }

    /// Which page of the book page `page` of document `index` is.
    ///
    /// `nil` when the document is out of range, when the page is outside it, or when any earlier
    /// document is unmeasured, since the pages before it cannot be counted.
    func bookPage(forDocumentAt index: Int, page: Int) -> Int? {
        guard let count = pageCount(forDocumentAt: index), page >= 0, page < count else { return nil }
        guard let start = startOfDocument(at: index) else { return nil }
        return start + page
    }

    /// Which document and page book page `page` falls in.
    ///
    /// `nil` when the page is negative, or when it falls beyond the measured run of documents at
    /// the front of the spine. A page inside an unmeasured document cannot be located, and a page
    /// past the end of the measured run may belong to any of the documents that follow.
    func position(ofBookPage page: Int) -> Position? {
        guard page >= 0 else { return nil }
        var remaining = page
        for (index, count) in counts.enumerated() {
            guard let count else { return nil }
            if remaining < count {
                return Position(document: index, page: remaining)
            }
            remaining -= count
        }
        return nil
    }

    /// The book page the first page of document `index` sits at, which is the prefix sum before it.
    ///
    /// `nil` when any earlier document is unmeasured.
    func startOfDocument(at index: Int) -> Int? {
        guard spinePaths.indices.contains(index) else { return nil }
        var start = 0
        for earlier in 0..<index {
            guard let count = counts[earlier] else { return nil }
            start += count
        }
        return start
    }

    /// The fraction of the book that page `page` of document `index` sits at, for persistence.
    ///
    /// `(page + anchor) / total`, restored as the page *containing* that place,
    /// `floor(fraction * total)`. The anchor says where within the page the reading position
    /// sits, and the caller knows that where this index does not: the leading edge (0) for a
    /// single column or a scrolling document, whose first visible line is exactly where reading
    /// resumes, and the leading edge of the last column — `(n - 1) / n` — for an n-column spread,
    /// whose earlier columns the reader has been through by the time they leave it.
    ///
    /// Both halves of that convention came from a failure. Anchoring a two-column spread at its
    /// edge restored a one-column iPhone onto the *first* column's text, a page before where the
    /// reader left off; anchoring everything in the middle of the page made switching a paged
    /// book to scroll mode land half a page past the line the reader was on. On the layout that
    /// saved it the fraction floors back to the same page exactly, whatever the anchor.
    ///
    /// The text readers write `index / (count - 1)` to the same `HistoryObject.scrollPosition`
    /// column, but each reader only ever reads its own values back, so the conventions may differ.
    ///
    /// `nil` until the book is completely measured. A fraction of a lower bound overstates how far
    /// through the book the reader is, and it is written to storage, so it is worth withholding
    /// rather than approximating.
    func progression(forDocumentAt index: Int, page: Int, anchor: Double) -> Double? {
        guard isComplete, let bookPage = bookPage(forDocumentAt: index, page: page) else { return nil }
        return (Double(bookPage) + anchor) / Double(total)
    }
}
