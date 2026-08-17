//
//  ReaderEpubViewModel.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation
import UIKit

/// Reading state for one ePub: which spine document is loaded, which of its pages is shown, and
/// where that sits in the book.
///
/// One ePub is one chapter, so a page turn at the end of a spine document continues into the next
/// one rather than ending the chapter, and the toolbar describes the book rather than the document.
/// Everything here is arithmetic and navigation and none of it draws, which keeps the part that
/// crosses spine boundaries testable without a view controller.
@MainActor
final class ReaderEpubViewModel {
    enum LoadError: Error {
        /// The file could not be parsed as an ePub, so it has no spine to read.
        case unreadableBook(URL)
    }

    let bookURL: URL

    /// Spine document paths in reading order, as `chapters.flatMap(\.hrefs)` yields them.
    ///
    /// Chapter grouping decides only where a chapter starts, so it cannot drop a document; the
    /// OPF spine and `EpubParser` were reconciled across the corpus and agree.
    let spinePaths: [String]

    private(set) var index: EpubPageIndex
    private(set) var currentDocument = 0
    private(set) var renderer: EpubSpineRenderer?

    private let provider: any EpubResourceProvider
    private let measurer: EpubSpineMeasurer
    private var viewport: CGSize = .zero

    /// True once `open` has laid the book out, so that a layout pass arriving before it does not
    /// start a measurement pass of its own.
    ///
    /// A host places the web view and lays it out before opening the book, which is a size change
    /// and reaches `viewportChanged`. Measuring from there would count the whole spine once against
    /// a book that has not been opened, and `open` would then start a second pass over the same
    /// renderer while the first was still walking it.
    private var isOpen = false

    /// Called whenever the position or the book's total moves, so a host can refresh its toolbar.
    var onChange: (() -> Void)?

    /// Called when a scroll-mode pull runs past the end (`true`) or start (`false`) of the
    /// current document. The host routes it through the same queue as its page turns, since it is
    /// one: a move into the neighbouring spine document.
    var onOverscroll: ((Bool) -> Void)?

    /// Spine paths the measurement pass could not lay out, for the debug screen to show.
    private(set) var unmeasurable: [String] = []

    /// A book page asked for before the index could place it, held rather than dropped.
    ///
    /// A reader resuming partway through a book asks for a page whose document has not been
    /// counted yet, since only the opening document is measured by the time the book is open.
    /// Dropping the request leaves the reader at page 1, and the position they were resuming to is
    /// then overwritten with 1 when the reader closes, so the request has to outlive the counts it
    /// is waiting on.
    private(set) var pendingBookPage: Int?

    /// True once the page held above can be placed.
    ///
    /// Exposed rather than acted on here so the host asks for it through the same serialised path
    /// its own page turns use. A resume racing a page turn is two navigations at once on one
    /// renderer, which is the shape of defect this reader has already paid for once.
    var canShowPendingBookPage: Bool {
        guard let pendingBookPage else { return false }
        return index.position(ofBookPage: pendingBookPage) != nil
    }

    /// The first spine document with no count, or `nil` once the book is complete. Debug only.
    var firstUnmeasured: Int? {
        (0..<spinePaths.count).first { index.pageCount(forDocumentAt: $0) == nil }
    }

    /// The page shown within the current spine document, zero-based.
    var pageInDocument: Int {
        renderer?.currentPage ?? 0
    }

    /// Which page of the book is shown, zero-based, or `nil` while the documents before this one
    /// are still being counted.
    var bookPage: Int? {
        index.bookPage(forDocumentAt: currentDocument, page: pageInDocument)
    }

    /// The book's page count, which is a lower bound until `isMeasured`.
    var bookTotal: Int {
        index.total
    }

    /// True once every spine document has been counted, and therefore once `bookTotal` is final.
    var isMeasured: Bool {
        index.isComplete
    }

    /// The fraction of the book that is read, for `setCurrentPage(_:position:)` to persist.
    ///
    /// Withheld until the book is measured, since a fraction of a lower bound overstates how far
    /// through the book the reader is. `EpubSpineRenderer.progression` is the fraction within one
    /// spine document and is not this.
    var progression: Double? {
        index.progression(forDocumentAt: currentDocument, page: pageInDocument)
    }

    /// Pagination settings for the reading renderer and the measurement pass alike: a count is
    /// only meaningful when it was measured with the settings the document is shown with.
    private let settings: EpubPaginationSettings

    init(bookURL: URL, settings: EpubPaginationSettings = .default) throws {
        guard let book = EpubParser.parse(url: bookURL) else {
            throw LoadError.unreadableBook(bookURL)
        }
        self.bookURL = bookURL
        self.settings = settings
        self.spinePaths = book.chapters.flatMap(\.hrefs)
        self.index = EpubPageIndex(spinePaths: spinePaths)
        self.provider = try EpubZipResourceProvider(url: bookURL)
        self.measurer = EpubSpineMeasurer(provider: provider, settings: settings)
    }

    /// Builds the renderer so its web view can be placed before anything is laid out in it.
    ///
    /// Separate from `open` because the size the book is measured at has to be the size the web
    /// view actually ends up, not a prediction of it. Laying the opening document out against a
    /// computed size and then letting the host place the view invites a disagreement of a point or
    /// two, and any disagreement invalidates every page count and restarts the measurement pass.
    func prepareRenderer() async throws -> EpubSpineRenderer {
        if let renderer { return renderer }
        let renderer = try await EpubSpineRenderer(provider: provider, settings: settings)
        renderer.onScroll = { [weak self] in self?.onChange?() }
        renderer.onOverscroll = { [weak self] forward in self?.onOverscroll?(forward) }
        renderer.onRepaginate = { [weak self] count in
            guard let self else { return }
            // The renderer re-measures when a late image or a size change moves the boundaries, so
            // this is the current document's count becoming more accurate rather than a new one.
            index.setPageCount(count, forDocumentAt: currentDocument)
            onChange?()
        }
        self.renderer = renderer
        return renderer
    }

    /// Shows the opening document and starts counting the rest of the book.
    ///
    /// `viewport` must be the web view's settled size. Call after the host has placed it.
    func open(viewport: CGSize, atDocument document: Int = 0) async throws {
        self.viewport = viewport
        isOpen = true
        currentDocument = min(max(document, 0), max(spinePaths.count - 1, 0))
        try await loadCurrentDocument()
        startMeasuring()
    }

    /// Forward a page, continuing into the next spine document at its end.
    func moveForward() async {
        // A reader who turns a page has taken over from whatever they were being resumed to, and
        // arriving at it later would move them off the page they chose.
        pendingBookPage = nil
        guard let renderer else { return }
        if renderer.currentPage + 1 < renderer.pageCount {
            await renderer.showPage(renderer.currentPage + 1)
            onChange?()
        } else {
            await move(toDocument: currentDocument + 1, landingOnLastPage: false)
        }
    }

    /// Back a page, continuing into the previous spine document at its **last** page.
    func moveBackward() async {
        pendingBookPage = nil
        guard let renderer else { return }
        if renderer.currentPage > 0 {
            await renderer.showPage(renderer.currentPage - 1)
            onChange?()
        } else {
            await move(toDocument: currentDocument - 1, landingOnLastPage: true)
        }
    }

    /// Shows a page of the book, which is what a dragged slider asks for.
    ///
    /// A page that cannot be placed, which is any page beyond the run of documents counted so far,
    /// is held until it can be rather than guessed at: guessing would move the reader somewhere
    /// arbitrary. `canShowPendingBookPage` tells a host when to ask again.
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

    /// Shows the page that was held, once the index can place it.
    func showPendingBookPage() async {
        guard let page = pendingBookPage else { return }
        await showBookPage(page)
    }

    /// Re-lays the book out at a new size.
    ///
    /// Every count belongs to a viewport, so all of them are dropped and counted again. The
    /// renderer restores its own page by progression within the current document, which is what
    /// keeps the reader on the same text rather than on the same page number.
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

    /// Loads a spine document and shows a page of it.
    ///
    /// `load` returns the document's count, so the last page is known by the time there is a
    /// document to show it in. A count already held for this document does not shorten the path:
    /// nothing can be shown before the document is loaded either way.
    private func move(toDocument document: Int, landingOnLastPage: Bool, page: Int = 0) async {
        guard spinePaths.indices.contains(document) else { return }

        // Provider reads serialise onto one file handle, so a load that crosses into another spine
        // document contends with the pass. A reader waiting on a background count is a visible
        // stall; a count waiting on a reader is not.
        measurer.pause()
        defer { measurer.resume() }

        // A document is shown at its first page the moment it loads, and only then scrolled to the
        // page that was asked for. Turning back into a document therefore renders its opening, then
        // visibly runs through it to the end. The web view is hidden across the two steps so the
        // reader sees the page it asked for and nothing else.
        //
        // Landing on page 0 needs none of this, since that is where a load already leaves the
        // document, and hiding it there would flicker for no reason.
        let target = landingOnLastPage ? Int.max : page
        let hides = target != 0
        if hides {
            renderer?.webView.alpha = 0
        }
        defer {
            if hides {
                renderer?.webView.alpha = 1
            }
        }

        currentDocument = document
        do {
            let count = try await loadCurrentDocument()
            await renderer?.showPage(landingOnLastPage ? count - 1 : page)
        } catch {
            LogManager.logger.error("ReaderEpubViewModel: could not load \(spinePaths[document]): \(error)")
        }
        onChange?()
    }

    @discardableResult
    private func loadCurrentDocument() async throws -> Int {
        guard let renderer, spinePaths.indices.contains(currentDocument) else { return 0 }
        let count = try await renderer.load(spinePath: spinePaths[currentDocument])
        // The reading renderer has measured this document for free, so the pass need not.
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
            onFinish: { [weak self] outcome in
                guard let self else { return }
                // A pass that was superseded reports what it had failed on so far, which is a
                // partial answer to a question the pass that replaced it is about to answer in
                // full. Only a pass that reached the end of the spine describes the book.
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
