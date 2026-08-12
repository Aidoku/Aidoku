//
//  EpubPaginationTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/11/26.
//

@testable import Aidoku
import Foundation
import Testing
import UIKit
import WebKit

/// Pagination is the part of the ePub reader whose failures are silent: a document laid out at the
/// wrong viewport still renders, still applies its styles, and still reports a plausible page
/// count. Every assertion here is therefore against a number the document itself reports rather
/// than against pagination merely having run.
@Suite(.serialized)
@MainActor
struct EpubPaginationTests {
    /// The count is what the geometry says it is. Read from the document rather than from the
    /// renderer, so the two have to agree.
    @Test func pageCountFollowsTheColumnGeometry() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        let count = try await renderer.load(spinePath: "OEBPS/page.xhtml")

        let scrollWidth = try await EpubFixture.number("document.documentElement.scrollWidth", in: renderer.webView)
        let viewportWidth = try await EpubFixture.number("window.innerWidth", in: renderer.webView)

        #expect(viewportWidth == Double(EpubFixture.viewportSize.width))
        #expect(count > 1)
        #expect(count == Int((scrollWidth / viewportWidth).rounded()))
        #expect(renderer.pageCount == count)

        // The column gap is zero, so the document ends on a page boundary and no partial column
        // trails the last page.
        #expect(scrollWidth == viewportWidth * Double(count))
    }

    /// A count that does not depend on measuring anything: three blocks separated by two forced
    /// column breaks occupy three columns, whatever the text does.
    @Test func forcedColumnBreaksProduceOnePageEach() async throws {
        let body = """
        <style>.break { -webkit-column-break-after: always; break-after: column; }</style>
        <div class="break">one</div><div class="break">two</div><div>three</div>
        """
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: body).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        let count = try await renderer.load(spinePath: "OEBPS/page.xhtml")

        #expect(count == 3)
    }

    /// A short document is one page rather than none, and the arithmetic never reports zero.
    @Test func aShortDocumentIsOnePage() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: "<p>short</p>").utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        #expect(try await renderer.load(spinePath: "OEBPS/page.xhtml") == 1)
    }

    /// Every page begins at exactly `index * viewportWidth`, and the last one is reachable.
    @Test func pagesSitAtWholeMultiplesOfTheViewport() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        let count = try await renderer.load(spinePath: "OEBPS/page.xhtml")
        // The document is left to stop moving before its offsets are sampled; see `settle`.
        await renderer.settle()
        let viewportWidth = try await EpubFixture.number("window.innerWidth", in: renderer.webView)

        var offsets: [Double] = []
        for index in 0..<count {
            await renderer.showPage(index)
            offsets.append(EpubFixture.pageOffset(in: renderer.webView))
        }

        // Compared as a whole so that a failure shows where in the document the offsets stopped
        // following the viewport rather than only that one of them did.
        #expect(offsets == (0..<count).map { viewportWidth * Double($0) })
        #expect(renderer.currentPage == count - 1)

        // The end of a document is 1, which is what `HistoryObject.scrollPosition` already means
        // for both text readers.
        #expect(renderer.progression == 1)
    }

    /// A page index outside the document lands on the nearest page that exists rather than on an
    /// empty column past the end.
    @Test func showPageClampsToTheDocument() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 40)).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        let count = try await renderer.load(spinePath: "OEBPS/page.xhtml")
        // The document is left to stop moving before its offsets are sampled; see `settle`.
        await renderer.settle()
        let viewportWidth = try await EpubFixture.number("window.innerWidth", in: renderer.webView)

        await renderer.showPage(count + 10)
        #expect(renderer.currentPage == count - 1)
        var offset = EpubFixture.pageOffset(in: renderer.webView)
        #expect(offset == viewportWidth * Double(count - 1))

        await renderer.showPage(-5)
        #expect(renderer.currentPage == 0)
        offset = EpubFixture.pageOffset(in: renderer.webView)
        #expect(offset == 0)
    }

    /// One web view serves the whole spine, which is the optimisation the measured cost of walking
    /// a book depends on: reuse is what keeps the footprint flat across a long spine.
    @Test func oneWebViewServesTheWholeSpine() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/first.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8),
            "OEBPS/second.xhtml": Data(EpubFixture.page(body: "<p>second</p>").utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        let webView = renderer.webView
        let first = try await renderer.load(spinePath: "OEBPS/first.xhtml")
        await renderer.showPage(first - 1)

        let second = try await renderer.load(spinePath: "OEBPS/second.xhtml")

        #expect(renderer.webView === webView)
        #expect(first > 1)
        #expect(second == 1)
        // The new document starts at its first page rather than at the offset the previous one was
        // left on.
        #expect(renderer.currentPage == 0)

        let body = try await EpubFixture.evaluate("document.body.textContent.trim()", in: webView) as? String
        #expect(body == "second")
    }

    /// An image wider than the viewport is constrained rather than allowed to widen the document.
    ///
    /// This is the cheapest confirmation that the readium-css sheets are applying at all: `img
    /// { max-width: 100% }` is theirs, and without it a 600 px image in a 320 px viewport pushes
    /// the column layout sideways by an amount that belongs to no page.
    @Test func aWideImageDoesNotOverflowThePage() async throws {
        let body = "<p>before</p><img id=\"wide\" src=\"wide.png\"/><p>after</p>"
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: body).utf8),
            "OEBPS/wide.png": EpubFixture.png(size: CGSize(width: 600, height: 400))
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        // The image arrives after navigation ends, so the count is confirmed rather than assumed.
        try await renderer.load(spinePath: "OEBPS/page.xhtml")
        await renderer.settle()

        let natural = try await EpubFixture.number("document.getElementById('wide').naturalWidth", in: renderer.webView)
        let rendered = try await EpubFixture.number("document.getElementById('wide').clientWidth", in: renderer.webView)
        let scrollWidth = try await EpubFixture.number("document.documentElement.scrollWidth", in: renderer.webView)
        let viewportWidth = try await EpubFixture.number("window.innerWidth", in: renderer.webView)

        // The image is genuinely wider than the viewport, and is displayed narrower than it.
        #expect(natural == 600)
        #expect(rendered <= viewportWidth)
        // The document still ends on a page boundary, which a sideways overflow would break.
        #expect(scrollWidth == viewportWidth * Double(renderer.pageCount))
    }

    /// A page count belongs to a viewport size. A narrower web view re-fragments the document, so
    /// the count the host is holding has to be replaced rather than merely re-rendered.
    @Test func changingTheViewportRepaginates() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        let wide = try await renderer.load(spinePath: "OEBPS/page.xhtml")
        await renderer.showPage(1)

        let reported = Box()
        renderer.onRepaginate = { reported.value = $0 }

        renderer.webView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: EpubFixture.viewportSize.width / 2, height: EpubFixture.viewportSize.height)
        )
        renderer.webView.layoutIfNeeded()

        try await EpubFixture.waitUntil(timeout: 10) { reported.value != nil }

        let narrow = renderer.pageCount
        #expect(narrow > wide)
        #expect(reported.value == narrow)

        // The document is left on a whole page of the new width. Which page that is belongs to the
        // text rather than to the number it had before, and is covered by
        // `rotatingKeepsTheReaderOnTheSameText`.
        let viewportWidth = try await EpubFixture.number("window.innerWidth", in: renderer.webView)
        let offset = EpubFixture.pageOffset(in: renderer.webView)
        #expect(viewportWidth == Double(EpubFixture.viewportSize.width) / 2)
        #expect(renderer.currentPage > 0)
        #expect(offset == viewportWidth * Double(renderer.currentPage))
    }

    /// A rotation re-fragments the document, and rotating back returns it to what it was.
    ///
    /// The document is asked for the width of its own root element, not only for a page count. A
    /// count that merely changes proves nothing: with `:root` pinned to the width it had at load
    /// and its columns still `100vw`, a narrower viewport produces more columns while every page
    /// boundary sits somewhere other than a multiple of the viewport, and nothing later puts it
    /// right. That is what a pixel-valued `--RS__viewportWidth` did.
    @Test func rotatingTheViewportReflowsTheColumns() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let portrait = EpubFixture.viewportSize
        let landscape = CGSize(width: portrait.height, height: portrait.width)

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        let upright = try await renderer.load(spinePath: "OEBPS/page.xhtml")
        await renderer.settle()
        try await assertColumnsFillTheViewport(of: renderer, width: portrait.width)

        let turned = try await rotate(renderer, to: landscape)
        try await assertColumnsFillTheViewport(of: renderer, width: landscape.width)
        // A wider, shorter page holds a different amount of text, so the count has to move.
        #expect(turned != upright)

        let returned = try await rotate(renderer, to: portrait)
        try await assertColumnsFillTheViewport(of: renderer, width: portrait.width)
        #expect(returned == upright)
    }

    /// A rotation keeps the reader where they had read to, rather than on the page number they were
    /// reading at.
    ///
    /// Re-fragmenting moves text between pages: this document is 29 pages at 320 px and 32 at 480,
    /// and the paragraph at the top of page 10 moves to page 12. Holding the index would hand the
    /// reader two pages they had already read, and the error grows with how far in they are.
    ///
    /// A fraction of the document is what is restored, so the text lands within a page of where it
    /// was rather than exactly on it. Measured across six positions in a 43 page document, the
    /// fraction and the text agreed exactly at four of them and differed by one page at the others.
    /// Exactness would mean resolving a pointer into the text, which is a feature of its own.
    @Test func rotatingKeepsTheReaderOnTheSameText() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        try await renderer.load(spinePath: "OEBPS/page.xhtml")
        await renderer.settle()
        await renderer.showPage(10)

        let paragraph = try await EpubFixture.number(Self.paragraphAtTopOfPage, in: renderer.webView)
        #expect(paragraph >= 0)

        _ = try await rotate(renderer, to: CGSize(width: 480, height: 320))

        let landed = try await EpubFixture.number(Self.pageOfParagraph(Int(paragraph)), in: renderer.webView)
        #expect(abs(landed - Double(renderer.currentPage)) <= 1)
    }

    /// Which paragraph the page currently begins with, by the same reckoning the renderer's anchor
    /// uses: the first character inside the page gutter.
    private static let paragraphAtTopOfPage = """
    (function() {
        var range = null;
        for (var y = 22; y < window.innerHeight && !range; y += 12) {
            var candidate = document.caretRangeFromPoint(22, y);
            if (candidate && candidate.startContainer && candidate.startContainer.nodeType === 3) {
                range = candidate;
            }
        }
        var node = range ? range.startContainer : null;
        var element = node && node.nodeType === 3 ? node.parentElement : node;
        // An XHTML document does not uppercase its tag names, unlike an HTML one.
        while (element && element.tagName.toLowerCase() !== 'p') { element = element.parentElement; }
        if (!element) { return -1; }
        var paragraphs = document.getElementsByTagName('p');
        for (var i = 0; i < paragraphs.length; i++) {
            if (paragraphs[i] === element) { return i; }
        }
        return -1;
    })()
    """

    /// Which page a paragraph now falls on, in the document's own coordinates.
    private static func pageOfParagraph(_ index: Int) -> String {
        """
        (function() {
            var paragraph = document.getElementsByTagName('p')[\(index)];
            if (!paragraph) { return -1; }
            var left = paragraph.getBoundingClientRect().left + window.pageXOffset;
            return Math.floor((left + 1) / window.innerWidth);
        })()
        """
    }

    /// Resizes the web view as a rotation would and waits for the renderer to re-paginate.
    private func rotate(_ renderer: EpubSpineRenderer, to size: CGSize) async throws -> Int {
        let before = renderer.pageCount
        renderer.webView.frame = CGRect(origin: .zero, size: size)
        renderer.webView.layoutIfNeeded()

        // The count changes before the page is restored, so waiting on it alone would sample the
        // document mid-turn.
        try await EpubFixture.waitUntil(timeout: 10) {
            let width = try? await EpubFixture.number("window.innerWidth", in: renderer.webView)
            guard width == Double(size.width), renderer.pageCount != before else { return false }
            return EpubFixture.pageOffset(in: renderer.webView)
                == Double(renderer.currentPage) * Double(size.width)
        }
        return renderer.pageCount
    }

    /// The text fills pages of exactly the viewport's width.
    ///
    /// The body is what has to be asked. A root pinned to the width it had at load still produces
    /// columns of `100vw` and a page count that divides cleanly, because the multi-column box grows
    /// to hold them; what stays behind is the text, laid out to the old width and leaving the rest
    /// of every page empty. Measured at 320 px and rotated to 480: columns 480 wide, pages whole,
    /// body still 320.
    private func assertColumnsFillTheViewport(of renderer: EpubSpineRenderer, width: CGFloat) async throws {
        let viewportWidth = try await EpubFixture.number("window.innerWidth", in: renderer.webView)
        let bodyWidth = try await EpubFixture.number("document.body.clientWidth", in: renderer.webView)
        let scrollWidth = try await EpubFixture.number("document.documentElement.scrollWidth", in: renderer.webView)

        #expect(viewportWidth == Double(width))
        #expect(bodyWidth == viewportWidth)
        #expect(scrollWidth == viewportWidth * Double(renderer.pageCount))
    }

    /// A count belongs to the size the document is laid out at, not to the size before it.
    ///
    /// The web content process is told of a new size after the view has taken it, so a measurement
    /// made as the layout pass arrives describes the layout being replaced. On an iPad entering a
    /// split view that left the count at the full-width 1 for a document which had already reflowed
    /// to `innerWidth` 412 and `scrollWidth` 1236, three pages; nudging the divider then measured
    /// that 412 layout and reported 3 for a document by then laid out at 449 and occupying 2. Each
    /// resize reported the one before it.
    ///
    /// Two changes in quick succession are what expose it, since the second must not be answered
    /// with the geometry of the first. The count is checked against the document's own measurements
    /// rather than against a number worked out here, which is the disagreement being tested for.
    @Test func resizingTwiceReportsTheLatestGeometry() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        _ = try await renderer.load(spinePath: "OEBPS/page.xhtml")
        await renderer.settle()

        let height = EpubFixture.viewportSize.height
        for width in [EpubFixture.viewportSize.width / 2, EpubFixture.viewportSize.width * 2 / 3] {
            renderer.webView.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            renderer.webView.layoutIfNeeded()
        }
        await renderer.settle()

        let viewportWidth = try await EpubFixture.number("window.innerWidth", in: renderer.webView)
        let scrollWidth = try await EpubFixture.number("document.documentElement.scrollWidth", in: renderer.webView)

        // Within a point rather than exactly: this width is fractional, which is the case an iPad
        // split view produces, and `window.innerWidth` is an integer.
        #expect(abs(viewportWidth - Double(EpubFixture.viewportSize.width * 2 / 3)) <= 1)
        #expect(Double(renderer.pageCount) == (scrollWidth / viewportWidth).rounded())
        // The document is on a whole page of the width it now has, rather than of the one the count
        // was measured against.
        #expect(EpubFixture.pageOffset(in: renderer.webView) == viewportWidth * Double(renderer.currentPage))
    }

    /// A document loaded while a resize is still settling ends up paginated as itself, from page 0.
    ///
    /// The window is shorter than a person can act in, so a manual pass over it shows only that
    /// nothing gross happens. This asserts the state it settles into, not the path taken: `load`
    /// writes the count, the page and the progression after any work the resize had in flight, so a
    /// resize left uncancelled is corrected here rather than caught. What it would produce is a
    /// scroll to the previous document's progression that stands until `holdCurrentPage` undoes it,
    /// a flash of the wrong text which no assertion about the settled state can see. The
    /// cancellation guard in `repaginate` exists for that flash and is not covered by any test.
    @Test func loadingDuringAResizeDoesNotCarryThePreviousDocument() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/long.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8),
            "OEBPS/short.xhtml": Data(EpubFixture.page(body: "<p>one short page</p>").utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        _ = try await renderer.load(spinePath: "OEBPS/long.xhtml")
        await renderer.settle()
        await renderer.showPage(renderer.pageCount - 1)
        #expect(renderer.progression > 0)

        // Resize, then replace the document before the resize has been acted on.
        renderer.webView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: EpubFixture.viewportSize.width / 2, height: EpubFixture.viewportSize.height)
        )
        renderer.webView.layoutIfNeeded()
        // Long enough for the size change to be past its debounce and inside `repaginate`, which is
        // the window being tested. Replacing the document sooner is caught by the check the task
        // makes when it wakes, and so exercises nothing.
        try? await Task.sleep(nanoseconds: 60_000_000)
        let pages = try await renderer.load(spinePath: "OEBPS/short.xhtml")
        await renderer.settle()

        #expect(pages == 1)
        #expect(renderer.pageCount == 1)
        #expect(renderer.currentPage == 0)
        #expect(renderer.progression == 0)
        #expect(EpubFixture.pageOffset(in: renderer.webView) == 0)
    }

    /// A resize arriving while a load is still being confirmed settles on the geometry it ends at.
    ///
    /// The confirmation started by a load holds the document steady and re-measures it when a late
    /// image reflows it, so a resize inside that window has the two running against each other.
    /// This asserts the outcome that matters, a count agreeing with the document and not moving
    /// afterwards; it does not distinguish which of the two produced it, and passes with the
    /// confirmation left uncancelled because `waitForViewport` makes a late measurement land on the
    /// final width anyway. What cancelling removes is two `holdCurrentPage` loops invalidating each
    /// other's request guard, which shows as jitter rather than as a wrong number.
    @Test func resizingDuringTheConfirmationSettlesOnOneCount() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: EpubFixture.prose(paragraphs: 80)).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        // Deliberately not settled: the confirmation is still running when the resize arrives.
        _ = try await renderer.load(spinePath: "OEBPS/page.xhtml")
        renderer.webView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: EpubFixture.viewportSize.width / 2, height: EpubFixture.viewportSize.height)
        )
        renderer.webView.layoutIfNeeded()
        await renderer.settle()

        let settled = renderer.pageCount
        let viewportWidth = try await EpubFixture.number("window.innerWidth", in: renderer.webView)
        let scrollWidth = try await EpubFixture.number("document.documentElement.scrollWidth", in: renderer.webView)

        #expect(viewportWidth == Double(EpubFixture.viewportSize.width) / 2)
        #expect(Double(settled) == (scrollWidth / viewportWidth).rounded())

        // Nothing left running moves it afterwards.
        try? await Task.sleep(nanoseconds: 700_000_000)
        #expect(renderer.pageCount == settled)
    }

    /// A spine path the provider cannot satisfy fails the navigation rather than leaving the reader
    /// waiting on a page count that never arrives.
    @Test func loadingAMissingDocumentThrows() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: "<p>text</p>").utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        await #expect(throws: EpubSpineRenderer.RenderError.self) {
            _ = try await renderer.load(spinePath: "OEBPS/missing.xhtml")
        }
    }
}

/// Carries a value out of the renderer's callback, which fires while the test is suspended.
@MainActor
private final class Box {
    var value: Int?
}
