//
//  EpubSpineRenderer.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/11/26.
//

import Foundation
import WebKit

@MainActor
final class EpubSpineRenderer: NSObject {
    enum RenderError: Error {
        case unresolvablePath(String)
        case navigationFailed(String)
        case superseded
        case measurementFailed(String)
    }

    let webView: WKWebView

    private(set) var pageCount = 0
    private(set) var currentPage = 0

    // divides by one less than the page count, as the text readers' scrollPosition does
    private(set) var progression: Double = 0

    // exact where currentPage / pageCount understates the position by up to a page
    var scrollEdgeFraction: Double? {
        guard !settings.paged else { return nil }
        let contentHeight = Double(webView.scrollView.contentSize.height)
        guard contentHeight > 0 else { return nil }
        return min(max(currentPageOffset / contentHeight, 0), 1)
    }

    var onRepaginate: ((Int) -> Void)?

    // the web view is blank from here and does not come back on its own, so whoever owns it has to
    // load the document again rather than keep showing it
    var onContentProcessTerminated: (() -> Void)?

    // reported rather than followed; a self-loading navigation would strand the counts
    var onLinkActivated: ((String, String?) -> Void)?
    var onExternalLinkActivated: ((URL) -> Void)?

    private var settings: EpubPaginationSettings
    private var navigationContinuation: CheckedContinuation<Void, any Error>?

    // without this identity, a superseded navigation's failure resumes the healthy one
    private var pendingNavigation: WKNavigation?
    private var confirmationTask: Task<Void, Never>?
    private var sizeChangeTask: Task<Void, Never>?

    // read back from the document; a width held here goes stale and lands every page short
    private var currentPageOffset: Double = 0

    private static let pageOffsetTolerance: Double = 1

    private var doubleTapObservations: [NSKeyValueObservation] = []

    private var pageRequests = 0
    private var pagesInFlight = 0

    // throws without the rule list, which would show the book while it reached the network
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

        // 100vh resolves against the bounds, not the area insets leave visible
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // a free scroll would leave a paged column boundary mid-viewport
        webView.scrollView.alwaysBounceVertical = !settings.paged
        webView.scrollView.isScrollEnabled = !settings.paged
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false

        if #available(iOS 27.0, *) {
            // a paged view does not scroll, so an edge effect there only fades the first and last
            // lines. the horizontal pair is hidden either way, a page drag is not a scroll
            webView.scrollView.topEdgeEffect.style = settings.paged ? .hard : .soft
            webView.scrollView.bottomEdgeEffect.style = settings.paged ? .hard : .soft
            webView.scrollView.topEdgeEffect.isHidden = settings.paged
            webView.scrollView.bottomEdgeEffect.isHidden = settings.paged
            webView.scrollView.leftEdgeEffect.isHidden = true
            webView.scrollView.rightEdgeEffect.isHidden = true
        }

        // no page turn reports a scroll-mode position; 1% steps keep a drag off the toolbar
        if !settings.paged {
            scrollObservation = webView.scrollView.observe(\.contentOffset) { [weak self] _, _ in
                Task { @MainActor in self?.handleScroll() }
            }
        }
    }

    private var scrollObservation: NSKeyValueObservation?

    private func handleScroll() {
        guard navigationContinuation == nil else { return }
        let scrollView = webView.scrollView
        let viewportHeight = Double(scrollView.bounds.height)
        let offsetY = Double(scrollView.contentOffset.y)
        let maxOffset = Double(scrollView.contentSize.height) - viewportHeight
        let fraction = maxOffset > 0 ? min(max(offsetY / maxOffset, 0), 1) : 0

        if pagesInFlight == 0, viewportHeight > 0, pageCount > 0 {
            // the scroll view rests short of its maximum, so the bottom needs a line's tolerance
            currentPage = offsetY >= maxOffset - 24
                ? pageCount - 1
                : min(max(Int((offsetY / viewportHeight).rounded()), 0), pageCount - 1)
            currentPageOffset = min(max(offsetY, 0), max(maxOffset, 0))
        }

        // re-armed inside the range, so the bounce-back cannot fire this twice. only a live drag
        // or its momentum: a document still settling after a load also carries the offset past the
        // ends, and a crossing from that navigated the reader while a restore was on its way
        if offsetY > maxOffset + Self.overscrollThreshold || offsetY < -Self.overscrollThreshold {
            if !overscrollTriggered, scrollView.isDragging || scrollView.isDecelerating {
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

    // above the overshoot a normal flick reaches, so momentum alone does not cross documents
    private static let overscrollThreshold: Double = 120

    private var overscrollTriggered = false

    enum LinkTarget {
        case inBook(path: String, fragment: String?)
        case external(URL)
    }

    private var pageLock: NSKeyValueObservation?

    var onScroll: (() -> Void)?

    // true past the end, false past the start
    var onOverscroll: ((Bool) -> Void)?

    deinit {
        confirmationTask?.cancel()
        sizeChangeTask?.cancel()
    }

    // MARK: - Rendering

    @discardableResult
    func load(spinePath: String) async throws -> Int {
        guard let url = EpubSchemeHandler.url(forResourcePath: spinePath) else {
            throw RenderError.unresolvablePath(spinePath)
        }

        cancelPendingWork()

        // a fling would keep scrolling into the next document; toggling cancels a live drag
        webView.scrollView.panGestureRecognizer.isEnabled = false
        webView.scrollView.panGestureRecognizer.isEnabled = true
        webView.scrollView.setContentOffset(webView.scrollView.contentOffset, animated: false)

        // before the navigation, or a throw leaves the old count beside this page
        currentPage = 0
        progression = 0
        pageCount = 0
        currentPageOffset = 0

        let navigation = webView.load(URLRequest(url: url))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            pendingNavigation = navigation
            navigationContinuation = continuation
        }

        // the injected viewport meta is applied on a rendering update after the load, so the
        // measurement below could otherwise read a layout the meta has not reached yet
        await waitForViewport()

        let count = try await measurePageCount()
        pageCount = count
        confirmationTask = makeConfirmationTask()

        return count
    }

    // waits out the layout, so nothing moves under a caller about to read it
    func settle() async {
        await confirmationTask?.value
        await sizeChangeTask?.value
    }

    // the document reports the previous offset for ~30ms after the script returns
    // a rotation moves the safe area, and rebuilding the book to re-inject it loses the position
    func setScrollPadding(_ clearance: UIEdgeInsets) {
        guard !settings.paged else { return }
        var updated = settings
        updated.applyScrollClearance(clearance)
        guard updated != settings else { return }
        settings = updated

        // the injection is a user script fixed at configuration time, so later documents need it too
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(EpubWebViewFactory.makeInjectionScript(settings: settings))

        // readium reads the property where it uses it, so the loaded document takes this live
        webView.evaluateJavaScript(
            """
            document.documentElement.style.setProperty('--RS__scrollPaddingTop', '\(settings.scrollPaddingTopPx)px');
            document.documentElement.style.setProperty('--RS__scrollPaddingBottom', '\(settings.scrollPaddingBottomPx)px');
            document.documentElement.style.setProperty('--RS__scrollPaddingLeft', '\(settings.scrollPaddingLeftPx)px');
            document.documentElement.style.setProperty('--RS__scrollPaddingRight', '\(settings.scrollPaddingRightPx)px');
            """,
            in: nil,
            in: EpubWebViewFactory.contentWorld
        )
        // queued behind the property set, so it measures the padded document
        handleSizeChange()
    }

    // two thirds of the viewport, the amount the webtoon and text readers scroll on a tap, so the
    // line being read survives the move. false when the document is already at that end
    func scrollByViewport(forward: Bool, animated: Bool) -> Bool {
        let scrollView = webView.scrollView
        let viewport = scrollView.bounds.height
        guard viewport > 0 else { return false }
        let maxOffset = max(scrollView.contentSize.height - viewport, 0)
        let current = scrollView.contentOffset.y
        guard forward ? current < maxOffset - 1 : current > 1 else { return false }
        let step = viewport * 2 / 3
        let target = min(max(forward ? current + step : current - step, 0), maxOffset)
        // the scroll observation reports the move, so nothing here records the position
        scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: animated)
        return true
    }

    // WebKit re-enables its double tap about a second after the load, so this holds it off rather
    // than disabling it once. a double tap otherwise recentres the page, moving the reader's position
    private func suppressDoubleTapGestures() {
        doubleTapObservations.removeAll()
        var stack: [UIView] = [webView]
        while let view = stack.popLast() {
            for recognizer in view.gestureRecognizers ?? [] {
                // the exact type only: the subclasses at two taps are word selection and the
                // synthesised link click, both of which must keep working
                guard
                    let tap = recognizer as? UITapGestureRecognizer,
                    type(of: tap) == UITapGestureRecognizer.self,
                    tap.numberOfTapsRequired == 2,
                    tap.numberOfTouchesRequired == 1
                else { continue }
                tap.isEnabled = false
                doubleTapObservations.append(tap.observe(\.isEnabled) { tap, _ in
                    if tap.isEnabled { tap.isEnabled = false }
                })
            }
            stack.append(contentsOf: view.subviews)
        }
    }

    var pagePitch: CGFloat {
        webView.bounds.width + CGFloat(settings.columnGapPx)
    }

    // a settle continues the drag: it starts where the finger left the page and carries its speed,
    // where a smooth scrollTo eases in from rest however fast the release was
    func slide(toPage index: Int, velocity: CGFloat) async {
        pageRequests += 1
        pagesInFlight += 1
        defer { pagesInFlight -= 1 }

        currentPage = min(max(index, 0), max(pageCount - 1, 0))
        let target = Double(currentPage) * Double(pagePitch)
        currentPageOffset = target

        let scrollView = webView.scrollView
        let distance = target - Double(scrollView.contentOffset.x)
        // a spring measures its velocity as a fraction of the distance left, and a release aimed
        // away from the target starts the settle at rest rather than pulling further off it
        let spring = distance == 0 ? 0 : min(max(Double(velocity) / distance, 0), Self.settleVelocityLimit)

        await withCheckedContinuation { continuation in
            UIView.animate(
                withDuration: Self.settleDuration,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: spring,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                scrollView.contentOffset.x = CGFloat(target)
            } completion: { _ in
                continuation.resume()
            }
        }

        progression = Double(currentPage) / Double(max(pageCount - 1, 1))
    }

    private static let settleDuration: TimeInterval = 0.3

    // a flick hard enough to carry several pages would otherwise snap the one page it turns
    private static let settleVelocityLimit: Double = 30

    func showPage(_ index: Int, animated: Bool = false, timeout: TimeInterval = 1) async {
        guard await goToPage(index, animated: animated, timeout: timeout) else { return }
        // the reader's own turns only, or the position wanders across repeated restores
        progression = Double(currentPage) / Double(max(pageCount - 1, 1))
    }

    // off the page grid, or a second floor on the way back walks the position backwards
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

    // from this renderer's offset, pageXOffset lagging. a missing fragment is absent, not 0
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
        return pages.mapValues { min(max($0, 0), max(pageCount - 1, 0)) }
    }

    @discardableResult
    private func goToPage(_ index: Int, animated: Bool = false, timeout: TimeInterval = 1) async -> Bool {
        pageRequests += 1
        pagesInFlight += 1
        defer { pagesInFlight -= 1 }

        let request = pageRequests
        currentPage = min(max(index, 0), max(pageCount - 1, 0))

        // returned so the check verifies the scroll performed, not one recomputed here
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
            guard request == pageRequests, !Task.isCancelled else { return false }
            if await isShowingCurrentPage() { return true }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        return true
    }

    private func isShowingCurrentPage() async -> Bool {
        let target = currentPageOffset
        // points and css pixels are the same size here, the viewport being at scale one
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

    // n columns span n * width + (n - 1) * gap; dropping the gap drifts low over a long document
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

    // the view resizes before the content process does, so measuring at layoutSubviews described
    // the layout being replaced and each resize reported the one before it
    private func waitForViewport(timeout: TimeInterval = 1) async {
        let expected = Double(webView.bounds.width)
        guard expected > 0 else { return }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard !Task.isCancelled else { return }
            let script = "String(window.innerWidth)"
            let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
            // innerWidth is an integer and the bounds fractional, so they agree within a point
            if let width = Double((result as? String) ?? ""), abs(width - expected) <= 1 {
                return
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private func readMetrics() async throws -> Metrics {
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

    // progression, not the page index: a relayout moves text across the pages that hold it
    private func repaginate() async {
        await waitForViewport()
        guard let count = try? await measurePageCount() else { return }
        // measuring suspends, so the document may no longer be the one on screen
        guard !Task.isCancelled else { return }

        let changed = count != pageCount
        pageCount = count
        await goToPage(Int((progression * Double(max(count - 1, 1))).rounded()))

        if changed {
            onRepaginate?(count)
        }
    }

    // WebKit relayouts a moment after load and returns a multi-column document to its first
    // column, silently losing a page applied before that. a turn still settling is left alone
    private func holdCurrentPage(through window: TimeInterval = 0.5) async {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            let request = pageRequests
            try? await Task.sleep(nanoseconds: 32_000_000)
            guard !Task.isCancelled else { return }

            guard pagesInFlight == 0, request == pageRequests else { continue }
            guard await !isShowingCurrentPage() else { continue }
            guard pagesInFlight == 0, request == pageRequests else { continue }

            await goToPage(currentPage)
        }
    }

    // covers an image that decodes after navigation ends and reflows behind the reported count
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
        guard webView.url != nil else { return }

        // a confirmation belongs to the layout it started for, and holds an offset from it
        confirmationTask?.cancel()
        sizeChangeTask?.cancel()
        sizeChangeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self, !Task.isCancelled else { return }
            await repaginate()
            await holdCurrentPage()
        }
    }

    private func cancelPendingWork() {
        confirmationTask?.cancel()
        confirmationTask = nil
        sizeChangeTask?.cancel()
        sizeChangeTask = nil
        navigationContinuation?.resume(throwing: RenderError.superseded)
        navigationContinuation = nil
        pendingNavigation = nil
    }

    // only a definite mismatch: these are implicitly unwrapped, and a nil must not strand a load
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

// MARK: - Content hit tests

extension EpubSpineRenderer {
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

    // the paged style disables the web view's touches so the page controller's pan can recognise
    // over text, which also silences WebKit's own link taps; the reader asks here instead, at the
    // point its own tap landed
    func linkTarget(at point: CGPoint) async -> LinkTarget? {
        let script = """
        (function() {
            var el = document.elementFromPoint(\(point.x), \(point.y));
            while (el) {
                if ((el.tagName || '').toLowerCase() === 'a') {
                    var href = el.getAttribute('href');
                    return href ? new URL(href, document.baseURI).href : '';
                }
                el = el.parentElement;
            }
            return '';
        })()
        """
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        guard let href = result as? String, !href.isEmpty, let url = URL(string: href) else { return nil }
        if url.scheme == "http" || url.scheme == "https" {
            return .external(url)
        }
        if url.scheme == EpubSchemeHandler.scheme {
            // URL.fragment is encoded where URL.path is decoded, so this decodes exactly once
            let fragment = url.fragment.map { $0.removingPercentEncoding ?? $0 }
            return .inBook(path: EpubSchemeHandler.resourcePath(from: url), fragment: fragment)
        }
        return nil
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
}

// MARK: - Selection

extension EpubSpineRenderer {
    /// Selects the word under the point and returns it, empty where there is no text: the caret
    /// snaps to the nearest text from an image or a margin, so the word's own rects are checked.
    func selectWord(at point: CGPoint) async -> String {
        let script = """
        (function() {
            var x = \(point.x), y = \(point.y);
            var el = document.elementFromPoint(x, y);
            if (!el || el.tagName === 'IMG' || el.closest('svg')) { return ''; }
            var range = document.caretRangeFromPoint(x, y);
            if (!range) { return ''; }
            var selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            selection.modify('move', 'backward', 'word');
            selection.modify('extend', 'forward', 'word');
            var rects = selection.rangeCount ? selection.getRangeAt(0).getClientRects() : [];
            for (var i = 0; i < rects.length; i++) {
                var r = rects[i];
                if (x >= r.left - 4 && x <= r.right + 4 && y >= r.top - 4 && y <= r.bottom + 4) {
                    return selection.toString();
                }
            }
            selection.removeAllRanges();
            return '';
        })()
        """
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        return (result as? String) ?? ""
    }

    func selectedText() async -> String {
        let script = "window.getSelection().toString()"
        let result = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
        return (result as? String) ?? ""
    }

    func clearSelection() async {
        let script = "window.getSelection().removeAllRanges(); ''"
        _ = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
    }

    /// Holds the scroll view at the page while a selection is live. A handle dragged to the edge
    /// has WebKit scroll the next column in, a page turn the reader never asked for, and a disabled
    /// scroll view stops fingers but not that. Synchronous, so no frame shows the drift.
    func lockPage() {
        guard settings.paged else { return }
        pageLock = webView.scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let target = CGFloat(self.currentPageOffset)
                guard abs(scrollView.contentOffset.x - target) > 0.5 else { return }
                scrollView.contentOffset.x = target
            }
        }
    }

    /// Releases the lock and puts the document's own scroll position back at the page. The
    /// autoscroll moves that in the web process before the scroll view follows, so snapping the
    /// scroll view back left the document where the autoscroll took it, and every hit test after
    /// landed the drift off.
    func unlockPage() async {
        guard pageLock != nil else { return }
        pageLock = nil
        let script = "window.scrollTo(\(currentPageOffset), 0); ''"
        _ = try? await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
    }
}

// MARK: - Navigation

extension EpubSpineRenderer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if navigationAction.navigationType == .linkActivated {
            if url.scheme == "http" || url.scheme == "https" {
                onExternalLinkActivated?(url)
                return .cancel
            }
            if url.scheme == EpubSchemeHandler.scheme {
                // URL.fragment is encoded where URL.path is decoded, so this decodes exactly once
                let fragment = url.fragment.map { $0.removingPercentEncoding ?? $0 }
                onLinkActivated?(EpubSchemeHandler.resourcePath(from: url), fragment)
                return .cancel
            }
        }
        guard url.scheme == EpubSchemeHandler.scheme else {
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        suppressDoubleTapGestures()
        finishNavigation(navigation, with: nil)
    }

    // jettisoned under memory pressure, which three live documents on an iPad reach far sooner than
    // one did. a load waiting on this view would otherwise never be answered
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        LogManager.logger.warn("EpubSpineRenderer: the web content process ended")
        cancelPendingWork()
        pageCount = 0
        currentPage = 0
        currentPageOffset = 0
        navigationContinuation?.resume(throwing: RenderError.navigationFailed("the web content process ended"))
        navigationContinuation = nil
        pendingNavigation = nil
        onContentProcessTerminated?()
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
