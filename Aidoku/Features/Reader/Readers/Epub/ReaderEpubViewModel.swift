//
//  ReaderEpubViewModel.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation
import UIKit

// a page turn at the end of a spine document continues into the next rather than ending the
// chapter. nothing here draws, which keeps the part that crosses spine boundaries testable
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
    private(set) var renderer: EpubSpineRenderer?

    private let provider: any EpubResourceProvider
    private let measurer: EpubSpineMeasurer
    private var viewport: CGSize = .zero

    // a host lays the web view out before opening the book, and measuring from there would start
    // a second pass over the same renderer while the first was still walking it
    private var isOpen = false

    var onChange: (() -> Void)?

    // reported rather than followed, since the host runs one navigation at a time
    var onLink: ((String, String?) -> Void)?

    // true past the end, false past the start
    var onOverscroll: ((Bool) -> Void)?

    private(set) var unmeasurable: [String] = []

    // a resume asks for a page whose document has not been counted yet, and dropping the request
    // leaves the reader at page 1, which then overwrites the progress being resumed to
    private(set) var pendingBookPage: Int?

    // exposed so the host asks through the same serialised path its page turns use, a resume
    // racing a turn being two navigations on one renderer
    var canShowPendingBookPage: Bool {
        guard let pendingBookPage else { return false }
        return index.position(ofBookPage: pendingBookPage) != nil
    }

    var firstUnmeasured: Int? {
        (0..<spinePaths.count).first { index.pageCount(forDocumentAt: $0) == nil }
    }

    var pageInDocument: Int {
        renderer?.currentPage ?? 0
    }

    var bookPage: Int? {
        index.bookPage(forDocumentAt: currentDocument, page: pageInDocument)
    }

    // the anchor an in-session rebuild restores from: the page boundary when paged, the exact top
    // of the viewport when scrolling
    var edgeInDocument: Double? {
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

    // withheld until the book is measured, since a fraction of a lower bound overstates how far
    // through it the reader is
    var progression: Double? {
        // where within the page the position sits, per EpubPageIndex.progression
        let anchor = settings.paged
            ? Double(settings.columnCount - 1) / Double(settings.columnCount)
            : 0
        return index.progression(forDocumentAt: currentDocument, page: pageInDocument, anchor: anchor)
    }

    // shared with the measurement pass, a count being meaningful only at the settings it was
    // measured with
    private let settings: EpubPaginationSettings

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

    // separate from open, so the size the book is measured at is the size the web view ends up at
    func prepareRenderer() async throws -> EpubSpineRenderer {
        if let renderer { return renderer }
        let renderer = try await EpubSpineRenderer(provider: provider, settings: settings)
        renderer.onScroll = { [weak self] in self?.onChange?() }
        renderer.onOverscroll = { [weak self] forward in self?.onOverscroll?(forward) }
        renderer.onLinkActivated = { [weak self] path, fragment in self?.onLink?(path, fragment) }
        renderer.onRepaginate = { [weak self] count in
            guard let self else { return }
            index.setPageCount(count, forDocumentAt: currentDocument)
            onChange?()
        }
        self.renderer = renderer
        return renderer
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
        if renderer.currentPage + 1 < renderer.pageCount {
            await renderer.showPage(renderer.currentPage + 1, animated: animated)
            onChange?()
        } else {
            await move(toDocument: currentDocument + 1, landingOnLastPage: false, animated: animated)
        }
    }

    func moveBackward(animated: Bool = false) async {
        pendingBookPage = nil
        guard let renderer else { return }
        if renderer.currentPage > 0 {
            await renderer.showPage(renderer.currentPage - 1, animated: animated)
            onChange?()
        } else {
            await move(toDocument: currentDocument - 1, landingOnLastPage: true, animated: animated)
        }
    }

    // recorded before the book is open, so the first counts to land do not read as the reader
    // sitting at its head, which saved page 1 over the progress being resumed to
    func holdBookPage(_ page: Int) {
        pendingBookPage = page
    }

    // a page beyond the run of documents counted so far is held rather than guessed at
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

    // through the provider rather than the web view, so the preview is at full resolution
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

    // every count belongs to a viewport, so all are dropped and counted again
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

    // a path outside the spine is logged rather than navigated to, there being no page in the
    // book that corresponds to it
    func showLocation(path: String, fragment: String?) async {
        guard let document = spinePaths.firstIndex(of: path) else {
            LogManager.logger.warn("ReaderEpubViewModel: link to \(path) is not in the spine")
            return
        }
        pendingBookPage = nil
        await show(document: document, fragment: fragment)
    }

    // asked of the loaded document, since a book converted from a single file shares one spine
    // index across every entry and only the layout tells them apart
    func currentEntry() async -> EpubTableOfContents.Entry? {
        let fragments = toc.entries(inDocument: currentDocument).compactMap(\.fragment)
        guard !fragments.isEmpty, let renderer else {
            return toc.entry(inDocument: currentDocument)
        }
        let pages = await renderer.fragmentPages(fragments)
        return toc.entry(inDocument: currentDocument, atOrBefore: pageInDocument, fragmentPages: pages)
    }

    // the entry's document, not the element inside it, which would cost a load and a layout each
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

        // the turn replaces the document inside the web view, so a snapshot of the outgoing page
        // stands in and covers the load
        var snapshot: UIView?
        if animated, let webView = renderer?.webView, webView.window != nil,
           let cover = webView.snapshotView(afterScreenUpdates: false) {
            cover.frame = webView.frame
            webView.superview?.addSubview(cover)
            snapshot = cover
        }

        // provider reads serialise onto one file handle, so this contends with the pass
        measurer.pause()
        defer { measurer.resume() }

        // a document shows its first page as it loads and is only then scrolled to the one asked
        // for, so turning back into one would visibly run through it. hidden across both steps,
        // except when landing on page 0, where a load already leaves it
        let target = landingOnLastPage ? Int.max : page
        let hides = (target != 0 || fragment != nil) && snapshot == nil
        if hides {
            renderer?.webView.alpha = 0
        }
        defer {
            if hides {
                renderer?.webView.alpha = 1
            }
        }

        currentDocument = document
        var loaded = false
        do {
            let count = try await loadCurrentDocument()
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
                let width = webView.bounds.width
                let direction: CGFloat = forward ? 1 : -1
                webView.transform = CGAffineTransform(translationX: direction * width, y: 0)
                await withCheckedContinuation { continuation in
                    UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                        webView.transform = .identity
                        snapshot.transform = CGAffineTransform(translationX: -direction * width, y: 0)
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
                // counted as one page rather than left unknown: EpubPageIndex answers nothing
                // about a position after an unmeasured document, so the toolbar froze for the rest
                // of the book and isMeasured stayed false, which gates marking the chapter read
                index.setPageCount(1, forDocumentAt: document)
                onChange?()
            },
            onFinish: { [weak self] outcome in
                guard let self else { return }
                // a superseded pass reports only what it had failed on so far
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
