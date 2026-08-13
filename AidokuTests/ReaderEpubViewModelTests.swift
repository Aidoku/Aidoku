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
        try await viewModel.start(viewport: Self.viewport)
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
        try await viewModel.start(viewport: Self.viewport)
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
        try await viewModel.start(viewport: Self.viewport)
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
        try await viewModel.start(viewport: Self.viewport, atDocument: 1)
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
        try await viewModel.start(viewport: Self.viewport)
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
        try await viewModel.start(viewport: Self.viewport, atDocument: last)
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
        try await viewModel.start(viewport: Self.viewport)
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
        try await viewModel.start(viewport: Self.viewport)
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
        try await viewModel.start(viewport: Self.viewport)
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
        try await viewModel.start(viewport: Self.viewport, atDocument: last)
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
        try await viewModel.start(viewport: Self.viewport)
        defer { viewModel.renderer?.webView.stopLoading() }
        try await waitUntilMeasured(viewModel)
        let narrow = viewModel.bookTotal

        viewModel.renderer?.webView.frame = CGRect(origin: .zero, size: CGSize(width: 640, height: 480))
        viewModel.viewportChanged(to: CGSize(width: 640, height: 480))
        #expect(!viewModel.isMeasured, "the counts belonging to the old size must be dropped")

        try await waitUntilMeasured(viewModel)
        #expect(viewModel.bookTotal < narrow, "a wider viewport holds more text per page")
    }
}
