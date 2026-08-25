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
    private(set) var renderer: EpubSpineRenderer?

    private let provider: any EpubResourceProvider
    private let measurer: EpubSpineMeasurer
    private var viewport: CGSize = .zero

    // measuring before open would start a second pass over the same renderer
    private var isOpen = false

    var onChange: (() -> Void)?

    var onLink: ((String, String?) -> Void)?

    var onOverscroll: ((Bool) -> Void)?

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

    var pageInDocument: Int {
        renderer?.currentPage ?? 0
    }

    var bookPage: Int? {
        index.bookPage(forDocumentAt: currentDocument, page: pageInDocument)
    }

    // the anchor an in-session rebuild restores from
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
            }
        )
    }
}
