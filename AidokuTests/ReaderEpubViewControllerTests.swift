//
//  ReaderEpubViewControllerTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/14/26.
//

@testable import Aidoku
import AidokuRunner
import Foundation
import Testing
import UIKit
import WebKit

/// What the reader tells its host, asserted against the host rather than against the model.
///
/// The model was exercised on its own for a long time and was correct throughout while the reader
/// was not: two measurement passes overlapped because the host lays its web view out before the
/// book is opened in it, which no test below the view controller could see. These drive the real
/// view controller in a window, with a delegate that records everything it is handed.
@Suite(.serialized)
@MainActor
struct ReaderEpubViewControllerTests {
    private static let viewport = CGSize(width: 320, height: 480)

    /// Records the conversation rather than acting on it, so a call that should never happen is
    /// visible as a value rather than as a side effect.
    final class RecordingDelegate: NSObject, ReaderHoldingDelegate {
        var barsHidden = false
        /// Every page count handed over, in order. An empty list is what the host reads as a
        /// chapter that failed to load.
        var reportedTotals: [Int] = []
        var currentPage = 0

        func hideBars() {}
        func getNextChapter() -> AidokuRunner.Chapter? { nil }
        func getPreviousChapter() -> AidokuRunner.Chapter? { nil }
        func setChapter(_ chapter: AidokuRunner.Chapter) {}
        /// Every position handed over, in order, so a correct one followed by a stale one is
        /// visible as a sequence rather than as a final value.
        var reportedPages: [Int] = []
        /// Every page list handed over, in order, since what a list says about itself is how the
        /// host decides which reader shows it.
        var reportedPageLists: [[Aidoku.Page]] = []
        func setCurrentPage(_ page: Int, position: Double?) {
            currentPage = page
            reportedPages.append(page)
        }
        func setCurrentPages(_ pages: ClosedRange<Int>) { currentPage = pages.lowerBound }
        func setPages(_ pages: [Aidoku.Page]) {
            reportedTotals.append(pages.count)
            reportedPageLists.append(pages)
        }
        func displayPage(_ page: Int) {}
        func setSliderOffset(_ offset: CGFloat) {}
        func setCompleted() {}
    }

    /// The reader in a window at a given size, opened on a book.
    ///
    /// Window membership rather than a detached view, because the reader insets its web view by the
    /// window's safe area and reads its own bounds back as the size every page count belongs to.
    private func open(
        bookURL: URL,
        startPage: Int = 1,
        size: CGSize = ReaderEpubViewControllerTests.viewport
    ) throws -> (reader: ReaderEpubViewController, delegate: RecordingDelegate) {
        let manga = AidokuRunner.Manga(sourceKey: "local", key: bookURL.lastPathComponent, title: "")
        let reader = ReaderEpubViewController(source: nil, manga: manga, bookURL: bookURL)
        let delegate = RecordingDelegate()
        reader.delegate = delegate

        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        try #require(window).addSubview(reader.view)
        reader.view.frame = CGRect(origin: .zero, size: size)
        reader.view.layoutIfNeeded()

        reader.setChapter(AidokuRunner.Chapter(key: bookURL.lastPathComponent), startPage: startPage)
        return (reader, delegate)
    }

    /// A source that hands back a fixed page list per chapter key.
    ///
    /// Which archive a chapter lives in is known only to the source, so a reader that resolves its
    /// own archive can only be driven through one. Every method of `Runner` but these three has a
    /// default implementation.
    private struct StubRunner: AidokuRunner.Runner {
        let features = AidokuRunner.SourceFeatures()
        let pages: [String: [AidokuRunner.Page]]

        func getSearchMangaList(
            query: String?,
            page: Int,
            filters: [AidokuRunner.FilterValue]
        ) async throws -> AidokuRunner.MangaPageResult {
            .init(entries: [], hasNextPage: false)
        }

        func getMangaUpdate(
            manga: AidokuRunner.Manga,
            needsDetails: Bool,
            needsChapters: Bool
        ) async throws -> AidokuRunner.Manga {
            manga
        }

        func getPageList(
            manga: AidokuRunner.Manga,
            chapter: AidokuRunner.Chapter
        ) async throws -> [AidokuRunner.Page] {
            pages[chapter.key] ?? []
        }
    }

    private func stubSource(pages: [String: [AidokuRunner.Page]]) -> AidokuRunner.Source {
        .init(
            key: "epub-test",
            name: "ePub Test",
            version: 1,
            contentRating: .safe,
            runner: StubRunner(pages: pages)
        )
    }

    /// The pages a source reports for an ePub chapter, one per spine document, as
    /// `LocalFileManager.readEpubPages` builds them.
    private func epubPages(for book: (url: URL, spinePaths: [String])) -> [AidokuRunner.Page] {
        book.spinePaths.map { .init(content: .zipFile(url: book.url, filePath: $0)) }
    }

    /// The reader opened the way the shipping host opens it: given a source and a chapter, and left
    /// to find the archive that chapter lives in for itself.
    private func openThroughSource(
        chapter: AidokuRunner.Chapter,
        source: AidokuRunner.Source,
        startPage: Int = 1,
        size: CGSize = ReaderEpubViewControllerTests.viewport
    ) throws -> (reader: ReaderEpubViewController, delegate: RecordingDelegate) {
        let manga = AidokuRunner.Manga(sourceKey: source.key, key: "folder", title: "")
        let reader = ReaderEpubViewController(source: source, manga: manga)
        let delegate = RecordingDelegate()
        reader.delegate = delegate

        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        try #require(window).addSubview(reader.view)
        reader.view.frame = CGRect(origin: .zero, size: size)
        reader.view.layoutIfNeeded()

        reader.setChapter(chapter, startPage: startPage)
        return (reader, delegate)
    }

    private func dismantle(_ reader: ReaderEpubViewController) {
        reader.book?.renderer?.webView.stopLoading()
        reader.view.removeFromSuperview()
    }

    private func waitUntilMeasured(
        _ reader: ReaderEpubViewController,
        timeout: TimeInterval = 30
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if reader.book?.isMeasured == true { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("the book was not measured within \(timeout)s")
    }

    /// The book's total is the sum of every document, measured once.
    ///
    /// A total that is short by a document, or long by one document's pages, is what two overlapping
    /// measurement passes produced: one of the two loads was resumed with `superseded` and its
    /// document was never counted, and the other measured whatever the shared web view was left
    /// holding and filed that count under its own path.
    @Test func openingABookMeasuresEveryDocumentExactlyOnce() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let (reader, _) = try open(bookURL: book.url)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        let model = try #require(reader.book)
        #expect(model.index.measuredDocumentCount == book.spinePaths.count)
        #expect(model.unmeasurable.isEmpty)
        #expect(model.firstUnmeasured == nil)

        // Against the documents rather than against itself: the sum has to equal what each document
        // reports at this size, which is the only check a mis-attributed count cannot pass.
        //
        // Measured at the web view's bounds rather than the reader's, since the reader insets its
        // web view by the window's safe area and a count belongs to the size it was laid out at.
        //
        // With the reader's own settings, derived from the reader's bounds the way the controller
        // derives them: a count belongs to its settings as much as to its size, so a renderer built
        // with the defaults would lay the same text out at a different font size and disagree for a
        // reason that says nothing about attribution.
        let size = try #require(model.renderer?.webView.bounds.size)
        let settings = EpubPaginationSettings.fromUserDefaults(for: reader.view.bounds.size)
        let renderer = try await EpubFixture.makeRenderer(for: book.url, size: size, settings: settings)
        defer { EpubFixture.dismantle(renderer.webView) }
        var expected = 0
        for path in book.spinePaths {
            expected += try await renderer.load(spinePath: path)
        }
        #expect(model.bookTotal == expected)
    }

    /// A chapter change opens the archive the new chapter lives in.
    ///
    /// A manga folder holding two epubs is one manga with two chapters carrying two different
    /// archives, since `scanLocalFiles` walks every allowed file in the folder under one id. The
    /// archive used to be resolved once, by the host, from whichever pages it happened to hold when
    /// the reader was built, so moving to the second book reopened the first at page 1 while the
    /// host marked the second read and, with `Library.deleteDownloadAfterReading`, deleted it.
    @Test func aChapterChangeOpensTheNewChaptersArchive() async throws {
        let first = try EpubFixture.makeBook(documents: [1, 40])
        defer { EpubFixture.remove(first.url) }
        let second = try EpubFixture.makeBook(documents: [1, 6, 25, 30])
        defer { EpubFixture.remove(second.url) }

        let firstChapter = AidokuRunner.Chapter(key: "first.epub")
        let secondChapter = AidokuRunner.Chapter(key: "second.epub")
        let source = stubSource(pages: [
            firstChapter.key: epubPages(for: first),
            secondChapter.key: epubPages(for: second)
        ])

        let (reader, delegate) = try openThroughSource(chapter: firstChapter, source: source)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)
        #expect(reader.book?.bookURL == first.url)
        let firstTotal = try #require(reader.book?.bookTotal)

        reader.setChapter(secondChapter, startPage: 1)
        // The book is taken down as the chapter changes, so what this waits for is a new one.
        #expect(reader.book == nil, "the book being left was not taken down")
        try await waitUntilMeasured(reader)

        #expect(reader.book?.bookURL == second.url, "the reader reopened the book it was born with")
        let secondTotal = try #require(reader.book?.bookTotal)
        #expect(secondTotal != firstTotal, "the two books are the same length, so this proves nothing")
        #expect(delegate.reportedTotals.last == secondTotal, "the host was left holding the first book's length")
    }

    /// A chapter that is not an ePub is handed to the host rather than opened.
    ///
    /// The same folder walk that produces two ePub chapters produces an epub beside a cbz. The host
    /// decides which reader shows a chapter by reading its page list, so handing that list over is
    /// how the ePub reader is replaced by the one the chapter belongs to. Reporting an empty list
    /// instead put the host's failure alert on top of a chapter that reads perfectly well.
    @Test func aChapterThatIsNotAnEpubIsHandedToTheHost() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 6])
        defer { EpubFixture.remove(book.url) }

        let epubChapter = AidokuRunner.Chapter(key: "book.epub")
        let imageChapter = AidokuRunner.Chapter(key: "images.cbz")
        let imagePages: [AidokuRunner.Page] = (0..<3).map {
            .init(content: .url(url: URL(string: "https://example.invalid/\($0).png")!))
        }
        let source = stubSource(pages: [
            epubChapter.key: epubPages(for: book),
            imageChapter.key: imagePages
        ])

        let (reader, delegate) = try openThroughSource(chapter: epubChapter, source: source)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        reader.setChapter(imageChapter, startPage: 1)
        try await EpubFixture.waitUntil(timeout: 10) {
            delegate.reportedPageLists.last?.count == imagePages.count
        }

        let handed = try #require(delegate.reportedPageLists.last)
        #expect(handed.count == imagePages.count, "the host was told the chapter failed to load")
        #expect(!handed.contains(where: { $0.isEpubPage }))
        #expect(reader.book == nil, "an ePub was left open under a chapter that is not one")
    }

    /// The pages the reader reports say which archive they came out of.
    ///
    /// They are placeholders standing for the book's length, but the host routes a page list by its
    /// content: a list that does not say it is an ePub takes a branch meant for something else, and
    /// none of the host's own corrections can fire on it.
    @Test func theReportedPagesCarryTheArchive() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let (reader, delegate) = try open(bookURL: book.url)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        let reported = try #require(delegate.reportedPageLists.last)
        #expect(!reported.isEmpty)
        #expect(reported.allSatisfy { $0.isEpubPage }, "the host cannot tell these came out of an ePub")
        #expect(reported.allSatisfy { $0.zipURL == book.url.absoluteString })
    }

    /// A settings change puts the reader back at the same text, not at the same page number.
    ///
    /// A font size change re-fragments the whole book, so the page the reader was on names a
    /// different place in the new layout, further off the deeper in they were. The reader is restored
    /// by the fraction of the book they had read, which is the anchor a rotation already used.
    ///
    /// This failed silently once: the rebuild's anchor was dropped by the pending-page retry in
    /// `report`, which runs through `navigate` and so looked like the reader taking over. The restore
    /// still happened and still landed on the old page number, so nothing errored and only the text
    /// on screen was wrong.
    @Test func aSettingsChangeKeepsTheReaderOnTheSameText() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "Reader.textFontSize")
        defer {
            if let original {
                defaults.set(original, forKey: "Reader.textFontSize")
            } else {
                defaults.removeObject(forKey: "Reader.textFontSize")
            }
        }
        defaults.set(18 as Double, forKey: "Reader.textFontSize")

        let (reader, _) = try open(bookURL: book.url)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        // Deep enough in that restoring the page number lands visibly early: the error is
        // proportional to how far in the reader is.
        let before = try #require(reader.book)
        let totalBefore = before.bookTotal
        let pageBefore = Int(Double(totalBefore) * 0.4)
        await before.showBookPage(pageBefore)
        let fractionBefore = Double(pageBefore) / Double(totalBefore - 1)

        // The reader observes the key rather than reading it at draw time, so the notification is
        // what starts the rebuild. `scheduleSettingsReload` debounces it.
        defaults.set(24 as Double, forKey: "Reader.textFontSize")
        NotificationCenter.default.post(name: NSNotification.Name("Reader.textFontSize"), object: nil)

        try await EpubFixture.waitUntil(timeout: 30) {
            reader.book?.isMeasured == true && reader.book?.bookTotal != totalBefore
        }
        // The refinement happens on the report that observes the last count, and moves through the
        // navigation queue, so it settles a moment after the book is measured.
        try await EpubFixture.waitUntil(timeout: 10) {
            reader.book.map { $0.bookPage != nil && $0.bookPage != pageBefore } ?? false
        }

        let after = try #require(reader.book)
        let totalAfter = after.bookTotal
        let pageAfter = try #require(after.bookPage)
        #expect(totalAfter != totalBefore, "the layout did not change, so the test proves nothing")

        // Against the fraction rather than against a page number: what has to survive is the place
        // in the text, and the two layouts have no page numbering in common.
        let fractionAfter = Double(pageAfter) / Double(totalAfter - 1)
        let tolerance = 2 / Double(totalAfter - 1)
        #expect(
            abs(fractionAfter - fractionBefore) <= tolerance,
            "landed at \(fractionAfter) of the book, having left from \(fractionBefore)"
        )
        // The old behaviour: the page number was restored verbatim, which the fraction check above
        // would also catch, but this says which mistake was made.
        #expect(pageAfter != pageBefore, "the page number was restored rather than the position")
    }

    /// A resize never reports an empty page list.
    ///
    /// Every count belongs to a viewport, so a resize drops all of them and the total is momentarily
    /// zero. The host reads an empty list as a chapter that failed to load and puts a modal alert on
    /// top of the reader, so a reader who rotated the device was told the chapter had failed.
    @Test func aResizeNeverReportsAnEmptyBook() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let (reader, delegate) = try open(bookURL: book.url)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        reader.view.frame = CGRect(origin: .zero, size: CGSize(width: 480, height: 320))
        reader.view.layoutIfNeeded()
        try await waitUntilMeasured(reader)

        #expect(!delegate.reportedTotals.contains(0), "the host was told the chapter failed to load")
        #expect(delegate.reportedTotals.allSatisfy { $0 > 0 })
    }

    /// A drag that never reports its end must not freeze the book's total.
    ///
    /// The total was withheld while the thumb was held, on the assumption that publishing it moved
    /// the thumb. It does not: `setPages` reaches `ReaderToolbarView.totalPages`, whose only effect
    /// is the page count text. So the withholding bought nothing, and any drag whose end was not
    /// reported left the toolbar showing whatever total had been reached when the drag began, for
    /// the rest of the book. Seen by hand on the 217 document book as `1360 / 2893` beside a
    /// document counter that had already reached the end.
    @Test func aHeldSliderDoesNotFreezeTheTotal() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let (reader, delegate) = try open(bookURL: book.url)
        defer { dismantle(reader) }

        // Before the pass has counted anything, as a drag begun on a freshly opened book would be,
        // and with no `sliderStopped` to follow it.
        reader.sliderMoved(value: 0.5)
        try await waitUntilMeasured(reader)

        let model = try #require(reader.book)
        #expect(delegate.reportedTotals.last == model.bookTotal)
        // The position is the half that genuinely moves the thumb, so it is the half withheld.
        #expect(delegate.currentPage == 0, "the thumb was moved under the finger")
    }

    /// A slider release publishes one position, and it is the one asked for.
    ///
    /// A move that crosses into another spine document passes through two states that are not
    /// places the reader is: the page they are leaving, and the first page of the document being
    /// loaded. Both used to be published, so the thumb landed near the target, jumped to the head
    /// of that document, and then settled. A drag within the loaded document loads nothing and so
    /// looked correct, which is why the second drag of a pair always appeared to work.
    @Test func aSliderReleasePublishesOnlyTheSettledPosition() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let (reader, delegate) = try open(bookURL: book.url)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        let model = try #require(reader.book)
        let last = model.bookTotal - 1
        let expected = Int((0.75 * Double(last)).rounded())

        let before = delegate.reportedPages.count
        reader.sliderMoved(value: 0.75)
        reader.sliderStopped(value: 0.75)

        let deadline = Date().addingTimeInterval(10)
        while model.bookPage != expected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        // Well past the renderer's half-second confirmation window, so a late correction that
        // overwrites the position has landed before this is read.
        try await Task.sleep(nanoseconds: 2_000_000_000)

        #expect(model.bookPage == expected, "the release did not move the book")
        #expect(
            Array(delegate.reportedPages.dropFirst(before)) == [expected + 1],
            "the thumb was moved through positions the reader never asked for"
        )
    }

    /// A value change delivered after the drag has ended does not freeze the reader's position.
    ///
    /// `UISlider` sends a last `.valueChanged` after its touch has ended, so a host that forwards
    /// every one of them tells the reader a drag has begun immediately after telling it one
    /// finished. The flag that withholds the position was then set for good: the book kept working
    /// and the counter sat at whatever it had last reported, which reads as a slider that moves the
    /// book to the wrong page and stays there.
    @Test func aValueChangeAfterTheDragEndsDoesNotFreezeThePosition() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let (reader, delegate) = try open(bookURL: book.url)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        let model = try #require(reader.book)
        let last = model.bookTotal - 1
        let expected = Int((0.75 * Double(last)).rounded())

        reader.sliderMoved(value: 0.75)
        reader.sliderStopped(value: 0.75)
        // The trailing event, after the end of the drag it belongs to.
        reader.sliderMoved(value: 0.75)

        let deadline = Date().addingTimeInterval(10)
        while delegate.currentPage != expected + 1 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(model.bookPage == expected)
        #expect(delegate.currentPage == expected + 1, "the position was withheld after the drag ended")

        // And the reader keeps reporting afterwards rather than having been silenced for good.
        await reader.book?.moveForward()
        #expect(delegate.currentPage == expected + 2)
    }

    /// Resuming past the opening document arrives, rather than silently staying at page 1.
    ///
    /// Only the opening document is counted when a book opens, so the index cannot place the page
    /// yet. The request is held and retried as the counts land; dropped, it leaves the reader at
    /// page 1 and the saved position is overwritten with 1 when the reader closes.
    @Test func resumingPastTheOpeningDocumentArrives() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let total: Int
        do {
            let (reader, _) = try open(bookURL: book.url)
            defer { dismantle(reader) }
            try await waitUntilMeasured(reader)
            total = try #require(reader.book).bookTotal
        }

        // The last page of the book, which sits in the last document and so cannot be placed until
        // every document before it has been counted.
        let (reader, delegate) = try open(bookURL: book.url, startPage: total)
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        let deadline = Date().addingTimeInterval(10)
        while delegate.currentPage != total && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(delegate.currentPage == total, "the reader stayed where the resume could not reach")
        #expect(try #require(reader.book).pendingBookPage == nil)
    }
}
