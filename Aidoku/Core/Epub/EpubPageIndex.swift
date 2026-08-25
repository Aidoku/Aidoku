//
//  EpubPageIndex.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation

// prefix sums over counts that arrive one document at a time. every answer is nil rather than
// approximated while they are incomplete: a total that grows is honest, a position that moves is not
struct EpubPageIndex {
    let spinePaths: [String]

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

    var total: Int {
        counts.reduce(into: 0) { total, count in
            if let count { total += count }
        }
    }

    mutating func setPageCount(_ count: Int, forDocumentAt index: Int) {
        guard counts.indices.contains(index) else { return }
        counts[index] = max(count, 1)
    }

    func pageCount(forDocumentAt index: Int) -> Int? {
        counts.indices.contains(index) ? counts[index] : nil
    }

    mutating func invalidate() {
        counts = Array(repeating: nil, count: spinePaths.count)
    }

    func bookPage(forDocumentAt index: Int, page: Int) -> Int? {
        guard let count = pageCount(forDocumentAt: index), page >= 0, page < count else { return nil }
        guard let start = startOfDocument(at: index) else { return nil }
        return start + page
    }

    // nil past the measured run at the front of the spine
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
    // the leading edge for one column, (n - 1) / n for an n-column spread
    func progression(forDocumentAt index: Int, page: Int, anchor: Double) -> Double? {
        guard isComplete, let bookPage = bookPage(forDocumentAt: index, page: page) else { return nil }
        return (Double(bookPage) + anchor) / Double(total)
    }
}
