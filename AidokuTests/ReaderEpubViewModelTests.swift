//
//  ReaderEpubViewModelTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

@testable import Aidoku
import Foundation
import Testing
import UIKit
import WebKit

/// One ePub is one chapter, so the interesting behaviour is at the seams between spine documents: a
/// page turn at the end of one continues into the next, and a turn back at the start of one lands
/// on the **last** page of the previous rather than its first.
@Suite(.serialized)
@MainActor
struct ReaderEpubViewModelTests {
    private static let viewport = CGSize(width: 320, height: 480)

    /// Four documents of deliberately different lengths, so a reader that lands on the wrong page
    /// of the right document is still visible.
    private static func makeBook() throws -> URL {
        try EpubFixture.makeBook(documents: [40, 1, 25, 6]).url
    }

    private func makeViewModel(_ url: URL) throws -> ReaderEpubViewModel {
        try ReaderEpubViewModel(bookURL: url)
    }

    /// Mirrors what the view controller does: place the web view, let it settle, then open the
    /// book at the size it settled at. A predicted size and a settled size that disagree invalidate
    /// every page count.
    private func start(_ viewModel: ReaderEpubViewModel, atDocument document: Int = 0) async throws {
        let renderer = try await viewModel.prepareRenderer()
        renderer.webView.frame = CGRect(origin: .zero, size: Self.viewport)
        renderer.webView.layoutIfNeeded()
        try await viewModel.open(viewport: Self.viewport, atDocument: document)
    }

    private func waitUntilMeasured(_ viewModel: ReaderEpubViewModel, timeout: TimeInterval = 20) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !viewModel.isMeasured && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        try #require(viewModel.isMeasured, "the book was not measured within \(timeout)s")
    }

    @Test func aBookOpensOnTheFirstPageOfTheFirstDocument() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }

        #expect(viewModel.currentDocument == 0)
        #expect(viewModel.pageInDocument == 0)
        #expect(viewModel.bookPage == 0)
        // The opening document is counted by the reading renderer on the way in, so a total exists
        // before the pass has been anywhere.
        #expect(viewModel.bookTotal > 0)
    }

    @Test func turningForwardStaysInTheDocumentUntilItsEnd() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }

        let count = try #require(viewModel.index.pageCount(forDocumentAt: 0))
        try #require(count > 1, "the fixture's first document must span more than one page")

        await viewModel.moveForward()
        #expect(viewModel.currentDocument == 0)
        #expect(viewModel.pageInDocument == 1)
    }

    /// The seam forwards: the last page of a document turns into the first page of the next.
    @Test func turningForwardAtTheEndEntersTheNextDocument() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }

        let count = try #require(viewModel.index.pageCount(forDocumentAt: 0))
        for _ in 0..<count {
            await viewModel.moveForward()
        }

        #expect(viewModel.currentDocument == 1)
        #expect(viewModel.pageInDocument == 0)
    }

    /// The seam backwards, which is the asymmetric one: the previous document's **last** page.
    @Test func turningBackAtTheStartEntersThePreviousDocumentsLastPage() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel, atDocument: 1)
        defer { viewModel.renderer?.webView.stopLoading() }
        try #require(viewModel.currentDocument == 1)
        try #require(viewModel.pageInDocument == 0)

        await viewModel.moveBackward()

        #expect(viewModel.currentDocument == 0)
        let count = try #require(viewModel.index.pageCount(forDocumentAt: 0))
        #expect(viewModel.pageInDocument == count - 1)
    }

    @Test func aBookDoesNotTurnBackPastItsStart() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }

        await viewModel.moveBackward()

        #expect(viewModel.currentDocument == 0)
        #expect(viewModel.pageInDocument == 0)
    }

    @Test func aBookDoesNotTurnForwardPastItsEnd() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        let last = viewModel.spinePaths.count - 1
        try await start(viewModel, atDocument: last)
        defer { viewModel.renderer?.webView.stopLoading() }

        let count = try #require(viewModel.index.pageCount(forDocumentAt: last))
        for _ in 0..<(count + 2) {
            await viewModel.moveForward()
        }

        #expect(viewModel.currentDocument == last)
        #expect(viewModel.pageInDocument == count - 1)
    }

    /// What the slider asks for. A page in another document has to load it.
    @Test func showingABookPageCrossesIntoTheRightDocument() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }
        try await waitUntilMeasured(viewModel)

        let target = try #require(viewModel.index.bookPage(forDocumentAt: 2, page: 1))
        await viewModel.showBookPage(target)

        #expect(viewModel.currentDocument == 2)
        #expect(viewModel.pageInDocument == 1)
        #expect(viewModel.bookPage == target)
    }

    /// A page the index cannot place is refused rather than guessed at, so the reader stays put.
    @Test func showingAnUnplaceableBookPageDoesNothing() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }
        try await waitUntilMeasured(viewModel)

        let document = viewModel.currentDocument
        let page = viewModel.pageInDocument
        await viewModel.showBookPage(viewModel.bookTotal + 100)

        #expect(viewModel.currentDocument == document)
        #expect(viewModel.pageInDocument == page)
    }

    /// The pass fills in the documents the reader has not visited, and only then is the total final
    /// and a progression available to persist.
    @Test func theMeasurementPassCompletesTheBook() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }

        #expect(viewModel.progression == nil, "a fraction of a lower bound must not be published")

        try await waitUntilMeasured(viewModel)

        #expect(viewModel.bookTotal > 0)
        #expect(viewModel.progression == 0, "the first page of the book is the start of it")

        let sum = (0..<viewModel.spinePaths.count).reduce(0) { total, document in
            total + (viewModel.index.pageCount(forDocumentAt: document) ?? 0)
        }
        #expect(viewModel.bookTotal == sum)
    }

    /// The end of the book is exactly 1, matching the `index / (count - 1)` convention the text
    /// readers already write into the same `scrollPosition` column.
    @Test func theEndOfTheBookIsProgressionOne() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        let last = viewModel.spinePaths.count - 1
        try await start(viewModel, atDocument: last)
        defer { viewModel.renderer?.webView.stopLoading() }
        try await waitUntilMeasured(viewModel)

        let count = try #require(viewModel.index.pageCount(forDocumentAt: last))
        await viewModel.showBookPage(viewModel.bookTotal - 1)

        #expect(viewModel.currentDocument == last)
        #expect(viewModel.pageInDocument == count - 1)
        #expect(viewModel.progression == 1)
    }

    /// The discriminator that routes a chapter to this reader, since the reading-mode picker does
    /// not offer an ePub entry and the choice is inferred from page content as the text reader's is.
    @Test func onlyAnArchiveEndingInEpubIsAnEpubPage() {
        func page(zipURL: String?, imageURL: String? = "OEBPS/1.xhtml") -> Page {
            Page(sourceId: "local", chapterId: "c", imageURL: imageURL, zipURL: zipURL)
        }

        #expect(page(zipURL: "file:///books/Book.epub").isEpubPage)
        #expect(page(zipURL: "file:///books/Book.EPUB").isEpubPage)
        #expect(!page(zipURL: "file:///books/Book.cbz").isEpubPage)
        #expect(!page(zipURL: nil).isEpubPage)
        // A text page inside a cbz stays a text page: the two are decided by different things.
        #expect(!page(zipURL: "file:///books/Book.cbz", imageURL: "1.txt").isEpubPage)
        #expect(page(zipURL: "file:///books/Book.cbz", imageURL: "1.txt").isTextPage)
    }

    /// A count belongs to a viewport, so a resize drops every count and starts again.
    @Test func aViewportChangeRecountsTheBook() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }
        try await waitUntilMeasured(viewModel)
        let narrow = viewModel.bookTotal

        viewModel.renderer?.webView.frame = CGRect(origin: .zero, size: CGSize(width: 640, height: 480))
        viewModel.viewportChanged(to: CGSize(width: 640, height: 480))
        #expect(!viewModel.isMeasured, "the counts belonging to the old size must be dropped")

        try await waitUntilMeasured(viewModel)
        #expect(viewModel.bookTotal < narrow, "a wider viewport holds more text per page")
    }

    /// A layout pass arriving before the book is opened starts nothing.
    ///
    /// A host places the web view and lays it out before opening the book in it, which is a size
    /// change and reaches `viewportChanged`. Counting the spine from there measures a book that has
    /// not been opened, and `open` then starts a second pass across the same renderer while the
    /// first is still walking it. See `aPassWaitsForTheOneItSupersededBeforeMeasuring` for what the
    /// overlap does to the counts.
    @Test func aViewportChangeBeforeOpeningCountsNothing() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        viewModel.viewportChanged(to: Self.viewport)

        // Long enough for a pass to have counted the fixture's four documents several times over.
        try await Task.sleep(nanoseconds: 2_000_000_000)

        #expect(viewModel.bookTotal == 0, "a book that has not been opened was measured")
        #expect(!viewModel.isMeasured)
    }

    /// A page asked for before the index can place it is held until it can be.
    ///
    /// Only the opening document is counted by the time a book is open, so a reader resuming
    /// anywhere else asks for a page the index cannot resolve. Dropping the request leaves them at
    /// page 1, and closing the reader then writes that 1 over the position they were resuming to.
    @Test func aResumeBeyondTheCountedDocumentsIsHeldUntilItCanBePlaced() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        // What page the last document starts at is a property of the fixture at this size, so it is
        // measured rather than assumed.
        let target: Int
        do {
            let measured = try makeViewModel(url)
            try await start(measured)
            defer { measured.renderer?.webView.stopLoading() }
            try await waitUntilMeasured(measured)
            target = try #require(measured.index.startOfDocument(at: 3))
        }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }
        // The pass checks this before each load and has not reached its first one yet, so nothing
        // beyond the opening document is counted while it is held.
        viewModel.pauseMeasuring()

        await viewModel.showBookPage(target)
        #expect(viewModel.pendingBookPage == target, "the request was dropped rather than held")
        #expect(!viewModel.canShowPendingBookPage)
        #expect(viewModel.currentDocument == 0, "the reader moved to a page the index cannot place")

        viewModel.resumeMeasuring()
        try await waitUntilMeasured(viewModel)

        #expect(viewModel.canShowPendingBookPage)
        await viewModel.showPendingBookPage()
        #expect(viewModel.currentDocument == 3)
        #expect(viewModel.bookPage == target)
        #expect(viewModel.pendingBookPage == nil)
    }

    /// A reader who turns a page has taken over from the resume, so it is abandoned.
    @Test func aPageTurnAbandonsAHeldResume() async throws {
        let url = try Self.makeBook()
        defer { EpubFixture.remove(url) }

        let viewModel = try makeViewModel(url)
        try await start(viewModel)
        defer { viewModel.renderer?.webView.stopLoading() }
        viewModel.pauseMeasuring()

        // Beyond anything the fixture holds, so it stays unplaceable for the rest of the test.
        await viewModel.showBookPage(10_000)
        #expect(viewModel.pendingBookPage == 10_000)

        await viewModel.moveForward()
        #expect(viewModel.pendingBookPage == nil)
        #expect(!viewModel.canShowPendingBookPage)
    }
}
