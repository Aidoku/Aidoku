//
//  ReaderEpubViewModel.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation
import UIKit

// a page turn at the end of a spine document continues into the next rather than ending the
// chapter, one epub being one chapter
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

    private var pool: EpubLoaderPool?
    private var preloadTask: Task<Void, Never>?
    private(set) var currentLoader: EpubDocumentLoader?

    var renderer: EpubSpineRenderer? { currentLoader?.renderer }

    private let provider: any EpubResourceProvider
    private let measurer: EpubSpineMeasurer
    private var viewport: CGSize = .zero

    // measuring before open would start a second pass over the same renderer
    private var isOpen = false

    var onChange: (() -> Void)?

    var onLink: ((String, String?) -> Void)?
    var onExternalLink: ((URL) -> Void)?

    var onOverscroll: ((Bool) -> Void)?

    // the loaders, or which document they hold, changed
    var onLoadersChanged: (() -> Void)?

    // a loader exists but holds nothing yet; its web view needs a place in the hierarchy before a
    // document is laid out into it
    var onLoaderCreated: ((EpubDocumentLoader) -> Void)?

    // spine paths the pass could not lay out; each is still counted as one page, so a book with one
    // in it can be finished
    private(set) var unmeasurable: [String] = []

    // held, not dropped: a dropped resume leaves the reader at page 1, which then overwrites the
    // progress being resumed to
    private(set) var pendingBookPage: Int?

    // the host asks, so the resume goes through the same serialised path its page turns use
    var canShowPendingBookPage: Bool {
        guard let pendingBookPage else { return false }
        return index.position(ofBookPage: pendingBookPage) != nil
    }

    /// The web views the reader should still be hosting. Anything else it holds has been given up.
    var hostedWebViews: Set<ObjectIdentifier> {
        Set((pool?.loaders ?? []).map { ObjectIdentifier($0.webView) })
    }

    /// Gives back everything but the document being read and the pair either side of it. The outer
    /// ones exist to save a load, which is not worth a jettisoned web process to buy.
    func releaseOuterDocuments() {
        guard let pool else { return }
        let keep = slottedLoaders.map { ObjectIdentifier($0.loader.webView) }
        pool.release(keeping: Set(keep))
        onLoadersChanged?()
        preloadTask?.cancel()
    }

    func hasNeighbour(offset: Int) -> Bool {
        slottedLoaders.contains { $0.slot == offset }
    }

    // paged only: in scroll style a document edge is a scroll position rather than a page
    var isAtDocumentStart: Bool {
        guard settings.paged, let renderer else { return false }
        return renderer.currentPage == 0
    }

    var isAtDocumentEnd: Bool {
        guard settings.paged, let renderer, renderer.pageCount > 0 else { return false }
        return renderer.currentPage >= renderer.pageCount - 1
    }

    /// Takes an already loaded neighbour as the document being read. Nothing loads and nothing
    /// moves: the drag has already carried it into place, and it is sitting on the right page.
    @discardableResult
    func adoptNeighbour(offset: Int) async -> Bool {
        let document = currentDocument + offset
        guard let loader = pool?.loader(holding: document), spinePaths.indices.contains(document) else {
            return false
        }
        if loader.document != document {
            // still mid-load, or lost to a terminated web process while the crossing animated:
            // waited out here, and given up on rather than adopted blank when it cannot finish
            guard (try? await loader.load(document: document, path: spinePaths[document])) != nil,
                  loader.document == document
            else { return false }
        }
        pendingBookPage = nil
        currentDocument = document
        currentLoader = loader
        onLoadersChanged?()
        onChange?()
        preloadNeighbours()
        return true
    }

    /// The live documents and where each sits relative to the one being read.
    var slottedLoaders: [(loader: EpubDocumentLoader, slot: Int)] {
        guard let pool else { return [] }
        return pool.loaders.compactMap { loader in
            // by the document actually painted, never one mid-load: until the incoming document
            // renders, the web view still shows whatever it held before, and a slotted view is a
            // drag away from being on screen
            guard let document = loader.document, abs(document - currentDocument) <= 1 else { return nil }
            return (loader, document - currentDocument)
        }
    }

    var pageInDocument: Int {
        renderer?.currentPage ?? 0
    }

    var bookPage: Int? {
        index.bookPage(forDocumentAt: currentDocument, page: pageInDocument)
    }

    // the anchor an in-session rebuild restores from
    var edgeInDocument: Double? {
        // swiftlint:disable:next empty_count
        guard let count = index.pageCount(forDocumentAt: currentDocument), count > 0 else { return nil }
        if !settings.paged, let precise = renderer?.scrollEdgeFraction {
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
        let anchor = settings.paged
            ? Double(settings.columnCount - 1) / Double(settings.columnCount)
            : 0
        return index.progression(forDocumentAt: currentDocument, page: pageInDocument, anchor: anchor)
    }

    // shared with the measurement pass; a count is only valid at the settings it was measured with
    private let settings: EpubPaginationSettings

    // the document being read and the neighbour on either side (previous, current, next).
    // keeping 3 loaders avoids WebKit process termination under memory pressure on iPad.
    private static let loaderCapacity = 3

    // measured in pages rather than documents: a chapter of one page costs one
    private static let preloadPageBudget = 1

    // only a host that installs the loaders' web views can hold neighbours: a renderer outside the
    // hierarchy has no size to lay a document out at, so off it there is one document at a time
    // a rebuild restores the reader's position before it is worth holding neighbours: a preload
    // ahead of that puts a web view load between the reader and the page they were on
    var deferPreloading = false {
        didSet {
            if !deferPreloading {
                preloadNeighbours()
            }
        }
    }

    var keepsNeighbours = false {
        didSet {
            pool?.capacity = keepsNeighbours ? Self.loaderCapacity : 1
            if keepsNeighbours {
                preloadNeighbours()
            }
        }
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

    func prepareRenderer() async throws -> EpubSpineRenderer {
        if let renderer { return renderer }
        let pool = pool ?? makePool()
        self.pool = pool
        guard let loader = try await pool.prepare() else {
            throw LoadError.unreadableBook(bookURL)
        }
        currentLoader = loader
        return loader.renderer
    }

    private func makePool() -> EpubLoaderPool {
        let capacity = keepsNeighbours ? Self.loaderCapacity : 1
        let pool = EpubLoaderPool(capacity: capacity) { [weak self, provider, settings] in
            let renderer = try await EpubSpineRenderer(provider: provider, settings: settings)
            self?.wire(renderer)
            return renderer
        }
        pool.onLoaderCreated = { [weak self] loader in self?.onLoaderCreated?(loader) }
        pool.onContentLost = { [weak self] document in self?.reload(document) }
        pool.isProtected = { [weak self] loader in loader === self?.currentLoader }
        pool.onRepaginate = { [weak self] document, count in
            guard let self else { return }
            index.setPageCount(count, forDocumentAt: document)
            onChange?()
        }
        return pool
    }

    private func wire(_ renderer: EpubSpineRenderer) {
        // only the document being read speaks for the reader: a neighbour being positioned scrolls
        // too, and reporting that moved the toolbar to a page nobody had turned to
        renderer.onScroll = { [weak self, weak renderer] in
            guard let self, currentLoader?.renderer === renderer else { return }
            onChange?()
        }
        renderer.onOverscroll = { [weak self, weak renderer] forward in
            guard let self, currentLoader?.renderer === renderer else { return }
            onOverscroll?(forward)
        }
        renderer.onLinkActivated = { [weak self] path, fragment in self?.onLink?(path, fragment) }
        renderer.onExternalLinkActivated = { [weak self] url in self?.onExternalLink?(url) }
    }

    func open(viewport: CGSize, atDocument document: Int = 0) async throws {
        self.viewport = viewport
        isOpen = true
        currentDocument = min(max(document, 0), max(spinePaths.count - 1, 0))
        try await loadCurrentDocument()
        startMeasuring()
    }

    func move(toPage page: Int, animated: Bool = false) async {
        pendingBookPage = nil
        guard let renderer else { return }
        await renderer.showPage(page, animated: animated)
        onChange?()
    }

    // the drag's own settle, carrying the speed the finger released at
    func slide(toPage page: Int, velocity: CGFloat) async {
        pendingBookPage = nil
        guard let renderer else { return }
        await renderer.slide(toPage: page, velocity: velocity)
        onChange?()
    }

    func moveForward(animated: Bool = false) async {
        pendingBookPage = nil
        guard let renderer else { return }
        if !settings.paged {
            if renderer.scrollByViewport(forward: true, animated: animated) {
                onChange?()
            } else {
                await move(toDocument: currentDocument + 1, landingOnLastPage: false, animated: animated)
            }
        } else if renderer.currentPage + 1 < renderer.pageCount {
            await renderer.showPage(renderer.currentPage + 1, animated: animated)
            onChange?()
        } else if spinePaths.indices.contains(currentDocument + 1) {
            await move(toDocument: currentDocument + 1, landingOnLastPage: false, animated: animated)
        } else {
            // the pan resists past the last page, and nothing else would undo that offset
            await renderer.showPage(renderer.currentPage, animated: animated)
        }
    }

    func moveBackward(animated: Bool = false) async {
        pendingBookPage = nil
        guard let renderer else { return }
        if !settings.paged {
            if renderer.scrollByViewport(forward: false, animated: animated) {
                onChange?()
            } else {
                await move(toDocument: currentDocument - 1, landingOnLastPage: true, animated: animated)
            }
        } else if renderer.currentPage > 0 {
            await renderer.showPage(renderer.currentPage - 1, animated: animated)
            onChange?()
        } else if spinePaths.indices.contains(currentDocument - 1) {
            await move(toDocument: currentDocument - 1, landingOnLastPage: true, animated: animated)
        } else {
            // the pan resists before the first page, and nothing else would undo that offset
            await renderer.showPage(renderer.currentPage, animated: animated)
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

    func imageData(at point: CGPoint) async -> Data? {
        guard
            let source = await renderer?.imageSource(at: point),
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
        for loader in pool?.loaders ?? [] {
            loader.renderer.setScrollPadding(clearance)
        }
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
    func currentEntry() async -> EpubTableOfContents.Entry? {
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

    private func show(document: Int, fragment: String?) async {
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
        guard spinePaths.indices.contains(document) else { return }
        let forward = document > currentDocument

        // the turn replaces the document, so a snapshot of the outgoing page covers the load
        var snapshot: UIView?
        if animated, let webView = renderer?.webView, webView.window != nil,
           let cover = webView.snapshotView(afterScreenUpdates: false) {
            cover.frame = webView.frame
            webView.superview?.addSubview(cover)
            snapshot = cover
        }

        measurer.pause()
        defer { measurer.resume() }

        // a load lands on page 0 and is only then scrolled, so turning back into a document would
        // visibly run through it; hidden across both steps unless page 0 is the target
        let target = landingOnLastPage ? Int.max : page
        let hides = (target != 0 || fragment != nil) && snapshot == nil
        // the views themselves, not `renderer`, which moves to the incoming loader when the
        // document loads: restoring alpha through it left the outgoing web view invisible for
        // good, and it came back around as a blank page in whatever slot it filled next
        let outgoing = hides ? renderer?.webView : nil
        outgoing?.alpha = 0
        defer { outgoing?.alpha = 1 }

        currentDocument = document
        var loaded = false
        do {
            let count = try await loadCurrentDocument()
            let incoming = hides ? renderer?.webView : nil
            if incoming !== outgoing {
                incoming?.alpha = 0
            }
            defer {
                if incoming !== outgoing {
                    incoming?.alpha = 1
                }
            }
            var landing = landingOnLastPage ? count - 1 : page
            if let fragment, let resolved = await renderer?.fragmentPages([fragment])[fragment] {
                landing = resolved
            }
            await renderer?.showPage(landing)
            loaded = true
        } catch {
            LogManager.logger.error("ReaderEpubViewModel: could not load \(spinePaths[document]): \(error)")
        }

        if let snapshot {
            if loaded, let webView = renderer?.webView {
                // along the axis the style reads in, or scroll style turns a chapter sideways
                let direction: CGFloat = forward ? 1 : -1
                let extent = (settings.paged ? webView.bounds.width : webView.bounds.height) * direction
                let entering = settings.paged
                    ? CGAffineTransform(translationX: extent, y: 0)
                    : CGAffineTransform(translationX: 0, y: extent)
                let leaving = settings.paged
                    ? CGAffineTransform(translationX: -extent, y: 0)
                    : CGAffineTransform(translationX: 0, y: -extent)
                webView.transform = entering
                await withCheckedContinuation { continuation in
                    UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                        webView.transform = .identity
                        snapshot.transform = leaving
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
        guard let pool, spinePaths.indices.contains(currentDocument) else { return 0 }
        let loader = try await pool.loader(for: currentDocument, path: spinePaths[currentDocument])
        currentLoader = loader
        index.setPageCount(loader.pageCount, forDocumentAt: currentDocument)
        onLoadersChanged?()
        onChange?()
        preloadNeighbours()
        return loader.pageCount
    }

    // a web view whose content process ended shows nothing until the document is put back into it.
    // the one being read cannot wait for a turn, the neighbours are refilled by the next preload
    private func reload(_ document: Int) {
        onLoadersChanged?()
        guard document == currentDocument else {
            preloadNeighbours()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await loadCurrentDocument()
            } catch {
                LogManager.logger.error(
                    "ReaderEpubViewModel: could not reload \(spinePaths[document]) after its process ended: \(error)"
                )
            }
        }
    }

    // a neighbour already laid out is a turn with nothing to load, which is the whole point of
    // holding three. it reports no count and no position: the pass has already measured the book,
    // and a second opinion on a count is the disagreement that put the book total out by one
    private func preloadNeighbours() {
        preloadTask?.cancel()
        // behind measurement, never beside it. the pass drives the toolbar and the progress the
        // reader is judged on, where a preload only saves a turn that has not happened yet. and
        // behind a restore, which is the page the reader is waiting to be given back
        guard keepsNeighbours, isMeasured, !deferPreloading else { return }
        let current = currentDocument
        let window = preloadWindow(around: current)
        let wanted = Set(window.map(\.document) + [current])
        preloadTask = Task { [weak self] in
            guard let self else { return }
            for (document, offset) in window {
                guard !Task.isCancelled, currentDocument == current, let pool else { continue }
                do {
                    // an already loaded one is still repositioned: adopting a neighbour turns the
                    // document just left into the neighbour on the other side
                    let loader = try await pool.loader(
                        for: document,
                        path: spinePaths[document],
                        keeping: wanted.subtracting([document])
                    )
                    // never the document being read: a load already in flight for it is shared
                    // rather than repeated, and positioning it would throw away the reader's page
                    guard !Task.isCancelled, currentDocument == current, loader !== currentLoader else { continue }
                    // the page a drag into it reveals: forward enters at the start, back at the end
                    await loader.renderer.showPage(offset > 0 ? 0 : max(loader.pageCount - 1, 0))
                    guard !Task.isCancelled, currentDocument == current else { return }
                    onLoadersChanged?()
                } catch {
                    LogManager.logger.warn(
                        "ReaderEpubViewModel: could not preload \(spinePaths[document]): \(error)"
                    )
                }
            }
        }
    }

    /// The documents worth holding either side, nearest first, taken outward while they are short
    /// enough to be worth the web view.
    private func preloadWindow(around document: Int) -> [(document: Int, offset: Int)] {
        let reach = Self.loaderCapacity / 2
        var window: [(document: Int, offset: Int)] = []
        for direction in [1, -1] {
            var pages = 0
            var offset = direction
            while abs(offset) <= reach {
                let candidate = document + offset
                guard spinePaths.indices.contains(candidate) else { break }
                window.append((candidate, offset))
                pages += index.pageCount(forDocumentAt: candidate) ?? 1
                guard pages < Self.preloadPageBudget else { break }
                offset += direction
            }
        }
        // the pair that can actually be turned into first, so a fast reader is never waiting on the
        // outer ones
        return window.sorted { abs($0.offset) < abs($1.offset) }
    }

    private func startMeasuring() {
        guard viewport.width > 0, viewport.height > 0 else { return }
        measurer.start(
            spinePaths: spinePaths,
            viewport: viewport,
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
                guard let self else { return }
                guard !outcome.cancelled else { return }
                if !outcome.failed.isEmpty {
                    LogManager.logger.error(
                        "ReaderEpubViewModel: \(outcome.failed.count) documents could not be laid out"
                    )
                }
                unmeasurable = outcome.failed
                onChange?()
                preloadNeighbours()
            }
        )
    }
}
