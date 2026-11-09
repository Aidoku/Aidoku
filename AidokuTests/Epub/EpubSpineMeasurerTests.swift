//
//  EpubSpineMeasurerTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

@testable import Aidoku
import Foundation
import Testing
import UIKit
import WebKit

/// The measurement pass fills a book's page counts while it is being read, so its failures are a
/// total that is wrong rather than a reader that stops working. Counts are therefore asserted
/// against what the documents themselves report rather than against the pass having run.
@Suite(.serialized)
@MainActor
struct EpubSpineMeasurerTests {
    private static let viewport = CGSize(width: 320, height: 480)

    /// Four documents whose lengths differ enough that their counts do, so a pass that reported the
    /// same number for every document, or reported them against the wrong index, is visible.
    private static func makeBook() throws -> (url: URL, paths: [String]) {
        let paths = ["OEBPS/1.xhtml", "OEBPS/2.xhtml", "OEBPS/3.xhtml", "OEBPS/4.xhtml"]
        let paragraphs = [60, 1, 30, 8]
        var entries: [String: Data] = [:]
        for (path, count) in zip(paths, paragraphs) {
            entries[path] = Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: count)).utf8)
        }
        return (try EpubFixture.makeArchive(entries: entries), paths)
    }

    private func measure(
        _ measurer: EpubSpineMeasurer,
        paths: [String],
        skipping: Set<Int> = [],
        viewport: CGSize = EpubSpineMeasurerTests.viewport
    ) async -> (counts: [Int: Int], outcome: EpubSpineMeasurer.Outcome) {
        var counts: [Int: Int] = [:]
        let outcome = await withCheckedContinuation { continuation in
            measurer.start(
                spinePaths: paths,
                viewport: viewport,
                skipping: skipping,
                onCount: { index, count in counts[index] = count },
                onFinish: { continuation.resume(returning: $0) }
            )
        }
        return (counts, outcome)
    }

    /// The counts a pass produces are the counts the renderer produces for the same documents at
    /// the same size, so the two cannot drift apart.
    @Test func aPassCountsEveryDocument() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))
        let (counts, outcome) = await measure(measurer, paths: book.paths)

        #expect(outcome.measured == 4)
        #expect(outcome.failed.isEmpty)
        #expect(!outcome.cancelled)
        #expect(counts.count == 4)

        let renderer = try await EpubFixture.makeRenderer(for: book.url, size: Self.viewport)
        defer { EpubFixture.dismantle(renderer.webView) }
        for (index, path) in book.paths.enumerated() {
            let expected = try await renderer.load(spinePath: path)
            #expect(counts[index] == expected, "document \(index)")
        }
    }

    /// A count belongs to a viewport, so the pass has to produce different totals at different
    /// sizes rather than a number that happens to be self-consistent.
    @Test func aWiderViewportProducesFewerPages() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))
        let narrow = await measure(measurer, paths: book.paths, viewport: CGSize(width: 320, height: 480))
        let wide = await measure(measurer, paths: book.paths, viewport: CGSize(width: 640, height: 480))

        let narrowTotal = narrow.counts.values.reduce(0, +)
        let wideTotal = wide.counts.values.reduce(0, +)
        #expect(narrowTotal > 0)
        #expect(wideTotal > 0)
        #expect(wideTotal < narrowTotal)
    }

    @Test func documentsAlreadyKnownAreNotMeasuredAgain() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))
        let (counts, outcome) = await measure(measurer, paths: book.paths, skipping: [0, 2])

        #expect(outcome.measured == 2)
        #expect(counts.keys.sorted() == [1, 3])
    }

    /// A pass superseded by a viewport change must publish nothing further, or a count taken at the
    /// old size lands in the index the new pass is filling.
    @Test func cancellingStopsThePassAndReportsIt() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))

        var counts: [Int: Int] = [:]
        let outcome = await withCheckedContinuation { continuation in
            measurer.start(
                spinePaths: book.paths,
                viewport: Self.viewport,
                onCount: { index, count in
                    counts[index] = count
                    if index == 0 { measurer.cancel() }
                },
                onFinish: { continuation.resume(returning: $0) }
            )
        }

        #expect(outcome.cancelled)
        #expect(counts.count < book.paths.count)
        #expect(!measurer.isMeasuring)
    }

    /// Starting again cancels what is running, so a rotation cannot leave two passes writing into
    /// the same index.
    @Test func startingAgainSupersedesThePassInFlight() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))

        var firstOutcome: EpubSpineMeasurer.Outcome?
        measurer.start(
            spinePaths: book.paths,
            viewport: Self.viewport,
            onCount: { _, _ in },
            onFinish: { firstOutcome = $0 }
        )
        let (counts, second) = await measure(measurer, paths: book.paths)

        #expect(!second.cancelled)
        #expect(counts.count == 4)
        if let firstOutcome {
            #expect(firstOutcome.cancelled)
        }
    }

    /// A document that cannot be laid out is reported rather than counted as some number of pages,
    /// since what an unreadable document should contribute to a book's total is not this type's
    /// decision.
    @Test func anUnreadableDocumentIsReportedAndThePassContinues() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))
        var paths = book.paths
        paths.insert("OEBPS/missing.xhtml", at: 2)
        let (counts, outcome) = await measure(measurer, paths: paths)

        #expect(outcome.failed == ["OEBPS/missing.xhtml"])
        #expect(outcome.measured == 4)
        #expect(!outcome.cancelled)
        #expect(counts[2] == nil)
        // The documents after the failure are still counted, and still at their own indices.
        #expect(counts[3] != nil)
        #expect(counts[4] != nil)
    }

    @Test func anEmptySpineFinishesWithoutBuildingAWebView() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))
        let (counts, outcome) = await measure(measurer, paths: [])

        #expect(counts.isEmpty)
        #expect(outcome.measured == 0)
        #expect(!outcome.cancelled)
        #expect(!measurer.isMeasuring)
    }

    /// The counts a pass produces are what `EpubPageIndex` is filled with, so the two are exercised
    /// together: a complete pass is what makes a book's total and its progression available.
    @Test func aCompletedPassCompletesThePageIndex() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        var index = EpubPageIndex(spinePaths: book.paths)
        #expect(!index.isComplete)

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))
        var counts: [Int: Int] = [:]
        _ = await withCheckedContinuation { continuation in
            measurer.start(
                spinePaths: book.paths,
                viewport: Self.viewport,
                onCount: { position, count in counts[position] = count },
                onFinish: { continuation.resume(returning: $0) }
            )
        }
        for (position, count) in counts {
            index.setPageCount(count, forDocumentAt: position)
        }

        #expect(index.isComplete)
        #expect(index.total == counts.values.reduce(0, +))
        #expect(index.progression(forDocumentAt: 0, page: 0, anchor: 0) == 0)
        let lastDocument = book.paths.count - 1
        let lastPage = try #require(index.pageCount(forDocumentAt: lastDocument)) - 1
        #expect(
            index.progression(forDocumentAt: lastDocument, page: lastPage, anchor: 0)
                == Double(index.total - 1) / Double(index.total)
        )
    }

    /// A pass may not touch the renderer until the pass it superseded has let go of it.
    ///
    /// Both passes share the measurer's renderer, and a renderer follows one navigation at a time.
    /// Cancellation is cooperative, so a superseded pass stays inside the load it was awaiting; a
    /// successor that loaded into the same web view meanwhile made the two navigations
    /// indistinguishable. Whichever load was resumed with `superseded` had its document recorded as
    /// unmeasurable, and the load that survived measured whatever the web view was left holding and
    /// filed that count under its own path. Both were seen on a real book: a total a document short,
    /// and a total seven pages long because a one page cover was credited with a later document's
    /// eight.
    ///
    /// Asserted as an ordering rather than as a count, since the corruption it produces depends on
    /// which load wins and only some of the outcomes are wrong.
    @Test func aPassWaitsForTheOneItSupersededBeforeMeasuring() async throws {
        let book = try Self.makeBook()
        defer { EpubFixture.remove(book.url) }

        let expected = await measure(
            EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url)),
            paths: book.paths
        )

        let measurer = EpubSpineMeasurer(provider: try EpubZipResourceProvider(url: book.url))
        var events: [String] = []
        var counts: [Int: Int] = [:]
        var restarted = false

        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            // Superseded from inside its own first count, which is as early as a pass can be caught
            // having started work.
            measurer.start(
                spinePaths: book.paths,
                viewport: Self.viewport,
                onCount: { _, _ in
                    guard !restarted else { return }
                    restarted = true
                    measurer.start(
                        spinePaths: book.paths,
                        viewport: Self.viewport,
                        onCount: { position, count in
                            events.append("second.count")
                            counts[position] = count
                        },
                        onFinish: { outcome in
                            events.append("second.finish")
                            continuation.resume(returning: outcome)
                        }
                    )
                },
                onFinish: { _ in events.append("first.finish") }
            )
        }

        let firstFinish = try #require(events.firstIndex(of: "first.finish"))
        let firstSecondCount = try #require(events.firstIndex(of: "second.count"))
        #expect(firstFinish < firstSecondCount, "the superseded pass was still loading: \(events)")

        #expect(outcome.failed.isEmpty)
        #expect(!outcome.cancelled)
        #expect(counts == expected.counts)
    }
}

private typealias Outcome = EpubSpineMeasurer.Outcome
