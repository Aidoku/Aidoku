//
//  EpubSpineRenderer.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/11/26.
//

import Foundation
import WebKit

// renders the documents of one epub spine, laid out in columns by readium-css. one web view serves
// the whole spine: cost follows the number of documents rather than their size, and reuse keeps the
// footprint flat.
//
// a page count belongs to a viewport size, since a column is 100vh by 100vw and any change to
// either re-fragments the document and moves every page boundary
@MainActor
final class EpubSpineRenderer: NSObject {
    enum RenderError: Error {
        case unresolvablePath(String)
        case navigationFailed(String)
        // abandoned because another navigation began
        case superseded
        case measurementFailed(String)
    }

    // the view the host places in its hierarchy. its size is the viewport every count is measured
    // against
    let webView: WKWebView

    private(set) var pageCount = 0
    private(set) var currentPage = 0

    // the position that survives a document being laid out again, where a page index does not: a
    // document of 43 pages at one width was 48 at another. a fraction rather than a pointer into
    // the text, which is what the app already keeps and what both text readers put in
    // HistoryObject.scrollPosition, dividing by one less than the page count as this does.
    // belongs to one spine document
    private(set) var progression: Double = 0

    // scroll mode's precise counterpart to currentPage / pageCount, which rounds the offset to a
    // boundary and the trailing partial screen up, together understating the position by up to a
    // page and resuming a mode switch early. nil for a paged document
    var scrollEdgeFraction: Double? {
        guard !settings.paged else { return nil }
        let contentHeight = Double(webView.scrollView.contentSize.height)
        guard contentHeight > 0 else { return nil }
        return min(max(currentPageOffset / contentHeight, 0), 1)
    }

    // an image decoding after navigation ended, or a change to the web view's size. the page shown
    // is preserved across both
    var onRepaginate: ((Int) -> Void)?

    // a move between spine documents is the book's to make, so a link is reported as a request and
    // the navigation cancelled: one that loaded itself would leave the counts and the spine
    // position describing a document no longer on screen
    var onLinkActivated: ((String, String?) -> Void)?

    private let settings: EpubPaginationSettings
    private var navigationContinuation: CheckedContinuation<Void, any Error>?

    // loading over a navigation in flight makes WebKit report the replaced one as cancelled, and
    // that report arrives after the replacement is installed, so without an identity to compare
    // against the failure of the superseded navigation resumes the healthy one
    private var pendingNavigation: WKNavigation?
    private var confirmationTask: Task<Void, Never>?
    private var sizeChangeTask: Task<Void, Never>?

    // read back from the document rather than computed here: the scroll and the check that
    // verifies it must use one number, and window.innerWidth is a CSSOM long while bounds.width can
    // be fractional. a width held on this side also goes stale the moment the document is laid out
    // again, and at a remembered 412 against a document laid out at 449 every page arrived 37px
    // before its boundary and showed the tail of the page before
    private var currentPageOffset: Double = 0

    // covers device-pixel snapping, not a disagreement about the geometry
    private static let pageOffsetTolerance: Double = 1

    // so work started for one page can tell it has been overtaken
    private var pageRequests = 0
    private var pagesInFlight = 0

    // throws where the content rule list cannot be compiled: a renderer without it would show the
    // book while letting it reach the network
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

        // WebKit resolves 100vh against the web view's bounds rather than the area left visible
        // once insets are applied, so a view whose scroll view insets itself lays out a column
        // taller than it can show and leaves the foot of every page under the chrome
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // a paged document is exactly as tall as its viewport, and a free scroll would leave a
        // column boundary mid-viewport where the offsets no longer describe what is on screen. a
        // scroll-mode document is the opposite, and handleScroll adopts its scrolling
        webView.scrollView.alwaysBounceVertical = !settings.paged
        webView.scrollView.isScrollEnabled = !settings.paged

        // in scroll mode the reading position is the vertical scroll offset, which no page turn
        // reports, so it is observed directly. at 1% steps, since every offset change would rewrite
        // the toolbar once per frame while a finger drags
        if !settings.paged {
            scrollObservation = webView.scrollView.observe(\.contentOffset) { [weak self] _, _ in
                Task { @MainActor in self?.handleScroll() }
            }
        }
    }

    private var scrollObservation: NSKeyValueObservation?

    private func handleScroll() {
        // offsets seen while a document is loading belong to the one being replaced, and adopting
        // them would hand the new document a page and an overscroll it never had
        guard navigationContinuation == nil else { return }
        let scrollView = webView.scrollView
        let viewportHeight = Double(scrollView.bounds.height)
        let offsetY = Double(scrollView.contentOffset.y)
        let maxOffset = Double(scrollView.contentSize.height) - viewportHeight
        let fraction = maxOffset > 0 ? min(max(offsetY / maxOffset, 0), 1) : 0

        // the page follows a free scroll, which keeps the book page and the slider moving, and is
        // adopted as the current target so holdCurrentPage does not scroll the reader back. not
        // while a programmatic turn is in flight, whose target is the authority then.
        //
        // the bottom of the document is the last page even though that page's grid offset sits past
        // the scrollable range, since content is rarely an exact multiple of the viewport
        if pagesInFlight == 0, viewportHeight > 0, pageCount > 0 {
            // within a line's height of the bottom counts as the bottom: the scroll view rests a
            // few points short of its maximum, and a 1pt tolerance left the counter one page shy
            currentPage = offsetY >= maxOffset - 24
                ? pageCount - 1
                : min(max(Int((offsetY / viewportHeight).rounded()), 0), pageCount - 1)
            currentPageOffset = min(max(offsetY, 0), max(maxOffset, 0))
        }

        // a pull past either end is the reader asking to continue, since vertical scrolling cannot
        // cross a spine boundary. fired once per pull and re-armed only once the offset is back
        // inside the scrollable range, so the bounce-back cannot repeat it
        if offsetY > maxOffset + Self.overscrollThreshold || offsetY < -Self.overscrollThreshold {
            if !overscrollTriggered {
                overscrollTriggered = true
                onOverscroll?(offsetY > 0)
            }
        } else if offsetY >= 0 && offsetY <= max(maxOffset, 0) {
            overscrollTriggered = false
        }

        guard abs(fraction - progression) >= 0.01 else { return }
        progression = fraction
        onScroll?()
    }

    // set above the overshoot a normal flick's bounce reaches on an iPad, so arriving at the bottom
    // with momentum does not cross into the next chapter. tuned on a simulator; make it
    // velocity-aware if flicks still cross documents on a device
    private static let overscrollThreshold: Double = 120

    private var overscrollTriggered = false

    // walks up from the element under the point, so a tap inside a linked or captioned image still
    // finds it. an inline svg with no source has no resource to show
    func imageSource(at point: CGPoint) async -> String? {
        let script = """
        (function() {
            var el = document.elementFromPoint(\(point.x), \(point.y));
            while (el) {
                var tag = (el.tagName || '').toLowerCase();
                if (tag === 'img') {
                    return el.currentSrc || el.src || '';
                }
                if (tag === 'image') {
                    var href = el.getAttribute('xlink:href') || el.getAttribute('href');
                    return href ? new URL(href, document.baseURI).href : '';
                }
                el = el.parentElement;
            }
            return '';
        })()
        """
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        guard let source = result as? String, !source.isEmpty else { return nil }
        return source
    }

    // only tables the injection script had to shrink: one that fits its page is readable where it
    // is and needs no preview
    func tableHTML(at point: CGPoint) async -> String? {
        let script = """
        (function() {
            var el = document.elementFromPoint(\(point.x), \(point.y));
            var wrap = el && el.closest ? el.closest('[data-aidoku-table]') : null;
            var table = wrap ? wrap.querySelector('table') : null;
            return table ? table.outerHTML : '';
        })()
        """
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        guard let html = result as? String, !html.isEmpty else { return nil }
        return html
    }

    var onScroll: (() -> Void)?

    // true past the end, false past the start: the gesture that continues into the neighbouring
    // spine document
    var onOverscroll: ((Bool) -> Void)?

    deinit {
        confirmationTask?.cancel()
        sizeChangeTask?.cancel()
    }

    // MARK: - Rendering

    // scrollWidth was already correct at didFinish for all 211 documents of the measured corpus,
    // so the count is available as soon as navigation completes
    @discardableResult
    func load(spinePath: String) async throws -> Int {
        guard let url = EpubSchemeHandler.url(forResourcePath: spinePath) else {
            throw RenderError.unresolvablePath(spinePath)
        }

        cancelPendingWork()

        // a document swap must not inherit the gesture that caused it: a fling's momentum keeps
        // scrolling after the next document has loaded, which showed a document's bottom instead of
        // its start. toggling the pan recognizer cancels a drag still in the reader's finger, which
        // killing the offset alone does not, and re-setting the offset kills a running deceleration
        webView.scrollView.panGestureRecognizer.isEnabled = false
        webView.scrollView.panGestureRecognizer.isEnabled = true
        webView.scrollView.setContentOffset(webView.scrollView.contentOffset, animated: false)

        // cleared before the navigation rather than after it, since a throw from either the
        // navigation or the measurement would otherwise leave a count belonging to the old document
        // beside a page belonging to this one, which the debug screen showed as 1/43 for a blank
        // document
        currentPage = 0
        progression = 0
        pageCount = 0
        currentPageOffset = 0

        // loading over the custom scheme means relative subresource requests resolve against it
        // too, so they arrive back at the handler
        let navigation = webView.load(URLRequest(url: url))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            pendingNavigation = navigation
            navigationContinuation = continuation
        }

        let count = try await measurePageCount()
        pageCount = count
        confirmationTask = makeConfirmationTask()

        return count
    }

    // neither the count nor the page shown depends on this. what it buys is a document WebKit has
    // finished laying out, so nothing moves under a caller about to read it. a resize is waited on
    // as well as a load, since a size change cancels the old layout's confirmation and starts its
    // own work
    func settle() async {
        await confirmationTask?.value
        await sizeChangeTask?.value
    }

    // a scroll requested from javascript is carried out by the scroll view rather than the script,
    // so the document reports the previous offset for 20 to 35ms after the script returns and the
    // offset has to be read back rather than assumed. animated slides for a turn the reader
    // performed; restores, slider jumps and layout corrections stay instant
    func showPage(_ index: Int, animated: Bool = false, timeout: TimeInterval = 1) async {
        // a superseded turn writes nothing: its currentPage belongs to whoever overtook it, which
        // during a rotation is repaginate restoring a rounded page
        guard await goToPage(index, animated: animated, timeout: timeout) else { return }
        // recorded from the reader's own turns only, since a restore reads this fraction and
        // rounding to the nearest page each time would let the position wander across rotations
        progression = Double(currentPage) / Double(max(pageCount - 1, 1))
    }

    // rests a scroll-mode viewport off the page grid, since a restore there has no reason to land
    // on a boundary: the boundary sits before the place being restored, and a later switch back to
    // paged floored a second time from it, walking every paged, scroll, paged round trip one page
    // back. scrollEdgeFraction reads back precisely what is set here
    func showEdge(_ fraction: Double) async {
        guard !settings.paged, pageCount > 0 else { return }
        let script = """
        var offset = Math.max(0, Math.min(
            \(fraction) * document.documentElement.scrollHeight,
            document.documentElement.scrollHeight - window.innerHeight
        ));
        window.scrollTo({left: 0, top: offset, behavior: 'auto'});
        String(offset);
        """
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        guard let offset = Double((result as? String) ?? "") else { return }
        currentPageOffset = offset
        let viewportHeight = Double(webView.scrollView.bounds.height)
        if viewportHeight > 0 {
            currentPage = min(max(Int((offset / viewportHeight).rounded()), 0), max(pageCount - 1, 0))
        }
    }

    // answered in a batch because a book converted from a single file addresses its whole contents
    // by fragment, and one round trip per entry would be paid every time the contents are shown. a
    // fragment the document does not contain is absent rather than defaulted to its first page.
    // measured from this renderer's own offset, which goToPage has confirmed against the scroll
    // view, since the document's pageXOffset lags what is on screen
    func fragmentPages(_ fragments: [String]) async -> [String: Int] {
        guard !fragments.isEmpty, pageCount > 0 else { return [:] }
        guard
            let data = try? JSONSerialization.data(withJSONObject: Array(Set(fragments))),
            let list = String(data: data, encoding: .utf8)
        else { return [:] }

        let extent = settings.paged
            ? "window.innerWidth + \(settings.columnGapPx)"
            : "window.innerHeight"
        let start = settings.paged ? "rect.left" : "rect.top"
        let script = """
        var ids = \(list);
        var pitch = \(extent);
        var out = {};
        for (var i = 0; i < ids.length; i++) {
            var el = document.getElementById(ids[i]);
            if (!el && window.CSS && CSS.escape) {
                el = document.querySelector('[name=' + CSS.escape(ids[i]) + ']');
            }
            if (!el || pitch <= 0) { continue; }
            var rect = el.getBoundingClientRect();
            out[ids[i]] = Math.max(0, Math.floor((\(start) + \(currentPageOffset)) / pitch));
        }
        JSON.stringify(out);
        """
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        guard
            let json = (result as? String)?.data(using: .utf8),
            let pages = try? JSONSerialization.jsonObject(with: json) as? [String: Int]
        else { return [:] }
        // a page past the end is a measurement taken while the document was being laid out again
        return pages.mapValues { min(max($0, 0), max(pageCount - 1, 0)) }
    }

    // returns whether this request saw itself through: one overtaken by a newer request, or
    // cancelled, returns false and leaves the document to whoever overtook it
    @discardableResult
    private func goToPage(_ index: Int, animated: Bool = false, timeout: TimeInterval = 1) async -> Bool {
        pageRequests += 1
        pagesInFlight += 1
        defer { pagesInFlight -= 1 }

        let request = pageRequests
        currentPage = min(max(index, 0), max(pageCount - 1, 0))

        // the offset is computed inside the document and returned, so the check below verifies the
        // scroll that was performed rather than one recomputed from a size this side believes in.
        // paged pages are column offsets along x, scroll-mode pages viewport heights along y
        let behavior = animated ? "smooth" : "auto"
        let script = settings.paged ? """
        var offset = \(currentPage) * (window.innerWidth + \(settings.columnGapPx));
        window.scrollTo({left: offset, top: 0, behavior: '\(behavior)'});
        String(offset);
        """ : """
        var offset = Math.max(0, Math.min(
            \(currentPage) * window.innerHeight,
            document.documentElement.scrollHeight - window.innerHeight
        ));
        window.scrollTo({left: 0, top: offset, behavior: '\(behavior)'});
        String(offset);
        """
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        if let offset = Double((result as? String) ?? "") {
            currentPageOffset = offset
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // a page asked for since this one supersedes it, and waiting on an offset nobody wants
            // would hold up whoever asked for the newer page
            guard request == pageRequests, !Task.isCancelled else { return false }
            if await isShowingCurrentPage() { return true }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        // nothing overtook it, so it stands as the page being shown even though the offset could
        // not be confirmed inside the timeout
        return true
    }

    // the scroll view is asked because it holds what is on screen: the document's own pageXOffset
    // is updated by a rendering update, so it lags whenever the web process has nothing else to
    // draw and would report a page turn as unfinished long after the reader could see it
    private func isShowingCurrentPage() async -> Bool {
        let target = currentPageOffset
        // points and css pixels are the same size here, since the injected viewport element maps
        // the document to the device width at a scale of one
        let offset = settings.paged
            ? Double(webView.scrollView.contentOffset.x)
            : Double(webView.scrollView.contentOffset.y)
        return abs(offset - target) < Self.pageOffsetTolerance
    }

    // MARK: - Measurement

    private struct Metrics {
        let scrollExtent: Double
        let viewportExtent: Double
    }

    // paged: n columns span n * width + (n - 1) * gap, so the gap belongs in the expression even
    // while it is zero, or the count drifts low across a long document. scroll mode: a page is one
    // viewport height, rounded up since a trailing partial screen is still text to be read, with an
    // epsilon against float fuzz at exact multiples
    private func measurePageCount() async throws -> Int {
        let metrics = try await readMetrics()
        guard metrics.viewportExtent > 0 else {
            throw RenderError.measurementFailed("the web view has no size")
        }
        if settings.paged {
            let gap = Double(settings.columnGapPx)
            return max(1, Int(((metrics.scrollExtent + gap) / (metrics.viewportExtent + gap)).rounded()))
        } else {
            return max(1, Int((metrics.scrollExtent / metrics.viewportExtent - 0.01).rounded(.up)))
        }
    }

    // a size change reaches the view before the web content process has acted on it, so measuring
    // when layoutSubviews fires describes the layout being replaced: an iPad entering a split view
    // kept its full-width count while the document had already reflowed, and each resize reported
    // the resize before it. the bounds are the expectation and the document stays the authority,
    // so this waits until the two agree
    private func waitForViewport(timeout: TimeInterval = 1) async {
        let expected = Double(webView.bounds.width)
        guard expected > 0 else { return }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard !Task.isCancelled else { return }
            let script = "String(window.innerWidth)"
            let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
            // innerWidth is an integer and the bounds can be fractional, so they agree to within a
            // point rather than exactly
            if let width = Double((result as? String) ?? ""), abs(width - expected) <= 1 {
                return
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private func readMetrics() async throws -> Metrics {
        // returned as one string and parsed here, since passing structured values across the
        // javascript boundary is less predictable. paged documents extend along x, scrolled along y
        let script = settings.paged
            ? "String(document.documentElement.scrollWidth) + ',' + String(window.innerWidth)"
            : "String(document.documentElement.scrollHeight) + ',' + String(window.innerHeight)"
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
        return Metrics(scrollExtent: values[0], viewportExtent: values[1])
    }

    // progression is restored, not the page index: re-fragmenting moves text across the pages that
    // hold it, and a document of 29 pages at 320px became 32 at 480px with the paragraph on page 10
    // moving to page 12
    private func repaginate() async {
        await waitForViewport()
        guard let count = try? await measurePageCount() else { return }
        // measuring suspends, and the document measured may no longer be the one on screen: a host
        // loading the next chapter mid-resize would otherwise show the previous chapter's
        // progression in the new one
        guard !Task.isCancelled else { return }

        let changed = count != pageCount
        pageCount = count
        await goToPage(Int((progression * Double(max(count - 1, 1))).rounded()))

        if changed {
            onRepaginate?(count)
        }
    }

    // WebKit lays a document out again shortly after it loads, and re-fragmenting a multi-column
    // document returns the scroll view to its first column. the reset arrives a frame or two after
    // the event that caused it, so a page applied before it is silently lost: walking a 29 page
    // document returned exactly one page per walk to the start. a page turn still settling is left
    // alone, since a correction issued alongside its scroll would land after it
    private func holdCurrentPage(through window: TimeInterval = 0.5) async {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            let request = pageRequests
            try? await Task.sleep(nanoseconds: 32_000_000)
            guard !Task.isCancelled else { return }

            // reading the offset suspends, so the quiet is checked on both sides of it: a scroll
            // issued alongside a page turn is not recalled by the turn that follows, and lands
            // whenever the scroll view gets to it
            guard pagesInFlight == 0, request == pageRequests else { continue }
            guard await !isShowingCurrentPage() else { continue }
            guard pagesInFlight == 0, request == pageRequests else { continue }

            await goToPage(currentPage)
        }
    }

    // the count does not depend on this. what it covers is an image that decodes after navigation
    // ends and reflows the document behind a count already reported; a document whose images have
    // all arrived cannot do that, and measuring it again would provoke the very layout
    // holdCurrentPage exists to absorb
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

    // a blocked image reports itself complete too, so this settles both outcomes rather than
    // waiting out the timeout on a book whose remote images the rule list stopped
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
        // the first layout of an empty web view is a size change like any other
        guard webView.url != nil else { return }

        // a confirmation belongs to the layout it was started for: left running, its
        // holdCurrentPage would hold the document to an offset computed against the old width while
        // this one restores against the new
        confirmationTask?.cancel()
        sizeChangeTask?.cancel()
        sizeChangeTask = Task { [weak self] in
            // the bounds have changed, which is not the document having been laid out again
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self, !Task.isCancelled else { return }
            await repaginate()
            await holdCurrentPage()
        }
    }

    // a continuation left unresumed is a leak, and a confirmation that outlives its document would
    // re-measure the next one
    private func cancelPendingWork() {
        confirmationTask?.cancel()
        confirmationTask = nil
        sizeChangeTask?.cancel()
        sizeChangeTask = nil
        navigationContinuation?.resume(throwing: RenderError.superseded)
        navigationContinuation = nil
        pendingNavigation = nil
    }

    // only a definite mismatch is ignored: WebKit types these as implicitly unwrapped, so a nil on
    // either side is treated as the navigation in hand rather than risking a load that never returns
    private func finishNavigation(_ navigation: WKNavigation?, with error: (any Error)?) {
        if let navigation, let pendingNavigation, navigation !== pendingNavigation { return }
        pendingNavigation = nil
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
        // alongside the content rule list, which is what stops subresource loads
        guard let url = navigationAction.request.url, url.scheme == EpubSchemeHandler.scheme else {
            return .cancel
        }
        // a link the reader followed rather than the load this renderer asked for, which only the
        // navigation type tells apart. cancelled and handed to the book, since even a link into the
        // document already loaded would restart it and discard the count belonging to it
        guard navigationAction.navigationType != .linkActivated else {
            // decoded, unlike the path beside it: URL.fragment hands back the encoded form where
            // URL.path hands back a decoded one, so a link to #sec%20one or a CJK anchor would
            // disagree with the decoded anchor the table of contents holds. fragment(percentEncoded:)
            // says so outright and is iOS 16, where this deploys to 15
            let fragment = url.fragment.map { $0.removingPercentEncoding ?? $0 }
            onLinkActivated?(EpubSchemeHandler.resourcePath(from: url), fragment)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(navigation, with: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishNavigation(navigation, with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finishNavigation(navigation, with: error)
    }
}

// MARK: - Size reporting

// a host that shows and hides its chrome changes the web view's size without saying so, and the
// relationship between a count and the viewport it was measured against belongs to the renderer
private final class SizeReportingWebView: WKWebView {
    var onSizeChange: (() -> Void)?

    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        reportSizeChange()
    }

    // any change at all, deliberately unlike ReaderPagedTextViewController, which ignores one below
    // 10 points to keep NSLayoutManager from repaginating in a loop. nothing here feeds back into
    // the size, and a column is 100vw, so a few points still move every page boundary
    private func reportSizeChange() {
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onSizeChange?()
    }
}
