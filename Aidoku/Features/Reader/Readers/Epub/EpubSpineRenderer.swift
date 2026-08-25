//
//  EpubSpineRenderer.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/11/26.
//

import Foundation
import WebKit

// a page count belongs to a viewport size, since a column is 100vh by 100vw
@MainActor
final class EpubSpineRenderer: NSObject {
    enum RenderError: Error {
        case unresolvablePath(String)
        case navigationFailed(String)
        case superseded
        case measurementFailed(String)
    }

    // its size is the viewport every count is measured against
    let webView: WKWebView

    private(set) var pageCount = 0
    private(set) var currentPage = 0

    // survives a relayout where a page index does not, and divides by one less than the page count
    // as the text readers' HistoryObject.scrollPosition does. belongs to one spine document
    private(set) var progression: Double = 0

    // currentPage / pageCount understates the position by up to a page, rounding the offset to a
    // boundary and the trailing partial screen up, which resumed a mode switch early
    var scrollEdgeFraction: Double? {
        guard !settings.paged else { return nil }
        let contentHeight = Double(webView.scrollView.contentSize.height)
        guard contentHeight > 0 else { return nil }
        return min(max(currentPageOffset / contentHeight, 0), 1)
    }

    var onRepaginate: ((Int) -> Void)?

    // reported as a request rather than followed: a navigation that loaded itself would leave the
    // counts and the spine position describing a document no longer on screen
    var onLinkActivated: ((String, String?) -> Void)?

    private let settings: EpubPaginationSettings
    private var navigationContinuation: CheckedContinuation<Void, any Error>?

    // WebKit reports a replaced navigation as cancelled after the replacement is installed, so
    // without an identity to compare, the superseded one's failure resumes the healthy one
    private var pendingNavigation: WKNavigation?
    private var confirmationTask: Task<Void, Never>?
    private var sizeChangeTask: Task<Void, Never>?

    // read back from the document rather than computed here, since a width held on this side goes
    // stale: at a remembered 412 against a document laid out at 449, every page arrived 37px early
    private var currentPageOffset: Double = 0

    private static let pageOffsetTolerance: Double = 1

    private var pageRequests = 0
    private var pagesInFlight = 0

    // throws where the content rule list cannot be compiled, which would show the book while
    // letting it reach the network
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

        // WebKit resolves 100vh against the bounds rather than the area insets leave visible, so a
        // self-insetting scroll view puts the foot of every page under the chrome
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // a free scroll would leave a paged document's column boundary mid-viewport, where the
        // offsets no longer describe what is on screen
        webView.scrollView.alwaysBounceVertical = !settings.paged
        webView.scrollView.isScrollEnabled = !settings.paged

        // no page turn reports a scroll-mode position, so the offset is observed directly, at 1%
        // steps to keep a drag from rewriting the toolbar once per frame
        if !settings.paged {
            scrollObservation = webView.scrollView.observe(\.contentOffset) { [weak self] _, _ in
                Task { @MainActor in self?.handleScroll() }
            }
        }
    }

    private var scrollObservation: NSKeyValueObservation?

    private func handleScroll() {
        // offsets seen while loading belong to the document being replaced
        guard navigationContinuation == nil else { return }
        let scrollView = webView.scrollView
        let viewportHeight = Double(scrollView.bounds.height)
        let offsetY = Double(scrollView.contentOffset.y)
        let maxOffset = Double(scrollView.contentSize.height) - viewportHeight
        let fraction = maxOffset > 0 ? min(max(offsetY / maxOffset, 0), 1) : 0

        // adopted as the current target too, so holdCurrentPage does not scroll the reader back
        if pagesInFlight == 0, viewportHeight > 0, pageCount > 0 {
            // the bottom counts as the last page even though its grid offset sits past the
            // scrollable range: the scroll view rests a few points short of its maximum, and a 1pt
            // tolerance left the counter one page shy
            currentPage = offsetY >= maxOffset - 24
                ? pageCount - 1
                : min(max(Int((offsetY / viewportHeight).rounded()), 0), pageCount - 1)
            currentPageOffset = min(max(offsetY, 0), max(maxOffset, 0))
        }

        // re-armed only once the offset is back inside the scrollable range, so the bounce-back
        // cannot fire this twice
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

    // above the overshoot a normal flick's bounce reaches on an iPad, so momentum alone does not
    // cross into the next chapter
    private static let overscrollThreshold: Double = 120

    private var overscrollTriggered = false

    // walks up, so a tap inside a linked or captioned image still finds it
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

    // true past the end, false past the start
    var onOverscroll: ((Bool) -> Void)?

    deinit {
        confirmationTask?.cancel()
        sizeChangeTask?.cancel()
    }

    // MARK: - Rendering

    // scrollWidth is already correct at didFinish, measured across the whole corpus
    @discardableResult
    func load(spinePath: String) async throws -> Int {
        guard let url = EpubSchemeHandler.url(forResourcePath: spinePath) else {
            throw RenderError.unresolvablePath(spinePath)
        }

        cancelPendingWork()

        // a fling's momentum keeps scrolling after the next document loads, showing its bottom
        // instead of its start. toggling the recognizer cancels a drag still in the finger
        webView.scrollView.panGestureRecognizer.isEnabled = false
        webView.scrollView.panGestureRecognizer.isEnabled = true
        webView.scrollView.setContentOffset(webView.scrollView.contentOffset, animated: false)

        // cleared before the navigation, or a throw leaves the old document's count beside this
        // one's page
        currentPage = 0
        progression = 0
        pageCount = 0
        currentPageOffset = 0

        // relative subresource requests resolve against the custom scheme and come back here
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

    // buys a document WebKit has finished laying out, so nothing moves under a caller about to
    // read it. the resize is waited on too, having cancelled the old layout's confirmation
    func settle() async {
        await confirmationTask?.value
        await sizeChangeTask?.value
    }

    // the scroll view carries out a scroll requested from javascript, so the document reports the
    // previous offset for 20 to 35ms afterwards and it has to be read back
    func showPage(_ index: Int, animated: Bool = false, timeout: TimeInterval = 1) async {
        guard await goToPage(index, animated: animated, timeout: timeout) else { return }
        // from the reader's own turns only: a restore reads this fraction back, and rounding it
        // each time would let the position wander across rotations
        progression = Double(currentPage) / Double(max(pageCount - 1, 1))
    }

    // off the page grid: a boundary sits before the place restored, so switching back to paged
    // floored a second time from it and walked every round trip a page back
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

    // measured from this renderer's own offset rather than the document's pageXOffset, which lags
    // what is on screen. a fragment the document lacks is absent rather than defaulted to page one
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
        // a page past the end was measured while the document was being laid out again
        return pages.mapValues { min(max($0, 0), max(pageCount - 1, 0)) }
    }

    // false where a newer request overtook this one, which then owns the document
    @discardableResult
    private func goToPage(_ index: Int, animated: Bool = false, timeout: TimeInterval = 1) async -> Bool {
        pageRequests += 1
        pagesInFlight += 1
        defer { pagesInFlight -= 1 }

        let request = pageRequests
        currentPage = min(max(index, 0), max(pageCount - 1, 0))

        // computed inside the document and returned, so the check below verifies the scroll that
        // was performed rather than one recomputed from a size this side believes in
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
            // waiting on an offset nobody wants would hold up whoever asked for the newer page
            guard request == pageRequests, !Task.isCancelled else { return false }
            if await isShowingCurrentPage() { return true }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        // nothing overtook it, so it stands even though the offset was never confirmed
        return true
    }

    // the scroll view holds what is on screen, where pageXOffset lags a rendering update
    private func isShowingCurrentPage() async -> Bool {
        let target = currentPageOffset
        // points and css pixels are the same size here, the viewport element mapping the document
        // to the device width at a scale of one
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

    // paged: n columns span n * width + (n - 1) * gap, so the gap belongs in the expression even at
    // zero, or the count drifts low across a long document. scrolled: one viewport height a page,
    // rounded up, with an epsilon against float fuzz at exact multiples
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
    // when layoutSubviews fires describes the layout being replaced and each resize reported the
    // resize before it. the bounds are the expectation, the document the authority
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
        // paged documents extend along x, scrolled along y
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

    // progression is restored, not the page index: a document of 29 pages at 320px became 32 at
    // 480px, with the paragraph on page 10 moving to page 12
    private func repaginate() async {
        await waitForViewport()
        guard let count = try? await measurePageCount() else { return }
        // measuring suspends, so a host loading the next chapter mid-resize would otherwise show
        // the previous chapter's progression in the new one
        guard !Task.isCancelled else { return }

        let changed = count != pageCount
        pageCount = count
        await goToPage(Int((progression * Double(max(count - 1, 1))).rounded()))

        if changed {
            onRepaginate?(count)
        }
    }

    // WebKit lays a document out again shortly after it loads, returning a multi-column one to its
    // first column a frame or two later, so a page applied before that is silently lost. a page
    // turn still settling is left alone, since a correction alongside it would land after it
    private func holdCurrentPage(through window: TimeInterval = 0.5) async {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            let request = pageRequests
            try? await Task.sleep(nanoseconds: 32_000_000)
            guard !Task.isCancelled else { return }

            // reading the offset suspends, so the quiet is checked on both sides of it
            guard pagesInFlight == 0, request == pageRequests else { continue }
            guard await !isShowingCurrentPage() else { continue }
            guard pagesInFlight == 0, request == pageRequests else { continue }

            await goToPage(currentPage)
        }
    }

    // covers an image that decodes after navigation ends and reflows the document behind a count
    // already reported. a document whose images have arrived cannot, and measuring it again would
    // provoke the very layout holdCurrentPage absorbs
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

    // a blocked image reports itself complete too, so this settles either way
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

        // a confirmation belongs to the layout it was started for, and would otherwise hold the
        // document to an offset computed against the old width
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

    // a continuation left unresumed is a leak
    private func cancelPendingWork() {
        confirmationTask?.cancel()
        confirmationTask = nil
        sizeChangeTask?.cancel()
        sizeChangeTask = nil
        navigationContinuation?.resume(throwing: RenderError.superseded)
        navigationContinuation = nil
        pendingNavigation = nil
    }

    // only a definite mismatch is ignored: WebKit types these as implicitly unwrapped, and a nil
    // treated as a mismatch would risk a load that never returns
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
        // the content rule list is what stops subresource loads
        guard let url = navigationAction.request.url, url.scheme == EpubSchemeHandler.scheme else {
            return .cancel
        }
        // only the navigation type tells a followed link from the load this renderer asked for.
        // handed to the book and cancelled, since even a link into the loaded document restarts it
        guard navigationAction.navigationType != .linkActivated else {
            // decoded, unlike the path beside it: URL.fragment hands back the encoded form where
            // URL.path hands back a decoded one, so a CJK anchor would disagree with the decoded
            // one the table of contents holds. fragment(percentEncoded:) is iOS 16, this ships to 15
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

private final class SizeReportingWebView: WKWebView {
    var onSizeChange: (() -> Void)?

    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        reportSizeChange()
    }

    // any change at all, unlike ReaderPagedTextViewController's 10 point floor: a column is 100vw,
    // so a few points still move every boundary, and nothing here feeds back into the size
    private func reportSizeChange() {
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onSizeChange?()
    }
}
