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
private let viewport = CGSize(width: 320, height: 480)

/// Records the conversation rather than acting on it, so a call that should never happen is
/// visible as a value rather than as a side effect.
///
/// At file scope with the harness below so `type_body_length` counts the suite's tests rather
/// than its scaffolding.
@MainActor
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

private let readerStyleKey = "Reader.textReaderStyle"

/// The style in force before `open` pinned it, so `dismantle` can put it back.
@MainActor private var styleBeforeOpen: String??

/// Pins the reader style to the app's registered default for the duration of a test.
///
/// The reader builds its pagination from `UserDefaults.standard`, which this target shares with the
/// app, so whichever style was last chosen in the simulator decided how these books paginated. A
/// book opened scrolled counts its pages differently from a paged one and every position assertion
/// here moves with it, which is not a failure any of them are written to describe. Clearing the key
/// rather than writing one leaves the default `AppDelegate` registers as the single source of it.
///
/// A test that is *about* the style sets it after opening, and its own restore still wins: this
/// puts back what it read before opening, which is the value that restore then overwrites.
@MainActor
private func pinReaderStyle() {
    styleBeforeOpen = UserDefaults.standard.string(forKey: readerStyleKey)
    UserDefaults.standard.removeObject(forKey: readerStyleKey)
}

@MainActor
private func unpinReaderStyle() {
    guard let saved = styleBeforeOpen else { return }
    styleBeforeOpen = nil
    if let saved {
        UserDefaults.standard.set(saved, forKey: readerStyleKey)
    } else {
        UserDefaults.standard.removeObject(forKey: readerStyleKey)
    }
}

/// The reader in a window at a given size, opened on a book.
///
/// Window membership rather than a detached view, because the reader insets its web view by the
/// window's safe area and reads its own bounds back as the size every page count belongs to.
@MainActor
private func open(
    bookURL: URL,
    startPage: Int = 1,
    size: CGSize = viewport
) throws -> (reader: ReaderEpubViewController, delegate: RecordingDelegate) {
    pinReaderStyle()
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

@MainActor
private func dismantle(_ reader: ReaderEpubViewController) {
    reader.book?.renderer?.webView.stopLoading()
    reader.view.removeFromSuperview()
    unpinReaderStyle()
}

@MainActor
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

@Suite(.serialized)
@MainActor
struct ReaderEpubViewControllerTests {

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

    /// Where each chapter's page list has got to, so a test can wait for the two moments the race
    /// is made of rather than sleep for a guess at when they are.
    private final class DeliveryLog: @unchecked Sendable {
        private let lock = NSLock()
        private var requested: Set<String> = []
        private var delivered: Set<String> = []

        func recordRequest(_ key: String) {
            lock.lock()
            defer { lock.unlock() }
            requested.insert(key)
        }

        func recordDelivery(_ key: String) {
            lock.lock()
            defer { lock.unlock() }
            delivered.insert(key)
        }

        func hasRequested(_ key: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return requested.contains(key)
        }

        func hasDelivered(_ key: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return delivered.contains(key)
        }
    }

    /// The same, with the page list of a chapter withheld for a while before it is handed back.
    ///
    /// A remote ePub is fetched over the network, so the reader is routinely suspended inside
    /// `getPages` when the chapter changes under it. This is how a test gets to be there too.
    private struct SlowRunner: AidokuRunner.Runner {
        let features = AidokuRunner.SourceFeatures()
        let pages: [String: [AidokuRunner.Page]]
        let delays: [String: Double]
        let log: DeliveryLog

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
            log.recordRequest(chapter.key)
            if let delay = delays[chapter.key] {
                // Not `Task.sleep`, which cancellation resumes at once: what has to be reproduced
                // is a fetch that hands its pages over *after* the chapter changed and the new one
                // was opened, which is what a `URLSession` callback already in flight does.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        continuation.resume()
                    }
                }
            }
            log.recordDelivery(chapter.key)
            return pages[chapter.key] ?? []
        }
    }

    private func slowSource(
        pages: [String: [AidokuRunner.Page]],
        delays: [String: Double],
        log: DeliveryLog
    ) -> AidokuRunner.Source {
        .init(
            key: "epub-test",
            name: "ePub Test",
            version: 1,
            contentRating: .safe,
            runner: SlowRunner(pages: pages, delays: delays, log: log)
        )
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
        size: CGSize = viewport
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

    /// A page list that arrives after the chapter changed decides nothing.
    ///
    /// `getPages` suspends and cancellation is cooperative, so the task a chapter change cancelled
    /// resumes anyway, and it used to write the archive of the chapter being left into the reader's
    /// cache after the change had cleared it. The reader is already showing the right book at that
    /// point; what the stale write decides is which book the *next* read of the cache opens, and a
    /// settings change is a read of the cache. So the chapter is left open on one book and rebuilt
    /// as another, mid-read.
    ///
    /// The other order, where the stale write lands early enough for the new chapter to open the
    /// old book outright, is the same write and is fixed by the same check; it is not reproduced
    /// here because which of the two tasks resumes first is not ours to arrange.
    @Test func aPageListArrivingAfterAChapterChangeIsDiscarded() async throws {
        let first = try EpubFixture.makeBook(documents: [1, 40])
        defer { EpubFixture.remove(first.url) }
        let second = try EpubFixture.makeBook(documents: [1, 6, 25, 30])
        defer { EpubFixture.remove(second.url) }

        let firstChapter = AidokuRunner.Chapter(key: "first.epub")
        let secondChapter = AidokuRunner.Chapter(key: "second.epub")
        let log = DeliveryLog()
        let source = slowSource(
            pages: [
                firstChapter.key: epubPages(for: first),
                secondChapter.key: epubPages(for: second)
            ],
            // Long enough that the second chapter's own page list has been fetched and cached
            // first, which is what leaves the stale write landing on top of a correct one.
            delays: [firstChapter.key: 0.5],
            log: log
        )

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

        let (reader, _) = try openThroughSource(chapter: firstChapter, source: source)
        defer { dismantle(reader) }

        // The chapter changes while the first page list is still being waited on, which is the
        // whole of the race, so the fetch has to have started before it does.
        try await EpubFixture.waitUntil(timeout: 10) { log.hasRequested(firstChapter.key) }
        #expect(!log.hasDelivered(firstChapter.key), "the first page list arrived before it was superseded")
        #expect(reader.book == nil, "the first chapter was opened before its page list was superseded")
        reader.setChapter(secondChapter, startPage: 1)
        try await waitUntilMeasured(reader)
        #expect(reader.book?.bookURL == second.url, "the superseded page list decided which book opened")

        // The superseded fetch returns here, which is the write under test.
        try await EpubFixture.waitUntil(timeout: 10) { log.hasDelivered(firstChapter.key) }

        // A settings change reopens the chapter through the cache rather than fetching again, so
        // this is where a poisoned cache shows.
        let totalBefore = try #require(reader.book?.bookTotal)
        defaults.set(24 as Double, forKey: "Reader.textFontSize")
        NotificationCenter.default.post(name: NSNotification.Name("Reader.textFontSize"), object: nil)
        try await EpubFixture.waitUntil(timeout: 30) {
            reader.book?.isMeasured == true && reader.book?.bookTotal != totalBefore
        }

        #expect(reader.book?.bookURL == second.url, "the rebuild opened the book the chapter was left for")
    }

    /// A book that declares no contents has still read them once it is open.
    ///
    /// The host disables the button that reaches the contents until the reader has read them, and
    /// it asked the table whether it was empty to decide. A book with no resolvable table never
    /// stops being empty, so the button stayed disabled for as long as that book was open and the
    /// chapter list it falls back to was reachable only by keyboard or pencil. This is the signal
    /// that tells "none to read" apart from "not read yet".
    @Test func aBookWithoutContentsStillReportsHavingReadThem() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 6])
        defer { EpubFixture.remove(book.url) }

        let manga = AidokuRunner.Manga(sourceKey: "local", key: book.url.lastPathComponent, title: "")
        let unopened = ReaderEpubViewController(source: nil, manga: manga, bookURL: book.url)
        #expect(!unopened.hasReadTableOfContents, "a reader with no book open has read nothing")

        let (reader, _) = try open(bookURL: book.url)
        defer { dismantle(reader) }
        try await EpubFixture.waitUntil(timeout: 30) { reader.book != nil }

        #expect(reader.tableOfContents.isEmpty, "the fixture must declare no contents")
        #expect(reader.hasReadTableOfContents, "an open book has read whatever contents it has")
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

    /// Switching between paged and scroll mode restores per document, not by a fraction of the
    /// whole book.
    ///
    /// A book fraction assumes pages hold equal shares of the text, and the per-document rounding
    /// breaks that across modes: scroll mode rounds every document's count *up*, so a long spine
    /// inflates the scroll total by up to a page per document, and a fraction carried between the
    /// modes landed several pages away. The document is the unit both layouts agree on, and the
    /// within-document edge is what must survive the switch.
    @Test func aModeSwitchKeepsTheReaderInTheSameDocument() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: readerStyleKey)
        defer {
            if let original {
                defaults.set(original, forKey: readerStyleKey)
            } else {
                defaults.removeObject(forKey: readerStyleKey)
            }
        }
        defaults.removeObject(forKey: readerStyleKey)

        // Landscape, so that on an iPad this exercises the two-column spread layout whose page
        // counts differ most from scroll mode's. On an iPhone it is one column either way.
        let (reader, _) = try open(bookURL: book.url, size: CGSize(width: 480, height: 320))
        defer { dismantle(reader) }
        try await waitUntilMeasured(reader)

        // Deep enough into the third document that a whole-book fraction, skewed by the other
        // documents' rounding, would miss it.
        let before = try #require(reader.book)
        await before.showBookPage(Int(Double(before.bookTotal) * 0.4))
        let documentBefore = before.currentDocument
        let pageInDocumentBefore = before.pageInDocument
        let countBefore = try #require(before.index.pageCount(forDocumentAt: documentBefore))
        let edgeBefore = Double(pageInDocumentBefore) / Double(countBefore)

        defaults.set("scroll", forKey: readerStyleKey)
        NotificationCenter.default.post(name: NSNotification.Name(readerStyleKey), object: nil)

        // The rebuild replaces the view model; the refinement settles through the navigation
        // queue once the new layout is measured. Reaching the right document is not it having
        // settled: the coarse page-number landing gets there first, so the wait is for the edge,
        // and a `try?` leaves a timeout to the assertions below, which then show where the reader
        // actually ended up.
        try await EpubFixture.waitUntil(timeout: 30) {
            reader.book !== before && reader.book?.isMeasured == true
        }
        try? await EpubFixture.waitUntil(timeout: 10) {
            guard
                let book = reader.book, book.currentDocument == documentBefore,
                let count = book.index.pageCount(forDocumentAt: documentBefore)
            else { return false }
            return abs(Double(book.pageInDocument) / Double(count) - edgeBefore) < 1.011 / Double(count)
        }

        let after = try #require(reader.book)
        let countAfter = try #require(after.index.pageCount(forDocumentAt: documentBefore))
        let edgeAfter = Double(after.pageInDocument) / Double(countAfter)
        // The scroll viewport rests on the exact edge, off the page grid, and the page *reported*
        // for it rounds to the nearest boundary — so the reported edge may sit up to half a page
        // to either side, and no further.
        #expect(
            abs(edgeBefore - edgeAfter) < 1.000_001 / Double(countAfter),
            "left the document edge at \(edgeBefore), landed at \(edgeAfter) of \(countAfter) pages"
        )

        // And back again. The scroll side seeds from its exact offset rather than from its page
        // number, whose rounding — offset to the nearest boundary, trailing partial screen up —
        // resumed the paged layout a page early.
        defaults.removeObject(forKey: readerStyleKey)
        NotificationCenter.default.post(name: NSNotification.Name(readerStyleKey), object: nil)

        try await EpubFixture.waitUntil(timeout: 30) {
            reader.book !== after && reader.book?.isMeasured == true
        }
        try await EpubFixture.waitUntil(timeout: 10) {
            reader.book?.currentDocument == documentBefore
        }

        // The anchor the return trip departs from is the scroll offset itself, which is more
        // precise than the page edge: the page's count rounds the trailing partial screen up, so
        // `q / count` understates where the reader is.
        let anchorBack = try #require(after.edgeInDocument)

        defaults.removeObject(forKey: readerStyleKey)
        NotificationCenter.default.post(name: NSNotification.Name(readerStyleKey), object: nil)

        try await EpubFixture.waitUntil(timeout: 30) {
            reader.book !== after && reader.book?.isMeasured == true
        }
        try? await EpubFixture.waitUntil(timeout: 10) {
            reader.book?.currentDocument == documentBefore
                && reader.book?.pageInDocument == pageInDocumentBefore
        }

        let back = try #require(reader.book)
        let countBack = try #require(back.index.pageCount(forDocumentAt: documentBefore))
        let edgeBack = Double(back.pageInDocument) / Double(countBack)
        // The landed page must *contain* the anchor: its edge at or before the anchor, the anchor
        // within one page of it. Landing a page early — the bug this guards — puts the anchor a
        // full page or more past the landed edge. The anchor reads a scroll offset back through
        // the scroll view, which rounds it by a few pixels, so containment holds to a hundredth of
        // a page rather than exactly.
        #expect(
            anchorBack - edgeBack >= -0.011 / Double(countBack)
                && anchorBack - edgeBack < 1.011 / Double(countBack),
            "left the scroll anchor at \(anchorBack), landed back at \(edgeBack) of \(countBack) pages"
        )
        // And exactly: the scroll viewport rested on the exact edge the paged layout left, so the
        // switch back floors onto the very page it departed from. Landing one page back is the
        // double floor this round trip existed to catch.
        #expect(
            back.pageInDocument == pageInDocumentBefore,
            "departed page \(pageInDocumentBefore) of the document, returned to \(back.pageInDocument)"
        )
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

    /// A resume is marked outstanding until it lands, and the total climbs throughout.
    ///
    /// Two things have to hold at once here, and fixing one by breaking the other has now happened
    /// twice. The reader must not be taken to be *at* the head of the book while it is being resumed
    /// past it, because the host writes that position and it lands on top of the progress being
    /// resumed to; measured on a real book, page 1 was saved over page 2120 of 5298. And the toolbar
    /// must keep showing numbers throughout, because `ReaderToolbarView` blanks both of its labels
    /// unless it has a current page as well as a total, so withholding the position withheld every
    /// sign that a five thousand page book was doing anything at all.
    ///
    /// The resolution is that the position is reported and `isAwaitingResume` says not to write it.
    /// This covers the reporting half. The half that refuses the write lives in
    /// `ReaderViewController.updateReadPosition`, which no test drives.
    @Test func aResumeIsMarkedOutstandingWhileTheTotalClimbs() async throws {
        let book = try EpubFixture.makeBook(documents: [1, 40, 6, 25])
        defer { EpubFixture.remove(book.url) }

        let total: Int
        do {
            let (reader, _) = try open(bookURL: book.url)
            defer { dismantle(reader) }
            try await waitUntilMeasured(reader)
            total = try #require(reader.book).bookTotal
        }
        try #require(total > 2, "the fixture must be long enough for a resume to be deep")

        let (reader, delegate) = try open(bookURL: book.url, startPage: total)
        defer { dismantle(reader) }

        // Held from before the book is opened, so the very first count lands into a book that
        // already knows it is not where it belongs.
        try await EpubFixture.waitUntil(timeout: 10) { reader.book != nil }
        #expect(reader.isAwaitingResume, "the resume was not outstanding while the book was counted")

        try await waitUntilMeasured(reader)
        try await EpubFixture.waitUntil(timeout: 10) { delegate.currentPage == total }

        #expect(!reader.isAwaitingResume, "the resume stayed outstanding after it landed")
        #expect(delegate.reportedPages.last == total)

        // The total is a label rather than a place, and it is published throughout. Withholding it
        // alongside the position froze the page count from the moment the book opened until the
        // resume landed.
        #expect(delegate.reportedTotals.count > 1, "the total did not climb while the resume was held")
        #expect(
            delegate.reportedTotals == delegate.reportedTotals.sorted(),
            "the total did not climb in order: \(delegate.reportedTotals)"
        )
        #expect(delegate.reportedTotals.last == total)
    }
}
