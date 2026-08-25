//
//  EpubPageIndex.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation

// prefix sums over page counts that arrive one document at a time, since a count belongs to a
// document laid out at a viewport and measuring one costs a load. every question here has to be
// answerable while the counts are incomplete, and is nil rather than approximated where it is not:
// a total that grows is honest, a position that moves under the reader is not
struct EpubPageIndex {
    let spinePaths: [String]

    // nil where the document has not been measured yet
    private var counts: [Int?]

    // both zero-based
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

    var measuredDocumentCount: Int {
        counts.reduce(into: 0) { total, count in
            if count != nil { total += 1 }
        }
    }

    var isComplete: Bool {
        !counts.isEmpty && counts.allSatisfy { $0 != nil }
    }

    // a lower bound on the book until isComplete, and must not be displayed as though it were final
    var total: Int {
        counts.reduce(into: 0) { total, count in
            if let count { total += count }
        }
    }

    // re-measuring is normal: every count belongs to a viewport, so a rotation invalidates all of
    // them. a document occupies at least one page even when empty, so a lower count is clamped
    mutating func setPageCount(_ count: Int, forDocumentAt index: Int) {
        guard counts.indices.contains(index) else { return }
        counts[index] = max(count, 1)
    }

    func pageCount(forDocumentAt index: Int) -> Int? {
        counts.indices.contains(index) ? counts[index] : nil
    }

    // called when the viewport changes, since a count measured at one size describes a layout that
    // no longer exists
    mutating func invalidate() {
        counts = Array(repeating: nil, count: spinePaths.count)
    }

    // nil when any earlier document is unmeasured, since the pages before it cannot be counted
    func bookPage(forDocumentAt index: Int, page: Int) -> Int? {
        guard let count = pageCount(forDocumentAt: index), page >= 0, page < count else { return nil }
        guard let start = startOfDocument(at: index) else { return nil }
        return start + page
    }

    // nil past the measured run of documents at the front of the spine, since a page beyond it may
    // belong to any of the documents that follow
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

    func startOfDocument(at index: Int) -> Int? {
        guard spinePaths.indices.contains(index) else { return nil }
        var start = 0
        for earlier in 0..<index {
            guard let count = counts[earlier] else { return nil }
            start += count
        }
        return start
    }

    // (page + anchor) / total, restored as floor(fraction * total). the caller picks the anchor:
    // the leading edge for one column or a scrolling document, (n - 1) / n for an n-column spread,
    // whose earlier columns have been read by the time the reader leaves it. both halves came from
    // a restore landing a page off. nil until the book is measured, since a fraction of a lower
    // bound overstates how far through it the reader is and this is written to storage
    func progression(forDocumentAt index: Int, page: Int, anchor: Double) -> Double? {
        guard isComplete, let bookPage = bookPage(forDocumentAt: index, page: page) else { return nil }
        return (Double(bookPage) + anchor) / Double(total)
    }
}
