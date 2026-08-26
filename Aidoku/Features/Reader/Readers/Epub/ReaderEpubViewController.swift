//
//  ReaderEpubViewController.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/13/26.
//

import AidokuRunner
import UIKit
import WebKit

// no UIPageViewController: one web view carries a whole spine document and its pages are scroll
// offsets within it, the shape ReaderWebtoonViewController already uses
class ReaderEpubViewController: BaseObservingViewController {
    weak var delegate: ReaderHoldingDelegate?

    var readingMode: ReadingMode = .ltr

    var chapter: AidokuRunner.Chapter?

    private let source: AidokuRunner.Source?
    private let manga: AidokuRunner.Manga

    // per chapter, not per reader: a folder holds several epubs and caching this per reader
    // reopened the wrong book while the host marked and deleted another
    private var bookURL: URL?

    private let providedBookURL: URL?

    private(set) var book: ReaderEpubViewModel?
    private var openTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?

    private var pendingMove: ((ReaderEpubViewModel) async -> Void)?

    // carried with the work: the slot is drained by restarting the move, and a restore that came
    // back as a reader's own move dropped the anchor it was restoring to
    private var pendingMoveIsRestore = false

    private var lastViewport: CGSize = .zero

    private struct WebViewInsets {
        let top: NSLayoutConstraint
        let bottom: NSLayoutConstraint
        let leading: NSLayoutConstraint
        let trailing: NSLayoutConstraint

        var constants: UIEdgeInsets {
            UIEdgeInsets(
                top: top.constant,
                left: leading.constant,
                bottom: bottom.constant,
                right: trailing.constant
            )
        }

        func apply(_ insets: UIEdgeInsets) {
            top.constant = insets.top
            bottom.constant = insets.bottom
            leading.constant = insets.left
            trailing.constant = insets.right
        }
    }

    private var webViewInsets: WebViewInsets?

    private var isSliding = false

    // a move into another document reports twice, which a dragged slider showed as a jump
    private var isNavigating = false

    private var reportedTotal = 0

    // the tap zones do not cancel the web view's touches, so one tap reaches both
    private var suppressedPageTurnAt: Date?

    private static let suppressedPageTurnWindow: TimeInterval = 0.75

    private var returnBookPage: Int?

    private var returnPosition: Double?

    private lazy var returnButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "arrow.uturn.backward",
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .body)
        )
        configuration.contentInsets = .zero
        // on the configuration, not the layer: a configured button draws its own background
        configuration.cornerStyle = .capsule
        configuration.background.backgroundColor = .systemBackground
        configuration.background.strokeColor = .separator
        configuration.background.strokeWidth = 1
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .label
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.15
        button.layer.shadowRadius = 6
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowPath = UIBezierPath(
            ovalIn: CGRect(x: 0, y: 0, width: Self.returnButtonDiameter, height: Self.returnButtonDiameter)
        ).cgPath
        button.alpha = 0
        button.isHidden = true
        button.addTarget(self, action: #selector(returnToJumpOrigin), for: .touchUpInside)
        return button
    }()

    private static let returnButtonDiameter: CGFloat = 44

    private static let returnOfferLifetime: TimeInterval = 5

    private var returnOfferTask: Task<Void, Never>?

    // the window's safe area, not the view's, or toggling the bars relays this out from under the
    // finger and the tap never registers
    private var returnButtonBottom: NSLayoutConstraint?

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga, bookURL: URL? = nil) {
        self.source = source
        self.manga = manga
        self.providedBookURL = bookURL
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        openTask?.cancel()
        moveTask?.cancel()
        settingsReloadTask?.cancel()
        returnOfferTask?.cancel()
    }

    private var settingsReloadTask: Task<Void, Never>?

    override func observe() {
        // baked into the injection script and every count, so a change invalidates all of it.
        // debounced because the steppers post once per tick
        for key in [
            "Reader.textReaderStyle", "Reader.textFontFamily", "Reader.textFontSize",
            "Reader.textLineSpacing", "Reader.textHorizontalPadding"
        ] {
            addObserver(forName: key) { [weak self] _ in
                self?.scheduleSettingsReload()
            }
        }
    }

    // across the whole run, not per rebuild: a mid-open book reports the start of itself, so
    // clearing this per rebuild put a reader who tapped a stepper twice on page one
    private var settingsReloadPage: Int?

    private var settingsReloadPosition: Double?

    // per document, since scroll mode rounds each count up and a book fraction drifts between
    // modes. the leading edge, not the history's column anchor, which skips text on the same device
    private var settingsReloadAnchor: (document: Int, fraction: Double)?

    // the count an anchor is applied against can be provisional, WebKit relayouting a moment after
    // load, so a changed count is the signal to apply the anchor again
    private var settingsReloadAnchorAppliedCount: Int?

    private func scheduleSettingsReload() {
        withdrawUnanchoredReturnOffer()
        // only from a reader who is where the last rebuild put them: captured mid-rebuild or
        // mid-move, the fraction records somewhere they never were
        let anchorSettled = moveTask == nil && settingsReloadAnchor.map {
            settingsReloadAnchorAppliedCount == book?.index.pageCount(forDocumentAt: $0.document)
        } ?? true
        if settingsReloadPage == nil {
            settingsReloadPage = (book?.bookPage).map { $0 + 1 }
            if anchorSettled {
                settingsReloadAnchor = book.flatMap { book in
                    book.edgeInDocument.map { (book.currentDocument, $0) }
                }
            }
            settingsReloadAnchorAppliedCount = nil
        }
        settingsReloadTask?.cancel()
        settingsReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            rebuildBook()
        }
    }

    func presentImagePreview(forTapAt point: CGPoint) async -> Bool {
        guard let book, let webView = book.renderer?.webView else { return false }
        let clientPoint = view.convert(point, to: webView)
        guard webView.bounds.contains(clientPoint) else { return false }
        if let data = await book.imageData(at: clientPoint), let image = UIImage(data: data) {
            present(EpubImagePreviewController(image: image), animated: true)
            return true
        }
        if let html = await book.renderer?.tableHTML(at: clientPoint) {
            present(EpubTablePreviewController(tableHTML: html), animated: true)
            return true
        }
        return false
    }

    private func rebuildBook() {
        guard book != nil else { return }
        let page = settingsReloadPage ?? (book?.bookPage).map { $0 + 1 } ?? 1
        tearDownBook()
        openTask = Task { [weak self] in
            await self?.open(startPage: page)
        }
    }

    private func tearDownBook() {
        openTask?.cancel()
        moveTask?.cancel()
        moveTask = nil
        pendingMove = nil
        pendingMoveIsRestore = false
        isNavigating = false
        isSliding = false
        reportedTotal = 0
        lastViewport = .zero
        insetsAppliedForSize = .zero
        book?.renderer?.webView.removeFromSuperview()
        webViewInsets = nil
        book = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // opaque, or the host's Reader.backgroundColor shows in the strips around the web view
        view.backgroundColor = .systemBackground

        // tap zones default to disabled and the web view does not scroll in paged mode, so
        // without this no touch gesture turns a page
        view.addGestureRecognizer(pagePan)

        installReturnButton()
    }

    private func installReturnButton() {
        view.addSubview(returnButton)
        let bottom = returnButton.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        returnButtonBottom = bottom
        NSLayoutConstraint.activate([
            returnButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.returnButtonMargin),
            returnButton.widthAnchor.constraint(equalToConstant: Self.returnButtonDiameter),
            returnButton.heightAnchor.constraint(equalToConstant: Self.returnButtonDiameter),
            bottom
        ])
    }

    private static let returnButtonMargin: CGFloat = 16
    private static let returnButtonToolbarClearance: CGFloat = 60

    private lazy var pagePan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        return pan
    }()

    private var panStartOffset: CGFloat = 0

    // the columns already sit side by side in one scroll view, so dragging its offset is the turn
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let renderer = book?.renderer, renderer.pageCount > 0 else { return }
        let pitch = renderer.pagePitch
        guard pitch > 0 else { return }
        let scrollView = renderer.webView.scrollView
        let translation = gesture.translation(in: view).x

        switch gesture.state {
            case .began:
                endSliding()
                panStartOffset = scrollView.contentOffset.x
            case .changed:
                let limit = CGFloat(renderer.pageCount - 1) * pitch
                let offset = panStartOffset - translation
                // the page past either end belongs to another document, so the drag resists there
                scrollView.contentOffset.x = if offset < 0 {
                    offset / 3
                } else if offset > limit {
                    limit + (offset - limit) / 3
                } else {
                    offset
                }
            case .ended, .cancelled, .failed:
                // projected rather than released, so a flick carries to the next page
                let projected = panStartOffset - translation - gesture.velocity(in: view).x * Self.panProjection
                settle(on: Int((projected / pitch).rounded()))
            default:
                break
        }
    }

    private static let panProjection: CGFloat = 0.1

    private func settle(on page: Int) {
        let animated = UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")
        navigate { book in
            if page < 0 {
                await book.moveBackward(animated: animated)
            } else if page >= book.renderer?.pageCount ?? 0 {
                await book.moveForward(animated: animated)
            } else {
                await book.move(toPage: page, animated: animated)
            }
        }
    }

    private var appliedColumnCount = 1

    // readium-css gives a scrolling document no page gutter, so its text runs to both edges
    private var appliedHorizontalGutter: CGFloat = 0

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySafeArea()
        let size = webViewSize()
        guard size != lastViewport, size.width > 0, size.height > 0 else { return }
        lastViewport = size

        withdrawUnanchoredReturnOffer()
        if book != nil, EpubPaginationSettings.columnCount(for: view.bounds.size) != appliedColumnCount {
            // an iPad rotating between one column and two, debounced to the settled size
            scheduleSettingsReload()
        } else {
            book?.viewportChanged(to: size)
        }
    }

    // never as injected env(safe-area-inset-*) rules: resizing changes env() and re-fragments the
    // document on a different tick from the one the renderer waits for
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

    // the window's insets survive a bar toggle where the view's do not, and a column is 100vh by
    // 100vw, so resizing on every toggle would move every boundary
    private static let chromeBuffer: CGFloat = 50

    // an iPad's top window inset is the status bar, which hides with the bars, so this is re-read
    // only when the view's size changes
    private var insetsAppliedForSize: CGSize = .zero

    private func applySafeArea() {
        guard let window = view.window else { return }
        returnButtonBottom?.constant = -(
            window.safeAreaInsets.bottom + Self.returnButtonMargin + Self.returnButtonToolbarClearance
        )
        guard let webViewInsets else { return }
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

    private func webViewSize() -> CGSize {
        book?.renderer?.webView.bounds.size ?? .zero
    }

    // the archive is known only to the source, so the page list is asked for as usual
    private enum ChapterContent {
        case epub(URL)
        case pages([Page])
        case superseded
    }

    private func chapterContent() async -> ChapterContent {
        if let bookURL {
            return .epub(bookURL)
        }
        if let providedBookURL {
            bookURL = providedBookURL
            return .epub(providedBookURL)
        }
        guard let chapter else { return .pages([]) }
        // checked again after the fetch, or a cancelled task caches the outgoing chapter's archive
        let chapterId = chapter.id
        let pages = await ReaderPagedViewModel.getPages(source: source, manga: manga, chapter: chapter)
        guard !Task.isCancelled, self.chapter?.id == chapterId else { return .superseded }
        guard
            let archive = pages.first(where: { $0.isEpubPage })?.zipURL,
            let url = URL(string: archive)
        else {
            return .pages(pages)
        }
        bookURL = url
        return .epub(url)
    }

    private func open(startPage: Int) async {
        let bookURL: URL
        switch await chapterContent() {
            case let .epub(url):
                bookURL = url
            case let .pages(pages):
                // handed over, not failed: the host picks a reader from the page list. an empty
                // list is a chapter that could not be read
                delegate?.setPages(pages)
                return
            case .superseded:
                return
        }
        guard !Task.isCancelled else { return }

        let settings = EpubPaginationSettings.fromUserDefaults(for: view.bounds.size)
        appliedColumnCount = settings.columnCount
        appliedHorizontalGutter = settings.paged ? 0 : CGFloat(settings.pageGutterPx)
        pagePan.isEnabled = settings.paged
        let book: ReaderEpubViewModel
        do {
            book = try ReaderEpubViewModel(bookURL: bookURL, settings: settings)
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not open \(bookURL.lastPathComponent): \(error)")
            delegate?.setPages([])
            return
        }
        book.onChange = { [weak self] in self?.report() }
        book.onLink = { [weak self] path, fragment in
            guard let self else { return }
            suppressedPageTurnAt = Date()
            offerReturn()
            navigate { await $0.showLocation(path: path, fragment: fragment) }
        }
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

        // laid out before the book opens, so every count belongs to the size the view settled at
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

        // held before open, or a report in between describes the head of the book and a close
        // saves page 1 over the progress being resumed to
        if startPage > 1 {
            book.holdBookPage(startPage - 1)
            // the saved page belongs to the viewport that counted it, so the fraction refines it.
            // never over a settings reload's anchor, which describes this session
            if settingsReloadPosition == nil, settingsReloadAnchor == nil {
                settingsReloadPosition = await savedScrollPosition()
            }
        }

        do {
            try await book.open(viewport: viewport)
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not lay out \(bookURL.lastPathComponent): \(error)")
            delegate?.setPages([])
            return
        }
        guard !Task.isCancelled else { return }

        await book.showPendingBookPage()

        report()
    }

    // both readers reflow, so both persist a fraction alongside the page number
    private func savedScrollPosition() async -> Double? {
        guard let chapterKey = chapter?.key else { return nil }
        let chapterId = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapterKey)
        return await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getHistory(chapterId: chapterId, context: context)?
                .scrollPosition?.doubleValue
        }
    }

    // meanwhile the reported position is the head of the book: right for the toolbar, wrong for
    // storage, where it would save page 1 over the progress being resumed to
    var isAwaitingResume: Bool {
        book?.pendingBookPage != nil
    }

    // the total is not withheld while dragging; only the position is, in setCurrentPage
    private func report() {
        guard let book else { return }

        // zero is an index just invalidated by a resize, and the host reads an empty page list as
        // a failed chapter, so a rotation announced a failure on every turn of the device
        let total = book.bookTotal
        if total > 0 && total != reportedTotal {
            reportedTotal = total
            delegate?.setPages(placeholderPages(count: total))
        }

        // through the same queue as a page turn, and as a restore, this being part of a rebuild
        if book.canShowPendingBookPage {
            navigate(isRestore: true) { await $0.showPendingBookPage() }
        }

        // floor, not nearest, or a restore skips text. the epsilon is a hundredth of a page, a
        // scroll offset coming back a few pixels under what was set. showEdge is why this navigates
        // even when the coarse landing already sits on the target page
        if book.isMeasured, let (document, fraction) = settingsReloadAnchor,
           let count = book.index.pageCount(forDocumentAt: document),
           let start = book.index.startOfDocument(at: document),
           count != settingsReloadAnchorAppliedCount {
            settingsReloadAnchorAppliedCount = count
            settingsReloadPosition = nil
            settingsReloadPage = nil
            let target = start + min(Int(fraction * Double(count) + 0.01), count - 1)
            navigate(isRestore: true) {
                await $0.showBookPage(target)
                await $0.renderer?.showEdge(fraction)
            }
            return
        } else if book.isMeasured, let position = settingsReloadPosition {
            settingsReloadPosition = nil
            settingsReloadPage = nil
            let target = min(Int(position * Double(book.bookTotal) + 0.01), book.bookTotal - 1)
            if target != book.bookPage {
                navigate(isRestore: true) { await $0.showBookPage(target) }
                return
            }
        }

        // an unplaceable page would report the reader somewhere arbitrary
        guard let page = book.bookPage else { return }
        // never while the thumb is held, this being the call that moves it, nor mid-navigation,
        // whose intermediate states are not places the reader is
        guard !isSliding, !isNavigating else { return }
        delegate?.setCurrentPage(page + 1, position: book.progression)
    }

    // the toolbar takes its total from the page count, so a book's length reaches it as pages.
    // they carry the archive, so isEpubPage stays true of them
    private func placeholderPages(count: Int) -> [Page] {
        // swiftlint:disable:next empty_count
        guard count > 0 else { return [] }
        let sourceId = source?.key ?? manga.sourceKey
        let chapterId = chapter?.key ?? ""
        let archive = bookURL?.absoluteString
        return (0..<count).map { index in
            Page(sourceId: sourceId, chapterId: chapterId, index: index, zipURL: archive)
        }
    }

    // one navigation at a time with one slot behind it: dropping taps feels broken, queuing them
    // all replays a burst. isRestore because only the reader's own move may drop a rebuild's anchor
    private func navigate(isRestore: Bool = false, _ work: @escaping (ReaderEpubViewModel) async -> Void) {
        if !isRestore {
            settingsReloadPage = nil
            settingsReloadPosition = nil
            settingsReloadAnchor = nil
            settingsReloadAnchorAppliedCount = nil
        }
        guard book != nil else { return }
        guard moveTask == nil else {
            pendingMove = work
            pendingMoveIsRestore = isRestore
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
                // the queued turn continues the same navigation, so the position stays withheld
                pendingMove = nil
                navigate(isRestore: pendingMoveIsRestore, next)
            } else {
                isNavigating = false
                // also cleared here: a host may send a last value change after the touch ended,
                // as UISlider does, which set the flag again for good
                isSliding = false
                report()
            }
        }
    }
}

// MARK: - Returning from a jump

extension ReaderEpubViewController {
    // called before the jump, since afterwards the page it would return to is the destination
    func offerReturn() {
        guard let book, let page = book.bookPage else { return }
        returnBookPage = page
        returnPosition = book.progression
        returnButton.accessibilityLabel = String(
            format: NSLocalizedString("BACK_TO_PAGE_X", comment: ""),
            page + 1
        )
        // the web view is added when a book opens, after this button, so it would sit above it
        view.bringSubviewToFront(returnButton)
        // ahead of the guard below, so a second jump restarts the countdown rather than
        // inheriting what is left of the first
        returnOfferTask?.cancel()
        returnOfferTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.returnOfferLifetime * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            hideReturnOffer()
        }
        guard returnButton.isHidden else { return }
        returnButton.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.returnButton.alpha = 1
        }
    }

    @objc func returnToJumpOrigin() {
        guard let target = returnTarget else { return }
        hideReturnOffer()
        navigate { await $0.showBookPage(target) }
    }

    // resolved against the layout as it stands now rather than the one the offer was made in
    private var returnTarget: Int? {
        if let returnPosition, let book, book.isMeasured {
            // the page containing the place, as the restore in report does
            return min(Int(returnPosition * Double(book.bookTotal) + 0.01), book.bookTotal - 1)
        }
        return returnBookPage
    }

    // only an offer held as a bare page number, made before the book finished being measured
    func withdrawUnanchoredReturnOffer() {
        guard returnBookPage != nil, returnPosition == nil else { return }
        hideReturnOffer()
    }

    func hideReturnOffer() {
        returnOfferTask?.cancel()
        returnOfferTask = nil
        returnBookPage = nil
        returnPosition = nil
        guard !returnButton.isHidden else { return }
        UIView.animate(withDuration: 0.2) {
            self.returnButton.alpha = 0
        } completion: { _ in
            self.returnButton.isHidden = true
        }
    }
}

// MARK: - Table of contents

extension ReaderEpubViewController: ReaderTableOfContentsReader {
    var tableOfContents: EpubTableOfContents {
        book?.toc ?? EpubTableOfContents(entries: [])
    }

    var hasReadTableOfContents: Bool {
        book != nil
    }

    func currentTableOfContentsEntry() async -> EpubTableOfContents.Entry? {
        await book?.currentEntry()
    }

    func bookPage(ofTableOfContentsEntry entry: EpubTableOfContents.Entry) -> Int? {
        book?.bookPage(ofEntry: entry)
    }

    func goToTableOfContentsEntry(_ entry: EpubTableOfContents.Entry) {
        offerReturn()
        navigate { await $0.showEntry(entry) }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ReaderEpubViewController: UIGestureRecognizerDelegate {
    // only the reader's own gestures carry this delegate
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
        turn(forward: false)
    }

    func moveRight() {
        turn(forward: true)
    }

    // consumed either way, since a tap late enough to be its own intent has also proved the link
    // is no longer the last thing that happened
    func consumesTap() -> Bool {
        guard let suppressedPageTurnAt else { return false }
        self.suppressedPageTurnAt = nil
        return Date().timeIntervalSince(suppressedPageTurnAt) < Self.suppressedPageTurnWindow
    }

    private func turn(forward: Bool) {
        endSliding()
        let animated = UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")
        navigate { book in
            if forward {
                await book.moveForward(animated: animated)
            } else {
                await book.moveBackward(animated: animated)
            }
        }
    }

    // left set, the flag stops the toolbar being told where the reader is, and sliderStopped
    // depends on a callback that a cancelled touch never sends, so a page turn heals it instead
    private func endSliding() {
        guard isSliding else { return }
        isSliding = false
        report()
    }

    // loading every document a drag passes over would make the slider unusable, so the book moves
    // once the thumb stops
    func sliderMoved(value: CGFloat) {
        isSliding = true
        guard reportedTotal > 0 else { return }
        delegate?.displayPage(bookPage(for: value) + 1)
    }

    func sliderStopped(value: CGFloat) {
        isSliding = false
        // without reporting first: the position withheld for the drag is the one being left, and
        // publishing it here put the thumb back where it started for as long as the move took
        let page = bookPage(for: value)
        navigate { await $0.showBookPage(page) }
    }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {
        guard self.chapter?.id != chapter.id else { return }
        self.chapter = chapter
        // the page the offer names belongs to the book being left
        hideReturnOffer()
        // resolved again, the old one having belonged to the chapter being left
        bookURL = nil
        settingsReloadPage = nil
        settingsReloadPosition = nil
        settingsReloadAnchor = nil
        settingsReloadAnchorAppliedCount = nil
        // the book being left goes with the chapter it belonged to
        tearDownBook()
        openTask = Task { [weak self] in
            await self?.open(startPage: startPage)
        }
    }

    // a fraction of the whole book, matching the index / (count - 1) convention the toolbar uses
    private func bookPage(for value: CGFloat) -> Int {
        let last = max(reportedTotal - 1, 0)
        return min(max(Int((value * CGFloat(last)).rounded()), 0), last)
    }
}

// MARK: - Image Preview

// fullscreen viewer for one image, dismissed by a single tap or the close button
private final class EpubImagePreviewController: UIViewController {
    private let image: UIImage
    private let scrollView = ZoomableScrollView()
    private let imageView: UIImageView

    init(image: UIImage) {
        self.image = image
        self.imageView = UIImageView(image: image)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)
        // `zoomView` only wires the zoom target; adding it to the hierarchy is the caller's job.
        scrollView.addSubview(imageView)
        scrollView.zoomView = imageView

        let closeButton = UIButton(type: .close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])

        // The same trick the reader's own gestures use: the dismissing tap waits for a double tap
        // to fail, so the first tap of `ZoomableScrollView`'s double-tap zoom cannot dismiss.
        let doubleTap = UITapGestureRecognizer(target: self, action: nil)
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        tap.require(toFail: doubleTap)
        view.addGestureRecognizer(tap)
    }

    // so a layout pass firing mid-pinch does not re-fit and reset the zoom
    private var fittedSize: CGSize = .zero

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = scrollView.bounds.size
        guard bounds != fittedSize else { return }
        fittedSize = bounds
        // Reset to an aspect fit of the current bounds; a rotation re-fits rather than keeping a
        // zoom that belonged to the old size.
        scrollView.zoomScale = 1
        guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height, 1)
        imageView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: image.size.width * scale, height: image.size.height * scale)
        )
        scrollView.contentSize = imageView.frame.size
        scrollView.centerView()
    }

    @objc private func didTap() {
        dismiss(animated: true)
    }
}

// MARK: - Table Preview

// fullscreen viewer for one table, at its natural size
private final class EpubTablePreviewController: UIViewController {
    private let tableHTML: String

    init(tableHTML: String) {
        self.tableHTML = tableHTML
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let webView = WKWebView(frame: view.bounds)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        view.addSubview(webView)
        webView.loadHTMLString(Self.shell(around: tableHTML), baseURL: nil)

        let closeButton = UIButton(type: .close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    // the book's stylesheets are not carried over, and the scale the injection script left inline
    // is undone. user-scalable, so a pinch zooms the way the book itself deliberately cannot
    private static func shell(around tableHTML: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { margin: 16px; margin-top: 60px; font-family: -apple-system, sans-serif; }
        table { transform: none !important; border-collapse: collapse; }
        td, th { border: 1px solid rgba(128, 128, 128, 0.5); padding: 0.25em 0.5em; }
        </style>
        </head>
        <body>\(tableHTML)</body>
        </html>
        """
    }
}
