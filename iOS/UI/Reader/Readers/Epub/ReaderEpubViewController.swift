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

    /// The one turn held while another is in flight. See `navigate`.
    private var pendingMove: ((ReaderEpubViewModel) async -> Void)?

    /// The size the book was last laid out at, so a layout pass that changes nothing does not
    /// invalidate every page count.
    private var lastViewport: CGSize = .zero

    /// The web view's inset constraints, held so their constants can be updated as the device's
    /// safe area changes without rebuilding them.
    private struct WebViewInsets {
        let top: NSLayoutConstraint
        let bottom: NSLayoutConstraint
        let leading: NSLayoutConstraint
        let trailing: NSLayoutConstraint

        var constants: UIEdgeInsets {
            UIEdgeInsets(top: top.constant, left: leading.constant,
                         bottom: bottom.constant, right: trailing.constant)
        }

        func apply(_ insets: UIEdgeInsets) {
            top.constant = insets.top
            bottom.constant = insets.bottom
            leading.constant = insets.left
            trailing.constant = insets.right
        }
    }

    private var webViewInsets: WebViewInsets?

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
        applySafeArea()
        let size = webViewSize()
        guard size != lastViewport, size.width > 0, size.height > 0 else { return }
        lastViewport = size
        book?.viewportChanged(to: size)
    }

    /// Adds the web view, inset from the device's safe area.
    ///
    /// Nothing about the safe area is expressed in CSS. readium-css is followed as it is, and its
    /// own `--RS__pageGutter` continues to be the only padding inside the document. An earlier
    /// attempt injected `env(safe-area-inset-*)` rules, which worked in the sense that they applied
    /// to every page, and broke pagination: a web view's safe area depends on where it sits in its
    /// window, so resizing it changes `env()`, which re-fragments the document on a different tick
    /// from the one the renderer waits for. The count then described a layout that had already been
    /// replaced. Insetting the view instead leaves the document with exactly one thing that decides
    /// its layout, its own size, which is the input the renderer already handles.
    private func install(_ webView: UIView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        let insets = WebViewInsets(
            top: webView.topAnchor.constraint(equalTo: view.topAnchor),
            bottom: view.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            leading: webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trailing: view.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        )
        NSLayoutConstraint.activate([insets.top, insets.bottom, insets.leading, insets.trailing])
        webViewInsets = insets
        applySafeArea()
    }

    /// Insets the web view by the **window's** safe area rather than the view's.
    ///
    /// The window's insets are the physical notch and home indicator and do not change when the
    /// bars are shown or hidden; the view's include the bars and do. A column is `100vh` by
    /// `100vw`, so a web view that resized on every tap that toggled the chrome would re-fragment
    /// the document and move every page boundary. This is the same distinction, and the same
    /// reason, as `ReaderPagedTextViewController`'s use of `view.window?.safeAreaInsets`.
    ///
    /// A rotation does change these, and also changes the view's size, so the renderer re-measures
    /// once for both rather than twice.
    private func applySafeArea() {
        guard let webViewInsets else { return }
        let safeArea = view.window?.safeAreaInsets ?? view.safeAreaInsets
        guard webViewInsets.constants != safeArea else { return }
        webViewInsets.apply(safeArea)
        view.layoutIfNeeded()
    }

    /// The size the document is laid out at, which is the web view's rather than the reader's.
    private func webViewSize() -> CGSize {
        book?.renderer?.webView.bounds.size ?? .zero
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

        // Laid out at the size the web view will occupy once inset, rather than at the reader's
        // full bounds, so the opening document is not paginated twice.
        let safeArea = view.window?.safeAreaInsets ?? view.safeAreaInsets
        let viewport = CGSize(
            width: max(view.bounds.width - safeArea.left - safeArea.right, 0),
            height: max(view.bounds.height - safeArea.top - safeArea.bottom, 0)
        )
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

    /// Runs one navigation at a time, holding at most one more behind it.
    ///
    /// A turn crossing into another spine document has to load one, which takes long enough for a
    /// second tap to arrive during it. Dropping that tap outright makes quick paging feel broken;
    /// queuing every tap makes a burst of ten replay as ten turns after the fact. One slot gives
    /// the responsiveness without the replay, and a third tap replaces the one waiting rather than
    /// joining it.
    private func navigate(_ work: @escaping (ReaderEpubViewModel) async -> Void) {
        guard book != nil else { return }
        guard moveTask == nil else {
            pendingMove = work
            return
        }
        moveTask = Task { [weak self] in
            guard let self, let book else { return }
            await work(book)
            moveTask = nil
            if let next = pendingMove {
                pendingMove = nil
                navigate(next)
            }
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
