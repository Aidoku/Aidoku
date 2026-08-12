//
//  EpubSpineRenderer.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/11/26.
//

import Foundation
import WebKit

/// Renders the documents of one ePub spine, laid out in columns by readium-css, and reports how
/// many pages each occupies.
///
/// One web view serves the whole spine. Cost follows the number of documents rather than their
/// size, so per-document overhead is what matters: a 191,889 character document paginates in 65 ms
/// against a 53 ms median for a single page one, while a seventy document book costs 3.81 s in
/// total. Reuse also keeps the footprint flat, at +0.6 MB across that same book.
///
/// A page count belongs to a viewport size. A column is `100vh` tall and `100vw` wide, so any
/// change to either dimension re-fragments the document and moves every page boundary. The
/// renderer therefore holds its own viewport still rather than trusting the chrome it is placed
/// in, and re-measures when the size changes regardless.
@MainActor
final class EpubSpineRenderer: NSObject {
    enum RenderError: Error {
        /// No URL could be built for the given spine path.
        case unresolvablePath(String)
        /// The web view reported a failed navigation.
        case navigationFailed(String)
        /// The navigation was abandoned because another one began.
        case superseded
        /// The measurement script returned something unusable.
        case measurementFailed(String)
    }

    /// The view the host places in its hierarchy. Its size is the viewport every page count is
    /// measured against.
    let webView: WKWebView

    /// How many pages the loaded document occupies, and which of them is shown. Zero until a
    /// document has been loaded.
    private(set) var pageCount = 0
    private(set) var currentPage = 0

    /// How far through the document the reader has read, as a fraction of it.
    ///
    /// This is the position that survives a document being laid out again, since a page index does
    /// not: re-fragmenting moves text between pages, and a document of 43 pages at one width was 48
    /// at another. Measured against the text itself, restoring by fraction landed within a page at
    /// every position sampled, and exactly on it at most of them.
    ///
    /// It is deliberately a fraction rather than a pointer into the text. A pointer restores
    /// exactly, and every reader that offers exactness carries one: KOReader's engine stores an
    /// XPointer, Readium a Locator holding a CSS selector or an EPUB CFI, and Calibre and Apple
    /// Books store CFIs. Each of those is a grammar to produce, parse and resolve against a
    /// document, which is a feature of its own rather than a detail of pagination, and it is what
    /// bookmarks and a position that survives a change of font size would need.
    ///
    /// A fraction is also the shape the app already keeps, and this one is the app's shape rather
    /// than its own. `ReaderHoldingDelegate` records a page alongside an optional `position`, which
    /// reaches `HistoryObject.scrollPosition`, and both text readers already fill it for the same
    /// reason: a reflowable document cannot be resumed from a page number. They put the end of a
    /// document at 1, `ReaderPagedTextViewController.normalizedPosition(for:)` dividing by one less
    /// than the page count and `ReaderTextViewController` clamping a scroll fraction to it, so this
    /// divides the same way. A reader hosting the renderer passes this value straight through.
    ///
    /// What travels to a server is the page rather than the fraction. `ChapterReadProgress` carries
    /// `completed` and an integer `page`, which `PageTracker` sends to Komga as a book read progress
    /// and to Kavita as `pageNum`. For images that page is exact; for an ePub it is the number that
    /// a rotation invalidates. Both servers hold a position that does survive, and neither is what
    /// Aidoku sends today: Komga takes a Readium locator whose `locations.progression` is exactly
    /// this fraction for one spine resource, while Kavita takes a spine index with an optional
    /// `BookScrollId`, an XPath into the document, which a fraction cannot fill.
    ///
    /// This value belongs to one spine document. A position within a book is that document's place
    /// in the spine together with this.
    private(set) var progression: Double = 0

    /// Called when a loaded document re-paginates, carrying the new page count.
    ///
    /// Two things cause it: an image that decoded after navigation ended, and a change to the size
    /// of the web view. The page shown is preserved across both, and its offset is recomputed, so
    /// a host that displays the count is all this needs to reach.
    var onRepaginate: ((Int) -> Void)?

    private let settings: EpubPaginationSettings
    private var navigationContinuation: CheckedContinuation<Void, any Error>?
    private var confirmationTask: Task<Void, Never>?
    private var sizeChangeTask: Task<Void, Never>?

    /// The offset the current page was scrolled to, as the document itself computed it.
    ///
    /// The scroll and the check that verifies it must use one number. `window.innerWidth` is a
    /// CSSOM `long` while `webView.bounds.width` is in points and can be fractional, as an iPad
    /// split view or a safe-area-derived layout produces, so the two disagree by up to a point;
    /// scrolling by one and checking against the other multiplies that difference by the page index
    /// until, within two pages, the check no longer recognises the offset it asked for and every
    /// page turn waits out its timeout while `holdCurrentPage` re-scrolls throughout.
    ///
    /// It is read back from the document rather than computed here and remembered. A width held on
    /// this side goes stale the moment the document is laid out again, and an offset computed from
    /// a stale width lands short by the difference: at a remembered 412 against a document laid out
    /// at 449, every page arrived 37 px before its boundary and showed the tail of the page before.
    private var currentPageOffset: Double = 0

    /// How far the document may sit from a page boundary and still count as showing it. The scroll
    /// and the check are computed from the same width, so this covers device-pixel snapping rather
    /// than a disagreement about the geometry.
    private static let pageOffsetTolerance: Double = 1

    /// Counts the pages asked for, so that work started for one page can tell it has been overtaken,
    /// and how many of those requests are still settling.
    private var pageRequests = 0
    private var pagesInFlight = 0

    /// Compiling the content rule list the configuration carries is asynchronous, so building a
    /// renderer is too, and it fails where that list cannot be compiled: a renderer without it
    /// would show the book while letting it reach the network. A configuration belongs to one
    /// provider and therefore to one book.
    init(provider: any EpubResourceProvider, settings: EpubPaginationSettings = .default) async throws {
        self.settings = settings

        let configuration = try await EpubWebViewFactory.makeConfiguration(
            provider: provider,
            settings: settings
        )
        let webView = SizeReportingWebView(frame: .zero, configuration: configuration)
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.onSizeChange = { [weak self] in self?.handleSizeChange() }

        #if !os(macOS)
        // WebKit resolves `100vh` against the web view's bounds rather than against the area left
        // visible once insets are applied. A view already pinned by its host whose scroll view
        // insets itself as well lays out a column taller than it can show, leaving the foot of
        // every page under the chrome.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // A paged document is exactly as tall as its viewport, so vertical movement of any kind is
        // rubber-banding against nothing.
        webView.scrollView.alwaysBounceVertical = false
        // Pages are reached through `showPage`. Free scrolling would leave a column boundary in
        // the middle of the viewport, at which point the offsets computed here no longer describe
        // what is on screen. Gestures belong to the reader that hosts this.
        webView.scrollView.isScrollEnabled = false
        #endif
    }

    deinit {
        confirmationTask?.cancel()
        sizeChangeTask?.cancel()
    }

    // MARK: - Rendering

    /// Loads a spine document and returns the number of pages it occupies.
    ///
    /// `scrollWidth` was already correct at `didFinish` for all 211 documents of the measured
    /// corpus, so the count is available as soon as navigation completes and no placeholder is
    /// needed in the meantime.
    @discardableResult
    func load(spinePath: String) async throws -> Int {
        guard let url = EpubSchemeHandler.url(forResourcePath: spinePath) else {
            throw RenderError.unresolvablePath(spinePath)
        }

        cancelPendingWork()

        // Loading over the custom scheme means relative subresource requests resolve against it
        // too, so they arrive back at the handler.
        webView.load(URLRequest(url: url))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            navigationContinuation = continuation
        }

        // Cleared before the measurement rather than after it. A throw here leaves the renderer
        // holding the document it no longer shows, and a count belonging to that document beside a
        // page and a progression belonging to this one is a state no caller can read: the debug
        // screen reported `1/43` for a blank document with its next control enabled.
        currentPage = 0
        progression = 0
        pageCount = 0
        currentPageOffset = 0

        let count = try await measurePageCount()
        pageCount = count
        confirmationTask = makeConfirmationTask()

        return count
    }

    /// Waits for the document to stop moving of its own accord.
    ///
    /// Neither the page count nor the page shown depends on this: `load` returns a count measured
    /// at `didFinish`, and `showPage` returns once the document is showing what was asked for. What
    /// waiting here buys is a document that WebKit has finished laying out, so that nothing will
    /// move under a caller which is about to read it. See `holdCurrentPage`.
    ///
    /// A resize is waited on as well as a load. A size change cancels the confirmation belonging to
    /// the old layout and starts its own work, so waiting on the confirmation alone would return
    /// while the document was still being laid out again.
    func settle() async {
        await confirmationTask?.value
        await sizeChangeTask?.value
    }

    /// Shows a page of the loaded document, clamped to the pages that exist, and returns once the
    /// document is showing it.
    ///
    /// A scroll requested from JavaScript is carried out by the scroll view rather than by the
    /// script, so the document keeps reporting the previous offset for a short while after the
    /// script returns: measured at 20 to 35 ms for the first page turn into a freshly loaded
    /// document, and within a single round trip after that. The offset is therefore read back
    /// rather than assumed, since a caller that samples the document immediately after paging would
    /// otherwise be told about the page it has just left.
    func showPage(_ index: Int, timeout: TimeInterval = 1) async {
        // A superseded turn writes nothing. Its `currentPage` belongs to whoever overtook it, which
        // during a rotation is `repaginate` restoring a rounded page, and recording the fraction
        // from that would snap the saved position onto a boundary of the new layout.
        guard await goToPage(index, timeout: timeout) else { return }
        // Recorded from the reader's own page turns only. A page laid out again is restored from
        // this fraction, and restoring must not then rewrite it: rounding to the nearest page each
        // time would let the position wander across repeated rotations.
        progression = Double(currentPage) / Double(max(pageCount - 1, 1))
    }

    /// Scrolls to a page, returning whether this request saw itself through. A request overtaken by
    /// a newer one, or cancelled, returns false and leaves the document to whoever overtook it.
    @discardableResult
    private func goToPage(_ index: Int, timeout: TimeInterval = 1) async -> Bool {
        pageRequests += 1
        pagesInFlight += 1
        defer { pagesInFlight -= 1 }

        let request = pageRequests
        currentPage = min(max(index, 0), max(pageCount - 1, 0))

        // The offset is computed inside the document, from the width the document is laid out
        // against, and returned so that the check below verifies the scroll that was actually
        // performed rather than one recomputed from a width this side believes in.
        let script = """
        var offset = \(currentPage) * (window.innerWidth + \(settings.columnGapPx));
        window.scrollTo(offset, 0);
        String(offset);
        """
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        if let offset = Double((result as? String) ?? "") {
            currentPageOffset = offset
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // A page asked for since this one supersedes it, and waiting for an offset nobody wants
            // any more would hold up whoever asked for the newer page.
            guard request == pageRequests, !Task.isCancelled else { return false }
            if await isShowingCurrentPage() { return true }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        // The page was asked for and nothing overtook it, so it stands as the page being shown even
        // though the offset could not be confirmed inside the timeout.
        return true
    }

    /// Whether the document is showing the page that was asked for.
    ///
    /// The scroll view is asked wherever there is one, because it holds what is on screen. The
    /// document's own `pageXOffset` is updated by a rendering update, so it lags behind the scroll
    /// view whenever the web process has nothing else to draw, and answering from it would report a
    /// page turn as unfinished long after the reader could see it.
    private func isShowingCurrentPage() async -> Bool {
        let target = currentPageOffset
        #if !os(macOS)
        // Points and CSS pixels are the same size here: the injected viewport element maps the
        // document to the device width at a scale of one.
        return abs(Double(webView.scrollView.contentOffset.x) - target) < Self.pageOffsetTolerance
        #else
        // Compared within a tolerance rather than for equality. These are floating-point offsets,
        // and one that lands on a device-pixel-snapped value would never satisfy an exact check,
        // leaving every page turn to wait out its timeout while `holdCurrentPage` re-scrolls.
        let script = """
        String(Math.abs(window.pageXOffset - \(target)) < \(Self.pageOffsetTolerance))
        """
        let showing = try? await webView.evaluateJavaScript(
            script,
            contentWorld: EpubWebViewFactory.contentWorld
        ) as? String
        return showing == "true"
        #endif
    }

    // MARK: - Measurement

    private struct Metrics {
        let scrollWidth: Double
        let viewportWidth: Double
    }

    /// `n` columns span `n * width + (n - 1) * gap`, so the gap belongs in the expression even
    /// while it is zero: without it the count drifts low as the error accumulates across a long
    /// document.
    private func measurePageCount() async throws -> Int {
        let metrics = try await readMetrics()
        guard metrics.viewportWidth > 0 else {
            throw RenderError.measurementFailed("the web view has no width")
        }
        let gap = Double(settings.columnGapPx)
        return max(1, Int(((metrics.scrollWidth + gap) / (metrics.viewportWidth + gap)).rounded()))
    }

    /// Waits for the document to be laid out against the width the web view now has.
    ///
    /// A size change is delivered to the view before the web content process has acted on it, so a
    /// measurement taken when `layoutSubviews` fires describes the layout being replaced, and a
    /// debounce only makes that more likely by measuring promptly after the last of a run of
    /// layout passes. The count then belongs to the size before the current one: an iPad entering a
    /// split view kept the full-width count of 1 while the document had already reflowed to
    /// `innerWidth` 412 and `scrollWidth` 1236, and nudging the divider afterwards measured that
    /// 412 layout, reporting 3 for a document by then laid out at 449 and occupying 2 pages. Each
    /// resize reported the resize before it, and only a further one put the count right.
    ///
    /// The bounds are the expectation and the document remains the authority: this waits until the
    /// two agree, then measures what the document reports. Giving up returns to the old behaviour
    /// of measuring whatever is there, which is no worse than not waiting at all.
    private func waitForViewport(timeout: TimeInterval = 1) async {
        let expected = Double(webView.bounds.width)
        guard expected > 0 else { return }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard !Task.isCancelled else { return }
            let script = "String(window.innerWidth)"
            let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
            // `innerWidth` is an integer and the bounds can be fractional, so they agree to within
            // a point rather than exactly.
            if let width = Double((result as? String) ?? ""), abs(width - expected) <= 1 {
                return
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private func readMetrics() async throws -> Metrics {
        // Returned as one string and parsed here: passing structured values across the JavaScript
        // boundary is less predictable than parsing a known format.
        let script = "String(document.documentElement.scrollWidth) + ',' + String(window.innerWidth)"
        let result = try await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)

        guard let report = result as? String else {
            throw RenderError.measurementFailed(
                "expected a string, got \(result.map { String(describing: type(of: $0)) } ?? "nil")"
            )
        }
        let values = report.split(separator: ",").compactMap { Double($0) }
        guard values.count == 2 else {
            throw RenderError.measurementFailed("could not parse '\(report)'")
        }
        return Metrics(scrollWidth: values[0], viewportWidth: values[1])
    }

    /// Re-measures the loaded document and returns the reader to where they had read to.
    ///
    /// The page index is not what is restored. A page belongs to a viewport, so re-fragmenting a
    /// document moves the text across the pages that hold it: measured at 320 px and rotated to
    /// 480, a document of 29 pages became 32, and the paragraph on page 10 moved to page 12. A
    /// reader kept on page 10 would be handed text they had already read, by a margin that grows
    /// with how far into the document they are. `progression` is restored instead.
    private func repaginate() async {
        await waitForViewport()
        guard let count = try? await measurePageCount() else { return }
        // Measuring suspends, and the document measured may no longer be the one on screen: a host
        // that loads the next chapter mid-resize cancels this, and without the check the count and
        // the scroll below would be applied to the document that has just replaced it, showing the
        // previous chapter's progression in the new one.
        guard !Task.isCancelled else { return }

        let changed = count != pageCount
        pageCount = count
        await goToPage(Int((progression * Double(max(count - 1, 1))).rounded()))

        if changed {
            onRepaginate?(count)
        }
    }

    /// Keeps the document on the page being read while a layout settles.
    ///
    /// WebKit lays a document out again shortly after it loads, and re-fragmenting a multi-column
    /// document returns the scroll view to its first column. Measuring provokes the same thing,
    /// since reading `scrollWidth` flushes a pending layout. Either way the reset is delivered a
    /// frame or two after the event that caused it, so a page applied before it is silently lost:
    /// walking a 29 page document returned exactly one page per walk to the start, at a different
    /// page each time. The offset is therefore watched over a short window and restored when it has
    /// been lost.
    ///
    /// A page turn that is still settling is left alone. Whoever asked for it is the authority on
    /// where the document is going, and a correction issued alongside their scroll would land after
    /// it and take the reader back.
    private func holdCurrentPage(through window: TimeInterval = 0.5) async {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            let request = pageRequests
            try? await Task.sleep(nanoseconds: 32_000_000)
            guard !Task.isCancelled else { return }

            // Only a document nobody is paging is corrected, and reading the offset suspends, so
            // the quiet is checked on both sides of the reading. A scroll issued alongside a page
            // turn is not recalled by the turn that follows it: it is applied whenever the scroll
            // view gets to it, which can be after the newer page has arrived, and the reader is
            // taken back to where they no longer are.
            guard pagesInFlight == 0, request == pageRequests else { continue }
            guard await !isShowingCurrentPage() else { continue }
            guard pagesInFlight == 0, request == pageRequests else { continue }

            await goToPage(currentPage)
        }
    }

    /// Holds the document steady after a load, and confirms the count when the document can still
    /// move.
    ///
    /// The count does not depend on the confirmation: `scrollWidth` was correct at `didFinish` for
    /// all 211 documents of the measured corpus. What it covers is the image that decodes after
    /// navigation ends and re-flows the document behind a count already reported. A document whose
    /// images have all arrived cannot do that, and measuring it again would only provoke the layout
    /// `holdCurrentPage` exists to absorb.
    private func makeConfirmationTask() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            if await hasPendingImages() {
                await waitForImages()
                guard !Task.isCancelled else { return }
                await repaginate()
            }
            await holdCurrentPage()
        }
    }

    private func hasPendingImages() async -> Bool {
        let script = "String(Array.prototype.some.call(document.images, function(i) { return !i.complete; }))"
        let pending = try? await webView.evaluateJavaScript(
            script,
            contentWorld: EpubWebViewFactory.contentWorld
        ) as? String
        return pending == "true"
    }

    /// A blocked image reports itself complete as well, so this settles both outcomes rather than
    /// waiting out the timeout on a book whose remote images the rule list stopped.
    private func waitForImages(timeout: TimeInterval = 2) async {
        let script = "String(Array.prototype.every.call(document.images, function(i) { return i.complete; }))"
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let complete = try? await webView.evaluateJavaScript(
                script,
                contentWorld: EpubWebViewFactory.contentWorld
            ) as? String
            if complete == "true" || Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - Viewport

    private func handleSizeChange() {
        // Nothing is paginated until a document is loaded, and the first layout of an empty web
        // view is a size change like any other.
        guard webView.url != nil else { return }

        // A confirmation belongs to the layout it was started for. Left running alongside the work
        // below, its `holdCurrentPage` would hold the document to an offset computed against the
        // old width while this one restores against the new, each invalidating the other's request
        // guard, and its `repaginate` would write a count measured partway through the resize.
        confirmationTask?.cancel()
        sizeChangeTask?.cancel()
        sizeChangeTask = Task { [weak self] in
            // The bounds have changed, which is not the same as the document having been laid out
            // against them again.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self, !Task.isCancelled else { return }
            await repaginate()
            await holdCurrentPage()
        }
    }

    /// Abandons the work belonging to the document being replaced. A continuation left unresumed
    /// is a leak, and a confirmation that outlives its document would re-measure the next one.
    private func cancelPendingWork() {
        confirmationTask?.cancel()
        confirmationTask = nil
        sizeChangeTask?.cancel()
        sizeChangeTask = nil
        navigationContinuation?.resume(throwing: RenderError.superseded)
        navigationContinuation = nil
    }

    private func finishNavigation(with error: (any Error)?) {
        if let error {
            navigationContinuation?.resume(throwing: RenderError.navigationFailed(error.localizedDescription))
        } else {
            navigationContinuation?.resume()
        }
        navigationContinuation = nil
    }
}

// MARK: - Navigation

extension EpubSpineRenderer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Alongside the content rule list, which is what stops subresource loads: only our own
        // scheme is allowed to navigate.
        navigationAction.request.url?.scheme == EpubSchemeHandler.scheme ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(with: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishNavigation(with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finishNavigation(with: error)
    }
}

// MARK: - Size reporting

/// A web view that reports changes to its own size.
///
/// The relationship between a page count and the viewport it was measured against belongs to the
/// renderer rather than to whatever chrome the web view is placed in, and a host that shows and
/// hides its chrome changes that size without being asked to say so.
private final class SizeReportingWebView: WKWebView {
    var onSizeChange: (() -> Void)?

    private var lastSize: CGSize = .zero

    #if os(macOS)
    override func layout() {
        super.layout()
        reportSizeChange()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        reportSizeChange()
    }
    #endif

    /// Any change at all is reported, deliberately unlike `ReaderPagedTextViewController`, which
    /// ignores one below 10 points to keep `NSLayoutManager` from repaginating in a loop. Nothing
    /// here feeds back into the size, so there is no loop to guard against, and a change of a few
    /// points still moves every page boundary: a column is `100vw`, so ignoring it would leave the
    /// offsets computed against a width the document is no longer laid out at. Churn during a
    /// rotation is absorbed by the debounce in `handleSizeChange` instead.
    private func reportSizeChange() {
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onSizeChange?()
    }
}
