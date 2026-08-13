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

    /// Called whenever the position or the book's total moves, so a host can refresh its toolbar.
    var onChange: (() -> Void)?

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

    init(bookURL: URL) throws {
        guard let book = EpubParser.parse(url: bookURL) else {
            throw LoadError.unreadableBook(bookURL)
        }
        self.bookURL = bookURL
        self.spinePaths = book.chapters.flatMap(\.hrefs)
        self.index = EpubPageIndex(spinePaths: spinePaths)
        self.provider = try EpubZipResourceProvider(url: bookURL)
        self.measurer = EpubSpineMeasurer(provider: provider)
    }

    /// Builds the renderer, shows the opening document, and starts counting the rest of the book.
    ///
    /// The renderer is given a frame and laid out here rather than left to the host, so that the
    /// opening document is laid out against the size it will be read at. A view still at its
    /// default zero size reports a viewport that means nothing, and window membership is not what
    /// decides this: a frame and a layout are.
    func start(viewport: CGSize, atDocument document: Int = 0) async throws {
        self.viewport = viewport
        let renderer = try await EpubSpineRenderer(provider: provider)
        renderer.webView.frame = CGRect(origin: .zero, size: viewport)
        renderer.webView.layoutIfNeeded()
        renderer.onRepaginate = { [weak self] count in
            guard let self else { return }
            // The renderer re-measures when a late image or a size change moves the boundaries, so
            // this is the current document's count becoming more accurate rather than a new one.
            index.setPageCount(count, forDocumentAt: currentDocument)
            onChange?()
        }
        self.renderer = renderer

        currentDocument = min(max(document, 0), max(spinePaths.count - 1, 0))
        try await loadCurrentDocument()
        startMeasuring()
    }

    /// Forward a page, continuing into the next spine document at its end.
    func moveForward() async {
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
    /// Does nothing while the page cannot be placed, which is any page beyond the run of documents
    /// counted so far. A slider offering pages the index cannot resolve is the host's problem to
    /// avoid, and guessing here would move the reader somewhere arbitrary.
    func showBookPage(_ page: Int) async {
        guard let position = index.position(ofBookPage: page) else { return }
        if position.document == currentDocument {
            await renderer?.showPage(position.page)
            onChange?()
        } else {
            await move(toDocument: position.document, landingOnLastPage: false, page: position.page)
        }
    }

    /// Re-lays the book out at a new size.
    ///
    /// Every count belongs to a viewport, so all of them are dropped and counted again. The
    /// renderer restores its own page by progression within the current document, which is what
    /// keeps the reader on the same text rather than on the same page number.
    func viewportChanged(to size: CGSize) {
        guard size != viewport, size.width > 0, size.height > 0 else { return }
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
            onFinish: { [weak self] _ in
                self?.onChange?()
            }
        )
    }
}
