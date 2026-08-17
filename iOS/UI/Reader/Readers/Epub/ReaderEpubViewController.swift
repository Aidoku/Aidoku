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

    /// True while a navigation is in flight, so the states it passes through are not published as
    /// positions.
    ///
    /// A move that crosses into another spine document reports twice on its way: once when the
    /// document loads, which is a real count but a position of its first page, and once when the
    /// page asked for is shown. A reader dragging the slider across a document boundary therefore
    /// saw the thumb land near their target, jump to the head of that document, and only then
    /// settle, while a drag within the loaded document moved once and looked correct.
    private var isNavigating = false

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
        settingsReloadTask?.cancel()
    }

    /// The debounced rebuild a settings change schedules; see `scheduleSettingsReload`.
    private var settingsReloadTask: Task<Void, Never>?

    override func observe() {
        // The text readers' settings apply to epubs too. They are baked into the renderer's
        // injection script and into every measured page count, so a change invalidates all of it;
        // rebuilding through `open` reuses the path a fresh open already exercises. Debounced
        // because the steppers in the settings sheet post once per tick.
        for key in [
            "Reader.textReaderStyle", "Reader.textFontFamily", "Reader.textFontSize",
            "Reader.textLineSpacing", "Reader.textHorizontalPadding"
        ] {
            addObserver(forName: key) { [weak self] _ in
                self?.scheduleSettingsReload()
            }
        }
    }

    /// The reader's place, captured before the first rebuild of a run and held until the reader
    /// navigates somewhere themselves.
    ///
    /// Held across the whole run rather than per rebuild: a second settings change arrives while
    /// the rebuild for the first is still opening the book, and a mid-open book reports the start
    /// of the book rather than the place the reader was. Clearing this after one rebuild let the
    /// second capture that start, which put a reader who tapped a stepper twice back on page one.
    /// Only a navigation the reader performs makes the captured place stale, so only `navigate`
    /// and a chapter change clear it.
    ///
    /// The page number is the immediate landing, since it is the only anchor available before the
    /// new layout has been counted. It is not where the reader belongs: a page number means a
    /// different place in a layout of a different length, and the error grows with depth. Changing
    /// 18pt to 20pt took a 456 page book to 520, which puts page 27 about four pages of text early
    /// and page 400 about fifty-six.
    private var settingsReloadPage: Int?

    /// Where the reader belongs, as a fraction of the whole book, refined onto a page once the new
    /// layout has been measured.
    ///
    /// The same anchor a rotation uses, and for the same reason: re-fragmenting moves text between
    /// pages, so a fraction survives it and an index does not. Only captured from a book that has
    /// been measured, since an unmeasured total is a lower bound and would place the fraction too
    /// far in; the page number carries those alone.
    private var settingsReloadPosition: Double?

    private func scheduleSettingsReload() {
        if settingsReloadPage == nil {
            settingsReloadPage = (book?.bookPage).map { $0 + 1 }
            settingsReloadPosition = book.flatMap { book in
                guard book.isMeasured, book.bookTotal > 1, let page = book.bookPage else { return nil }
                return Double(page) / Double(book.bookTotal - 1)
            }
        }
        settingsReloadTask?.cancel()
        settingsReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            rebuildBook()
        }
    }

    /// Tears the book down and opens it again at the same place, picking up the current settings.
    private func rebuildBook() {
        guard book != nil else { return }
        // The page numbers of the old layout are the best available guess at a place in the
        // new one; `open` holds it as a pending page until the new counts can place it.
        let page = settingsReloadPage ?? (book?.bookPage).map { $0 + 1 } ?? 1
        openTask?.cancel()
        moveTask?.cancel()
        moveTask = nil
        pendingMove = nil
        isNavigating = false
        isSliding = false
        reportedTotal = 0
        lastViewport = .zero
        insetsAppliedForSize = .zero
        book?.renderer?.webView.removeFromSuperview()
        webViewInsets = nil
        book = nil
        openTask = Task { [weak self] in
            await self?.open(startPage: page)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Opaque, so the host's `Reader.backgroundColor` — a manga/webtoon setting it applies to
        // its own background whenever the bars hide — never shows in the safe-area and chrome
        // strips around the web view. `.systemBackground` is white/black by appearance, which is
        // exactly what the injected `light-dark()` gives the page itself.
        view.backgroundColor = .systemBackground

        // The default tap zone setting is "disabled" and the web view's own scrolling is off, so
        // without these there is no touch gesture at all that turns a page. Every other reader
        // pages by swipe; this one does the same, on top of whatever tap zones are enabled.
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            // A WKWebView's internal recognizers claim touches before an ancestor's recognizer
            // sees them; recognising simultaneously is what lets the swipe through.
            swipe.delegate = self
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        // ePub text reads left to right, so swiping the content left goes forward.
        switch gesture.direction {
            case .left: moveRight()
            case .right: moveLeft()
            default: break
        }
    }

    /// The column count the open book was laid out with, so a rotation that changes it rebuilds
    /// the book. The count is baked into the renderer's injection script, so a re-measure alone
    /// cannot change it.
    private var appliedColumnCount = 1

    /// The horizontal margin the view supplies because the stylesheet does not.
    ///
    /// readium-css scopes its page gutter to a paged document — `:root:not([style*="readium-scroll-on"])
    /// body { padding: 0 var(--RS__pageGutter) }` — so a scrolling document has no horizontal padding
    /// at all and its text runs to both edges of the screen. Answered by insetting the view, not by
    /// adding a rule to the injection: a scrolling document's length is measured in viewport heights,
    /// and the view's own size is the one input the renderer already re-measures against.
    private var appliedHorizontalGutter: CGFloat = 0

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySafeArea()
        let size = webViewSize()
        guard size != lastViewport, size.width > 0, size.height > 0 else { return }
        lastViewport = size
        if book != nil, EpubPaginationSettings.columnCount(for: view.bounds.size) != appliedColumnCount {
            // An iPad rotating between one column (portrait) and two (landscape). Debounced with
            // the settings path so the rebuild sees the size the rotation settles at.
            scheduleSettingsReload()
        } else {
            book?.viewportChanged(to: size)
        }
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
    /// Fixed space reserved above and below the document for the translucent nav bar and toolbar,
    /// as `ReaderPagedTextViewController`'s `toolbarBuffer` reserves. The bars overlay the reader,
    /// so without it the first and last lines of every page sit behind them whenever they are
    /// shown; a constant reservation keeps the text clear of them without the viewport changing
    /// when they are toggled, which is what would re-fragment the document.
    private static let chromeBuffer: CGFloat = 50

    /// The view size the insets were last read for, so they are re-read only when it changes.
    ///
    /// On an iPhone the window's insets are the notch and stay put when the bars toggle, but an
    /// iPad has no notch: its top window inset is the status bar, which hides with the bars. Read
    /// on every layout pass, that resized the web view on every toggle, and every resize
    /// re-fragments the document — the text visibly jumped. A rotation or split-view change is
    /// the case the insets genuinely have to follow, and both change the view's size.
    private var insetsAppliedForSize: CGSize = .zero

    private func applySafeArea() {
        guard let webViewInsets, let window = view.window else { return }
        guard view.bounds.size != insetsAppliedForSize else { return }
        insetsAppliedForSize = view.bounds.size
        var insets = window.safeAreaInsets
        insets.top += Self.chromeBuffer
        insets.bottom += Self.chromeBuffer
        insets.left += appliedHorizontalGutter
        insets.right += appliedHorizontalGutter
        guard webViewInsets.constants != insets else { return }
        webViewInsets.apply(insets)
        view.layoutIfNeeded()
    }

    /// The size the document is laid out at, which is the web view's rather than the reader's.
    private func webViewSize() -> CGSize {
        book?.renderer?.webView.bounds.size ?? .zero
    }

    /// Opens the book and shows the page the reader left off at.
    private func open(startPage: Int) async {
        let settings = EpubPaginationSettings.fromUserDefaults(for: view.bounds.size)
        appliedColumnCount = settings.columnCount
        appliedHorizontalGutter = settings.paged ? 0 : CGFloat(settings.pageGutterPx)
        let book: ReaderEpubViewModel
        do {
            book = try ReaderEpubViewModel(bookURL: bookURL, settings: settings)
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not open \(bookURL.lastPathComponent): \(error)")
            delegate?.setPages([])
            return
        }
        book.onChange = { [weak self] in self?.report() }
        book.onOverscroll = { [weak self] forward in
            self?.navigate { book in
                if forward {
                    await book.moveForward()
                } else {
                    await book.moveBackward()
                }
            }
        }
        self.book = book

        // The web view is placed and laid out before the book is opened in it, so that the size
        // every page count belongs to is the size the view settled at. Predicting that size and
        // reconciling afterwards disagreed by a point or two, and any disagreement invalidates
        // every count and restarts the measurement pass, which is visible as the counter running
        // through the book a second time.
        let renderer: EpubSpineRenderer
        do {
            renderer = try await book.prepareRenderer()
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not build a renderer: \(error)")
            delegate?.setPages([])
            return
        }
        guard !Task.isCancelled else { return }
        install(renderer.webView)
        view.layoutIfNeeded()

        let viewport = renderer.webView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else {
            LogManager.logger.error("ReaderEpubViewController: the reader has no size to lay a book out in")
            delegate?.setPages([])
            return
        }
        lastViewport = viewport

        do {
            try await book.open(viewport: viewport)
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not lay out \(bookURL.lastPathComponent): \(error)")
            delegate?.setPages([])
            return
        }
        guard !Task.isCancelled else { return }

        if startPage > 1 {
            await book.showBookPage(startPage - 1)
        }
        report()
    }

    /// Tells the toolbar where the reader is and how long the book is.
    ///
    /// The total grows as the measurement pass fills it in, so it is rewritten when it changes
    /// rather than on every count. It is **not** withheld while the slider is dragged. A total is a
    /// label: `setPages` reaches `ReaderToolbarView.totalPages`, whose `didSet` updates the page
    /// count text and nothing else. The thumb is moved by `setCurrentPage`, which is where the
    /// guard belongs and now is. Withholding the total instead bought nothing and cost a book whose
    /// total froze at whatever it held when a drag began, for the rest of the book, whenever the
    /// flag outlived the drag by any route.
    private func report() {
        guard let book else { return }

        // A total of zero is an index that has just been invalidated by a resize, which is a book
        // about to be counted again rather than a book with no pages. The host reads an empty page
        // list as a chapter that failed to load and puts an alert on top of the reader, so a
        // rotation would announce a failure on every turn of the device. A book that genuinely
        // cannot be read reports its emptiness from the failure paths in `open` instead.
        let total = book.bookTotal
        if total > 0 && total != reportedTotal {
            reportedTotal = total
            delegate?.setPages(placeholderPages(count: total))
        }

        // A resume that could not be placed when it was asked for is retried here, through the same
        // queue as a page turn so that the two cannot run at once, and only once the counts it was
        // waiting on have landed.
        if book.canShowPendingBookPage {
            navigate { await $0.showPendingBookPage() }
        }

        // A rebuild's page-number landing is refined onto the place the reader actually left once the
        // new layout is finished being counted, which is the first moment the fraction can be turned
        // back into a page. Cleared first, so the navigation below does not see it as still pending,
        // and only while the reader has not moved themselves: `navigate` drops it precisely then.
        if book.isMeasured, let position = settingsReloadPosition, book.bookTotal > 1 {
            settingsReloadPosition = nil
            settingsReloadPage = nil
            let target = Int((position * Double(book.bookTotal - 1)).rounded())
            if target != book.bookPage {
                navigate { await $0.showBookPage(target) }
                return
            }
        }

        // A page the index cannot place yet is one in a document whose predecessors are still being
        // counted. Reporting a position then would put the reader somewhere arbitrary in the book.
        guard let page = book.bookPage else { return }
        // Never while the thumb is held. This is the call that moves it, through
        // `updateSliderPosition`, and the measurement pass lands counts often enough to drag it out
        // from under the finger. A flag that outlives the drag costs a position that lands late,
        // which the next page turn heals through `endSliding`.
        //
        // Never mid-navigation either, for the same reason from the other side: the states a move
        // passes through are not places the reader is, and `navigate` reports once the move has
        // settled.
        guard !isSliding, !isNavigating else { return }
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
        // The reader has taken over from wherever a rebuild was restoring them to.
        settingsReloadPage = nil
        settingsReloadPosition = nil
        guard book != nil else { return }
        guard moveTask == nil else {
            pendingMove = work
            return
        }
        isNavigating = true
        moveTask = Task { [weak self] in
            guard let self else { return }
            if let book {
                await work(book)
            }
            moveTask = nil
            if let next = pendingMove {
                // The queued turn continues the same navigation, so the position stays withheld
                // until the last of them has settled rather than surfacing between them.
                pendingMove = nil
                navigate(next)
            } else {
                isNavigating = false
                // A completed move is the definitive end of the drag that asked for it, since
                // `sliderStopped` is what queued this work. Cleared here as well as there because a
                // host may deliver a last value change after the touch has ended: `UISlider` does,
                // and that arrives after `sliderStopped` has already cleared the flag, setting it
                // again for good. The reader's position was then withheld for the rest of the book
                // while the book itself kept working, so the counter sat at whatever it last
                // reported. `ReaderSliderView`, which the shipping reader uses, sends
                // `.valueChanged` only from `continueTracking` and so never does this; the reader
                // does not depend on that being true of every host.
                isSliding = false
                report()
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ReaderEpubViewController: UIGestureRecognizerDelegate {
    // Only the reader's own swipes carry this delegate, so nothing else is affected.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - ReaderReaderDelegate

extension ReaderEpubViewController: ReaderReaderDelegate {
    func moveLeft() {
        endSliding()
        navigate { await $0.moveBackward() }
    }

    func moveRight() {
        endSliding()
        navigate { await $0.moveForward() }
    }

    /// Clears the dragging flag on any interaction that cannot coexist with a held thumb.
    ///
    /// The reader's position is withheld while the slider is being dragged so the thumb does not
    /// move under the finger. That makes the flag load-bearing: left set, the toolbar stops being
    /// told where the reader is. It is cleared by `sliderStopped`, but that depends on a single
    /// callback arriving, and a cancelled touch does not send one. A page turn proves no drag is in
    /// progress, so it heals the state rather than trusting the host to have reported the end of
    /// it. The book's **total** deliberately does not depend on this flag; see `report`.
    private func endSliding() {
        guard isSliding else { return }
        isSliding = false
        report()
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
        // Straight into the move, without reporting first. The position withheld for the length of
        // the drag is the one the reader is leaving, and publishing it here put the thumb back
        // where it started for as long as the move took. `navigate` reports once the move settles.
        let page = bookPage(for: value)
        navigate { await $0.showBookPage(page) }
    }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {
        guard self.chapter?.id != chapter.id else { return }
        self.chapter = chapter
        settingsReloadPage = nil
        settingsReloadPosition = nil
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
