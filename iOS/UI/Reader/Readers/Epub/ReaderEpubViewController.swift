//
//  ReaderEpubViewController.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/13/26.
//

import AidokuRunner
import UIKit

/// Hosts an ePub, reading a whole book across its spine.
///
/// One ePub is one chapter, so this reader spans a book rather than a document: page turns continue
/// across spine boundaries and the toolbar describes the book. `ReaderEpubViewModel` owns that
/// state and the navigation; this owns the view, the chrome and the conversation with
/// `ReaderHoldingDelegate`.
///
/// It does not use `UIPageViewController`, unlike the paged image reader. One web view carries a
/// whole spine document and its pages are scroll offsets within it, so there is no per-page view
/// controller to give a data source. `ReaderWebtoonViewController` is the sibling precedent for a
/// reader shaped this way, and its `moveLeft`/`moveRight` are likewise plain moves rather than
/// page-view-controller transitions. A web view per page inside a `UIPageViewController`, which is
/// what would restore transition parity with the paged reader, is recorded as the end goal in
/// `SLICE-3-SPEC.md`.
class ReaderEpubViewController: BaseObservingViewController {
    weak var delegate: ReaderHoldingDelegate?

    /// ePub text reads left to right regardless of the manga setting, as the text reader does.
    ///
    /// A right-to-left publication is a readium-css concern rather than a gesture one, and is out
    /// of scope for v1.
    var readingMode: ReadingMode = .ltr

    var chapter: AidokuRunner.Chapter?

    private let source: AidokuRunner.Source?
    private let manga: AidokuRunner.Manga

    /// The `.epub` every spine document of this chapter lives inside.
    ///
    /// Resolved by the host from the pages it has already loaded rather than loaded again here. A
    /// reader that fetched the chapter's pages a second time only to read one archive URL out of
    /// them would repeat the whole download or zip read for a value the host already holds.
    private let bookURL: URL

    private(set) var book: ReaderEpubViewModel?
    private var openTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?

    /// The size the book was last laid out at, so a layout pass that changes nothing does not
    /// invalidate every page count.
    private var lastViewport: CGSize = .zero

    /// True while the slider is being dragged, so the total firming up does not move the thumb
    /// under the finger.
    private var isSliding = false

    /// The total last handed to the toolbar, so it is rewritten when it changes rather than on
    /// every count that lands.
    private var reportedTotal = 0

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga, bookURL: URL) {
        self.source = source
        self.manga = manga
        self.bookURL = bookURL
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        openTask?.cancel()
        moveTask?.cancel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size != lastViewport, size.width > 0, size.height > 0 else { return }
        lastViewport = size
        book?.viewportChanged(to: size)
    }

    /// Adds the web view once the book exists, pinned to the view's own edges rather than to its
    /// safe area.
    ///
    /// The chrome overlays the reader and must never resize it. A column is `100vh` by `100vw`, so
    /// any change to the web view's height re-fragments the document and moves every page
    /// boundary: hiding the bars against a safe-area-pinned web view would repaginate the book on
    /// every tap. The renderer already sets `contentInsetAdjustmentBehavior = .never` for the same
    /// reason, and `EpubPaginationSettings.pageGutterPx` is what keeps text off the edges.
    private func install(_ webView: UIView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// Opens the book and shows the page the reader left off at.
    private func open(startPage: Int) async {
        let book: ReaderEpubViewModel
        do {
            book = try ReaderEpubViewModel(bookURL: bookURL)
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not open \(bookURL.lastPathComponent): \(error)")
            delegate?.setPages([])
            return
        }
        book.onChange = { [weak self] in self?.report() }
        self.book = book

        let viewport = view.bounds.size
        lastViewport = viewport
        do {
            try await book.start(viewport: viewport)
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not lay out \(bookURL.lastPathComponent): \(error)")
            delegate?.setPages([])
            return
        }
        guard !Task.isCancelled, let renderer = book.renderer else { return }
        install(renderer.webView)

        if startPage > 1 {
            await book.showBookPage(startPage - 1)
        }
        report()
    }

    /// Tells the toolbar where the reader is and how long the book is.
    ///
    /// The total grows as the measurement pass fills it in, so it is rewritten when it changes
    /// rather than on every count, and never while the slider is being dragged: `setPages` moves
    /// the thumb, and moving it under a finger is worse than a total that lands a moment late.
    private func report() {
        guard let book else { return }

        let total = book.bookTotal
        if total != reportedTotal && !isSliding {
            reportedTotal = total
            delegate?.setPages(placeholderPages(count: total))
        }

        // A page the index cannot place yet is one in a document whose predecessors are still being
        // counted. Reporting a position then would put the reader somewhere arbitrary in the book.
        guard let page = book.bookPage else { return }
        delegate?.setCurrentPage(page + 1, position: book.progression)
    }

    /// The toolbar takes its total from the number of pages it holds, so a book's length reaches it
    /// as pages.
    ///
    /// The paged text reader does the same once it has paginated, for the same reason: a reflowable
    /// document's page count is not known until it has been laid out, so the reader supplies it
    /// rather than the source.
    private func placeholderPages(count: Int) -> [Page] {
        guard count > 0 else { return [] }
        let sourceId = source?.key ?? manga.sourceKey
        let chapterId = chapter?.key ?? ""
        return (0..<count).map { index in
            Page(sourceId: sourceId, chapterId: chapterId, index: index)
        }
    }

    /// Runs one navigation at a time. A turn arriving while another is in flight is dropped rather
    /// than queued, since the renderer's own page turns already supersede one another and queuing
    /// here would replay a burst of taps after the fact.
    private func navigate(_ work: @escaping (ReaderEpubViewModel) async -> Void) {
        guard let book, moveTask == nil else { return }
        moveTask = Task { [weak self] in
            await work(book)
            self?.moveTask = nil
        }
    }
}

// MARK: - ReaderReaderDelegate

extension ReaderEpubViewController: ReaderReaderDelegate {
    func moveLeft() {
        navigate { await $0.moveBackward() }
    }

    func moveRight() {
        navigate { await $0.moveForward() }
    }

    /// Previews a page while the thumb is moving, without loading anything.
    ///
    /// Dragging across a book of several thousand pages crosses many spine documents, and loading
    /// each one it passes over would make the slider unusable. The book moves once the thumb stops.
    func sliderMoved(value: CGFloat) {
        isSliding = true
        guard reportedTotal > 0 else { return }
        delegate?.displayPage(bookPage(for: value) + 1)
    }

    func sliderStopped(value: CGFloat) {
        isSliding = false
        let page = bookPage(for: value)
        navigate { await $0.showBookPage(page) }
    }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {
        guard self.chapter?.id != chapter.id else { return }
        self.chapter = chapter
        openTask?.cancel()
        openTask = Task { [weak self] in
            await self?.open(startPage: startPage)
        }
    }

    /// The book page a slider position stands for, zero-based.
    ///
    /// `value` is a fraction of the whole book, matching the `index / (count - 1)` convention the
    /// toolbar and both text readers already use.
    private func bookPage(for value: CGFloat) -> Int {
        let last = max(reportedTotal - 1, 0)
        return min(max(Int((value * CGFloat(last)).rounded()), 0), last)
    }
}
