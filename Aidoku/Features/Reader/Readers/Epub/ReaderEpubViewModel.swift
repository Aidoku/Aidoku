//
//  ReaderEpubViewModel.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation
import UIKit

// the book's state: the spine, the table of contents, the page index the measurement pass fills,
// and where the reader is. the paged style turns pages in EpubPagedViewController and reports back
// here; the scroll style reads through the one renderer this model owns
@MainActor
final class ReaderEpubViewModel {
    enum LoadError: Error {
        case unreadableBook(URL)
    }

    let bookURL: URL

    let spinePaths: [String]

    let toc: EpubTableOfContents

    private(set) var index: EpubPageIndex
    private(set) var currentDocument = 0

    /// The scroll style's renderer. The paged style has no single renderer: each visible page
    /// leases one from the paged controller's roster.
    private(set) var renderer: EpubSpineRenderer?

    private let provider: any EpubResourceProvider
    private let measurer: EpubSpineMeasurer
    private var viewport: CGSize = .zero

    // shared with the measurement pass; a count is only valid at the settings it was measured with
    private let settings: EpubPaginationSettings

    var paged: Bool { settings.paged }

    // measuring before open would start a second pass over the same renderer
    private var isOpen = false

    var onChange: (() -> Void)?

    var onLink: ((String, String?) -> Void)?
    var onExternalLink: ((URL) -> Void)?

    var onOverscroll: ((Bool) -> Void)?

    // spine paths the pass could not lay out; each is still counted as one page, so a book with one
    // in it can be finished
    private(set) var unmeasurable: [String] = []

    // held, not dropped: a dropped resume leaves the reader at page 1, which then overwrites the
    // progress being resumed to
    private(set) var pendingBookPage: Int?

    // the paged controller's report of where the reader is; the scroll style asks its renderer
    private var pagedPageInDocument = 0

    var canShowPendingBookPage: Bool {
        guard let pendingBookPage else { return false }
        return index.position(ofBookPage: pendingBookPage) != nil
    }

    var pageInDocument: Int {
        paged ? pagedPageInDocument : renderer?.currentPage ?? 0
    }

    var bookPage: Int? {
        index.bookPage(forDocumentAt: currentDocument, page: pageInDocument)
    }

    // the anchor an in-session rebuild restores from
    var edgeInDocument: Double? {
        // swiftlint:disable:next empty_count
        guard let count = index.pageCount(forDocumentAt: currentDocument), count > 0 else { return nil }
        if !paged, let precise = renderer?.scrollEdgeFraction {
            return precise
        }
        return Double(pageInDocument) / Double(count)
    }

    var bookTotal: Int {
        index.total
    }

    var isMeasured: Bool {
        index.isComplete
    }

    // withheld until measured; a fraction of a lower bound overstates how far the reader is
    var progression: Double? {
        // where within the page the position sits, per EpubPageIndex.progression
        let anchor = paged
            ? Double(settings.columnCount - 1) / Double(settings.columnCount)
            : 0
        return index.progression(forDocumentAt: currentDocument, page: pageInDocument, anchor: anchor)
    }

    init(bookURL: URL, settings: EpubPaginationSettings = .default) throws {
        guard let book = EpubParser.parse(url: bookURL) else {
            throw LoadError.unreadableBook(bookURL)
        }
        self.bookURL = bookURL
        self.settings = settings
        self.spinePaths = book.chapters.flatMap(\.hrefs)
        self.toc = EpubTableOfContents(toc: book.toc, spinePaths: spinePaths)
        self.index = EpubPageIndex(spinePaths: spinePaths)
        self.provider = try EpubZipResourceProvider(url: bookURL)
        self.measurer = EpubSpineMeasurer(provider: provider, settings: settings)
    }

    // MARK: - The paged style

    /// What the paged controller builds its pages from. Positions all resolve because
    /// `openPaged` completes the index before any page exists.
    func makePagedBook() -> EpubPagedViewController.Book {
        EpubPagedViewController.Book(
            spinePaths: spinePaths,
            total: { [weak self] in self?.index.total ?? 0 },
            position: { [weak self] bookPage in
                (self?.index.position(ofBookPage: bookPage)).map { ($0.document, $0.page) }
            },
            makeRenderer: { [provider, settings] in
                try await EpubSpineRenderer(provider: provider, settings: settings)
            }
        )
    }

    /// Measures the whole book before anything is shown: the page controller needs every page to
    /// have an address, and the toolbar reports the total once rather than incrementally.
    func openPaged(viewport: CGSize) async {
        self.viewport = viewport
        isOpen = true
        await withCheckedContinuation { continuation in
            startMeasuring(onFinish: { continuation.resume() })
        }
    }

    /// The paged controller's report of where the reader now is.
    func notePagedPosition(bookPage: Int) {
        guard let position = index.position(ofBookPage: bookPage) else { return }
        pendingBookPage = nil
        currentDocument = position.document
        pagedPageInDocument = position.page
        onChange?()
    }

    /// Where a book page sits, for the paged controller's navigation.
    func startOfDocument(at document: Int) -> Int? {
        index.startOfDocument(at: document)
    }

    // MARK: - The scroll style

    func prepareRenderer() async throws -> EpubSpineRenderer {
        if let renderer { return renderer }
        let renderer = try await EpubSpineRenderer(provider: provider, settings: settings)
        wire(renderer)
        self.renderer = renderer
        return renderer
    }

    private func wire(_ renderer: EpubSpineRenderer) {
        renderer.onScroll = { [weak self] in self?.onChange?() }
        renderer.onOverscroll = { [weak self] forward in self?.onOverscroll?(forward) }
        renderer.onLinkActivated = { [weak self] path, fragment in self?.onLink?(path, fragment) }
        renderer.onExternalLinkActivated = { [weak self] url in self?.onExternalLink?(url) }
        renderer.onRepaginate = { [weak self] count in
            guard let self else { return }
            index.setPageCount(count, forDocumentAt: currentDocument)
            onChange?()
        }
        renderer.onContentProcessTerminated = { [weak self] in
            // a web view whose content process ended shows nothing until the document is put back
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await loadCurrentDocument()
                } catch {
                    LogManager.logger.error(
                        "ReaderEpubViewModel: could not reload \(spinePaths[currentDocument]): \(error)"
                    )
                }
            }
        }
    }

    func open(viewport: CGSize, atDocument document: Int = 0) async throws {
        self.viewport = viewport
        isOpen = true
        currentDocument = min(max(document, 0), max(spinePaths.count - 1, 0))
        try await loadCurrentDocument()
        startMeasuring()
    }

    func moveForward(animated: Bool = false) async {
        pendingBookPage = nil
        guard let renderer else { return }
        if renderer.scrollByViewport(forward: true, animated: animated) {
            onChange?()
        } else if spinePaths.indices.contains(currentDocument + 1) {
            await move(toDocument: currentDocument + 1, landingOnLastPage: false, animated: animated)
        }
    }

    func moveBackward(animated: Bool = false) async {
        pendingBookPage = nil
        guard let renderer else { return }
        if renderer.scrollByViewport(forward: false, animated: animated) {
            onChange?()
        } else if spinePaths.indices.contains(currentDocument - 1) {
            await move(toDocument: currentDocument - 1, landingOnLastPage: true, animated: animated)
        }
    }

    // before open, or the first counts to land read as the reader sitting at the head of the book
    func holdBookPage(_ page: Int) {
        pendingBookPage = page
    }

    func showBookPage(_ page: Int) async {
        guard let position = index.position(ofBookPage: page) else {
            pendingBookPage = page
            return
        }
        pendingBookPage = nil
        if position.document == currentDocument {
            await renderer?.showPage(position.page)
            onChange?()
        } else {
            await move(toDocument: position.document, landingOnLastPage: false, page: position.page)
        }
    }

    func imageData(at point: CGPoint, renderer: EpubSpineRenderer? = nil) async -> Data? {
        guard
            let source = await (renderer ?? self.renderer)?.imageSource(at: point),
            let url = URL(string: source),
            // only the book's own scheme: a data or remote url has no resource to read
            url.scheme == EpubSchemeHandler.scheme
        else { return nil }
        return try? await provider.data(at: EpubSchemeHandler.resourcePath(from: url))
    }

    func showPendingBookPage() async {
        guard let page = pendingBookPage else { return }
        await showBookPage(page)
    }

    func setScrollPadding(_ clearance: UIEdgeInsets) {
        renderer?.setScrollPadding(clearance)
        measurer.setScrollPadding(clearance)
    }

    func viewportChanged(to size: CGSize) {
        guard isOpen, size != viewport, size.width > 0, size.height > 0 else { return }
        viewport = size
        index.invalidate()
        startMeasuring()
        onChange?()
    }

    func pauseMeasuring() {
        measurer.pause()
    }

    func resumeMeasuring() {
        measurer.resume()
    }

    func showEntry(_ entry: EpubTableOfContents.Entry) async {
        pendingBookPage = nil
        await show(document: entry.document, fragment: entry.fragment)
    }

    // a path outside the spine has no page in the book, so it is logged rather than navigated to
    func showLocation(path: String, fragment: String?) async {
        guard let document = spinePaths.firstIndex(of: path) else {
            LogManager.logger.warn("ReaderEpubViewModel: link to \(path) is not in the spine")
            return
        }
        pendingBookPage = nil
        await show(document: document, fragment: fragment)
    }

    // asked of the layout: a book converted from one file shares a spine index across every entry
    func currentEntry(renderer: EpubSpineRenderer? = nil) async -> EpubTableOfContents.Entry? {
        let renderer = renderer ?? self.renderer
        let fragments = toc.entries(inDocument: currentDocument).compactMap(\.fragment)
        guard !fragments.isEmpty, let renderer else {
            return toc.entry(inDocument: currentDocument)
        }
        let pages = await renderer.fragmentPages(fragments)
        return toc.entry(inDocument: currentDocument, atOrBefore: pageInDocument, fragmentPages: pages)
    }

    func bookPage(ofEntry entry: EpubTableOfContents.Entry) -> Int? {
        index.startOfDocument(at: entry.document).map { $0 + 1 }
    }

    func show(document: Int, fragment: String?) async {
        pendingBookPage = nil
        guard document != currentDocument else {
            guard
                let fragment,
                let page = await renderer?.fragmentPages([fragment])[fragment]
            else {
                await renderer?.showPage(0)
                onChange?()
                return
            }
            await renderer?.showPage(page)
            onChange?()
            return
        }
        await move(toDocument: document, landingOnLastPage: false, fragment: fragment)
    }

    private func move(
        toDocument document: Int,
        landingOnLastPage: Bool,
        page: Int = 0,
        fragment: String? = nil,
        animated: Bool = false
    ) async {
        guard spinePaths.indices.contains(document), let renderer else { return }
        let forward = document > currentDocument

        // the turn replaces the document, so a snapshot of the outgoing page covers the load
        var snapshot: UIView?
        if animated, renderer.webView.window != nil,
           let cover = renderer.webView.snapshotView(afterScreenUpdates: false) {
            cover.frame = renderer.webView.frame
            renderer.webView.superview?.addSubview(cover)
            snapshot = cover
        }

        measurer.pause()
        defer { measurer.resume() }

        // a load lands at the head and is only then scrolled, so moving into a document would
        // visibly run through it; hidden across both steps unless the head is the target. one
        // web view for the whole style, so hiding and showing name the same view
        let target = landingOnLastPage ? Int.max : page
        let hides = (target != 0 || fragment != nil) && snapshot == nil
        if hides {
            renderer.webView.alpha = 0
        }
        defer {
            if hides {
                renderer.webView.alpha = 1
            }
        }

        currentDocument = document
        var loaded = false
        do {
            let count = try await loadCurrentDocument()
            var landing = landingOnLastPage ? count - 1 : page
            if let fragment, let resolved = await renderer.fragmentPages([fragment])[fragment] {
                landing = resolved
            }
            await renderer.showPage(landing)
            loaded = true
        } catch {
            LogManager.logger.error("ReaderEpubViewModel: could not load \(spinePaths[document]): \(error)")
        }

        if let snapshot {
            if loaded {
                // along the axis the style reads in: the scroll style turns a chapter vertically
                let webView = renderer.webView
                let extent = webView.bounds.height * (forward ? 1 : -1)
                webView.transform = CGAffineTransform(translationX: 0, y: extent)
                await withCheckedContinuation { continuation in
                    UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                        webView.transform = .identity
                        snapshot.transform = CGAffineTransform(translationX: 0, y: -extent)
                    } completion: { _ in
                        snapshot.removeFromSuperview()
                        continuation.resume()
                    }
                }
            } else {
                snapshot.removeFromSuperview()
            }
        }
        onChange?()
    }

    @discardableResult
    private func loadCurrentDocument() async throws -> Int {
        guard let renderer, spinePaths.indices.contains(currentDocument) else { return 0 }
        let count = try await renderer.load(spinePath: spinePaths[currentDocument])
        index.setPageCount(count, forDocumentAt: currentDocument)
        onChange?()
        return count
    }

    // MARK: - Measurement

    private func startMeasuring(onFinish: (() -> Void)? = nil) {
        guard viewport.width > 0, viewport.height > 0 else {
            onFinish?()
            return
        }
        measurer.start(
            spinePaths: spinePaths,
            viewport: viewport,
            // the scroll style's reading renderer has already counted the document it is showing
            skipping: index.pageCount(forDocumentAt: currentDocument) != nil ? [currentDocument] : [],
            onCount: { [weak self] document, count in
                guard let self else { return }
                index.setPageCount(count, forDocumentAt: document)
                onChange?()
            },
            onFailure: { [weak self] document in
                guard let self else { return }
                // one page rather than unknown: the index answers nothing about a position after
                // an unmeasured document, which froze the toolbar and never marked the book read
                index.setPageCount(1, forDocumentAt: document)
                onChange?()
            },
            onFinish: { [weak self] outcome in
                defer { onFinish?() }
                guard let self else { return }
                guard !outcome.cancelled else { return }
                if !outcome.failed.isEmpty {
                    LogManager.logger.error(
                        "ReaderEpubViewModel: \(outcome.failed.count) documents could not be laid out"
                    )
                }
                unmeasurable = outcome.failed
                onChange?()
            }
        )
    }
}
