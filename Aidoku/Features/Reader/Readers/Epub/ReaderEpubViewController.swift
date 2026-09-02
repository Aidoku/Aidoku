//
//  ReaderEpubViewController.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/13/26.
//

import AidokuRunner
import SafariServices
import UIKit
import WebKit

// the paged style turns pages with a UIPageViewController, the shape the paged text and image
// readers use; the scroll style reads through one web view per spine document. either way one
// epub is one chapter, and the toolbar describes the book
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
    private(set) var paged: EpubPagedViewController?
    private var openTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?

    private var pendingMove: ((ReaderEpubViewModel) async -> Void)?

    // carried with the work: the slot is drained by restarting the move, and a restore that came
    // back as a reader's own move dropped the anchor it was restoring to
    private var pendingMoveIsRestore = false

    private var lastViewport: CGSize = .zero

    private var isSliding = false

    // a move into another document reports twice, which a dragged slider showed as a jump
    private var isNavigating = false

    private var reportedTotal = 0

    // the scroll style's tap zones do not cancel the web view's touches, so one tap reaches both;
    // the paged style's pages take no touches at all, so nothing there needs suppressing
    private var suppressedPageTurnAt: Date?

    private static let suppressedPageTurnWindow: TimeInterval = 0.75

    private var appliedPaged = true

    private var appliedColumnCount = 1

    // readium-css gives a scrolling document no page gutter, so its text runs to both edges
    private var appliedHorizontalGutter: CGFloat = 0

    private var appliedScrollClearance: UIEdgeInsets = .zero

    private var settingsReloadTask: Task<Void, Never>?

    // MARK: - Loading gate

    // the book is measured before it is shown, so every page has an address and the total is
    // reported once rather than climbing under the reader; what was on screen covers the wait
    private var loadingCover: UIView?

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Return offer

    private var returnBookPage: Int?

    private var returnPosition: Double?

    private lazy var returnButton: UIButton = {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = .secondarySystemBackground
        }
        configuration.baseForegroundColor = .tintColor
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(
            systemName: "arrow.uturn.backward",
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .body)
        )
        configuration.contentInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
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

    private static let returnButtonMargin: CGFloat = 16
    private static let returnButtonToolbarClearance: CGFloat = 60

    // the bars' glass refracts what sits under them, so paged content is inset clear of the edges
    // where scroll content passes beneath and pads inside the document instead
    private static let chromeBuffer: CGFloat = 50

    // MARK: - Lifecycle

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

    override func viewDidLoad() {
        super.viewDidLoad()

        // opaque, or the host's Reader.backgroundColor shows around the pages
        view.backgroundColor = .systemBackground

        // a long press is WebKit starting a selection in the scroll style, and the tap ending it
        // is not a page turn
        view.addGestureRecognizer(selectionPress)

        installReturnButton()
    }

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

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        paged?.releaseSpares()
    }

    private lazy var selectionPress: UILongPressGestureRecognizer = {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleSelectionPress))
        press.delegate = self
        press.cancelsTouchesInView = false
        return press
    }()

    // stamped for every state, so the window is measured from the finger lifting
    @objc private func handleSelectionPress() {
        suppressedPageTurnAt = Date()
        // the paged style's pages take no touches, so the selection is started for them here
        guard selectionPress.state == .began, let book, book.paged, let paged else { return }
        let point = selectionPress.location(in: view)
        Task { await paged.beginSelection(at: point) }
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let window = view.window {
            returnButtonBottom?.constant = -(
                window.safeAreaInsets.bottom + Self.returnButtonMargin + Self.returnButtonToolbarClearance
            )
        }

        let size = view.bounds.size
        guard size != lastViewport, size.width > 0, size.height > 0 else { return }
        let hadViewport = lastViewport != .zero
        lastViewport = size

        withdrawUnanchoredReturnOffer()
        guard book != nil, hadViewport else { return }
        if appliedPaged {
            // every page is laid out at the viewport, so a resize rebuilds the book at the new
            // one, restoring through the same anchor a settings change uses
            scheduleSettingsReload()
        } else {
            let clearance = scrollClearance()
            if clearance != appliedScrollClearance {
                appliedScrollClearance = clearance
                book?.setScrollPadding(clearance)
            }
            book?.viewportChanged(to: size)
        }
    }

    // MARK: - Settings changes

    // across the whole run, not per rebuild: a mid-open book reports the start of itself, so
    // clearing this per rebuild put a reader who tapped a stepper twice on page one
    private var settingsReloadPage: Int?

    private var settingsReloadPosition: Double?

    // per document, since scroll mode rounds each count up and a book fraction drifts between
    // modes. the leading edge, not the history's column anchor, which skips text on the same device
    private var settingsReloadAnchor: (document: Int, fraction: Double)?

    // the count an anchor is applied against can be provisional in the scroll style, WebKit
    // relayouting a moment after load, so a changed count is the signal to apply the anchor again
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

    private func rebuildBook() {
        guard book != nil else { return }
        let page = settingsReloadPage ?? (book?.bookPage).map { $0 + 1 } ?? 1
        coverForRebuild()
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
        if let paged {
            paged.willMove(toParent: nil)
            paged.view.removeFromSuperview()
            paged.removeFromParent()
        }
        paged = nil
        book?.renderer?.webView.removeFromSuperview()
        book = nil
    }

    // MARK: - Opening

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
                uncover()
                delegate?.setPages(pages)
                return
            case .superseded:
                uncover()
                return
        }
        guard !Task.isCancelled else { return }

        var settings = EpubPaginationSettings.fromUserDefaults(for: view.bounds.size)
        appliedPaged = settings.paged
        appliedColumnCount = settings.columnCount
        appliedHorizontalGutter = settings.paged ? 0 : CGFloat(settings.pageGutterPx)
        let clearance = scrollClearance()
        appliedScrollClearance = clearance
        settings.applyScrollClearance(clearance)

        let book: ReaderEpubViewModel
        do {
            book = try ReaderEpubViewModel(bookURL: bookURL, settings: settings)
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not open \(bookURL.lastPathComponent): \(error)")
            uncover()
            delegate?.setPages([])
            return
        }
        book.onChange = { [weak self] in self?.report() }
        book.onLink = { [weak self] path, fragment in
            guard let self else { return }
            suppressedPageTurnAt = Date()
            offerReturn()
            go(toPath: path, fragment: fragment)
        }
        book.onExternalLink = { [weak self] url in self?.openExternal(url) }
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

        view.layoutIfNeeded()
        lastViewport = view.bounds.size

        if settings.paged {
            await openPaged(book, startPage: startPage)
        } else {
            await openScroll(book, startPage: startPage)
        }
    }

    private func openPaged(_ book: ReaderEpubViewModel, startPage: Int) async {
        coverForOpen()

        let insets = pagedContentInsets()
        let viewport = view.bounds.inset(by: insets).size
        guard viewport.width > 0, viewport.height > 0 else {
            LogManager.logger.error("ReaderEpubViewController: the reader has no size to lay a book out in")
            uncover()
            delegate?.setPages([])
            return
        }

        // held through the wait, so nothing reads the covered book as being at page 1
        if startPage > 1 {
            book.holdBookPage(startPage - 1)
        }
        // the saved page belongs to the viewport that counted it, so the fraction refines it.
        // never over a settings reload's anchor, which describes this session
        if startPage > 1, settingsReloadPosition == nil, settingsReloadAnchor == nil {
            settingsReloadPosition = await savedScrollPosition()
        }

        await book.openPaged(viewport: viewport)
        guard !Task.isCancelled, self.book === book else { return }

        // once, after the whole book is measured: a total that climbs under the reader moves
        // every position it has already reported
        reportedTotal = book.bookTotal
        delegate?.setPages(placeholderPages(count: book.bookTotal))

        let target = startBookPage(for: book, startPage: startPage)
        settingsReloadPage = nil
        settingsReloadPosition = nil
        settingsReloadAnchorAppliedCount = settingsReloadAnchor.flatMap { book.index.pageCount(forDocumentAt: $0.document) }
        // where the reader is, known before the page exists: everything that reads the position
        // meanwhile — persistence, the toolbar, a settings change — must see the restore target
        // rather than the head of the book
        book.notePagedPosition(bookPage: target)

        let paged = EpubPagedViewController(book: book.makePagedBook(), contentInsets: insets)
        paged.onPageChanged = { [weak self, weak book] page in
            book?.notePagedPosition(bookPage: page)
            self?.report()
        }
        paged.onSelectionEnded = { [weak self] in
            // the tap that dismissed the selection is not a page turn
            self?.suppressedPageTurnAt = Date()
        }
        paged.onWillTurn = { [weak self] in
            if UserDefaults.standard.bool(forKey: "Reader.hideBarsOnSwipe") {
                self?.delegate?.hideBars()
            }
        }
        addChild(paged)
        view.insertSubview(paged.view, at: 0)
        paged.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            paged.view.topAnchor.constraint(equalTo: view.topAnchor),
            paged.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paged.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paged.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        paged.didMove(toParent: self)
        self.paged = paged
        view.layoutIfNeeded()

        await paged.open(atBookPage: target)
        guard !Task.isCancelled, self.book === book else { return }
        uncover()
        report()
    }

    // the rebuild's anchor first, then a stored fraction, then the page the host handed over
    private func startBookPage(for book: ReaderEpubViewModel, startPage: Int) -> Int {
        let total = book.bookTotal
        guard total > 0 else { return 0 }
        if let (document, fraction) = settingsReloadAnchor,
           let count = book.index.pageCount(forDocumentAt: document),
           let start = book.index.startOfDocument(at: document) {
            // floor, not nearest, or a restore skips text. the epsilon is a hundredth of a page
            return start + min(Int(fraction * Double(count) + 0.01), count - 1)
        }
        if let position = settingsReloadPosition {
            return min(Int(position * Double(total) + 0.01), total - 1)
        }
        if startPage > 1 {
            return min(startPage - 1, total - 1)
        }
        return 0
    }

    private func pagedContentInsets() -> UIEdgeInsets {
        // the window's insets survive a bar toggle where the view's do not, and a page is laid
        // out once per build, so resizing on every toggle would move every boundary
        let safeArea = view.window?.safeAreaInsets ?? view.safeAreaInsets
        return UIEdgeInsets(
            top: safeArea.top + Self.chromeBuffer,
            left: safeArea.left,
            bottom: safeArea.bottom + Self.chromeBuffer,
            right: safeArea.right
        )
    }

    private func openScroll(_ book: ReaderEpubViewModel, startPage: Int) async {
        // laid out before the book opens, so every count belongs to the size the view settled at
        let renderer: EpubSpineRenderer
        do {
            renderer = try await book.prepareRenderer()
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not build a renderer: \(error)")
            uncover()
            delegate?.setPages([])
            return
        }
        guard !Task.isCancelled else { return }

        let webView = renderer.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(webView, at: 0)
        // to the view's edges: scroll content passes under the bars and pads inside the document,
        // which puts a cut line at the screen edge rather than mid-screen
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.layoutIfNeeded()

        let viewport = webView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else {
            LogManager.logger.error("ReaderEpubViewController: the reader has no size to lay a book out in")
            uncover()
            delegate?.setPages([])
            return
        }

        // held before open, or a report in between describes the head of the book and a close
        // saves page 1 over the progress being resumed to
        if startPage > 1 {
            book.holdBookPage(startPage - 1)
            if settingsReloadPosition == nil, settingsReloadAnchor == nil {
                settingsReloadPosition = await savedScrollPosition()
            }
        }

        do {
            try await book.open(viewport: viewport)
        } catch {
            LogManager.logger.error("ReaderEpubViewController: could not lay out \(bookURL?.lastPathComponent ?? "the book"): \(error)")
            uncover()
            delegate?.setPages([])
            return
        }
        guard !Task.isCancelled else { return }

        uncover()
        await book.showPendingBookPage()
        report()
    }

    private func scrollClearance() -> UIEdgeInsets {
        let safeArea = view.window?.safeAreaInsets ?? view.safeAreaInsets
        return UIEdgeInsets(
            top: safeArea.top + Self.chromeBuffer,
            left: max(safeArea.left, appliedHorizontalGutter),
            bottom: safeArea.bottom + Self.chromeBuffer,
            right: max(safeArea.right, appliedHorizontalGutter)
        )
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
}

// MARK: - Loading gate

extension ReaderEpubViewController {
    // with what was on screen when there is something
    private func coverForRebuild() {
        guard loadingCover == nil else { return }
        let cover = UIView(frame: view.bounds)
        cover.backgroundColor = .systemBackground
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let content = paged?.currentWebView ?? book?.renderer?.webView,
           content.window != nil,
           let snapshot = view.snapshotView(afterScreenUpdates: false) {
            // frosted, so the wait reads as a change under way and the spinner shows over text
            let frost = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            for layer in [snapshot, frost] {
                layer.frame = cover.bounds
                layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                cover.addSubview(layer)
            }
        }
        view.addSubview(cover)
        loadingCover = cover
        showLoadingIndicator(on: cover)
    }

    private func coverForOpen() {
        guard loadingCover == nil else { return }
        let cover = UIView()
        cover.backgroundColor = .systemBackground
        cover.frame = view.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(cover)
        loadingCover = cover
        showLoadingIndicator(on: cover)
    }

    private func showLoadingIndicator(on cover: UIView) {
        loadingIndicator.removeFromSuperview()
        cover.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: cover.centerYAnchor)
        ])
        loadingIndicator.startAnimating()
    }

    private func uncover() {
        loadingIndicator.stopAnimating()
        guard let cover = loadingCover else { return }
        loadingCover = nil
        UIView.animate(withDuration: 0.15) {
            cover.alpha = 0
        } completion: { _ in
            cover.removeFromSuperview()
        }
    }
}

// MARK: - Reporting

extension ReaderEpubViewController {
    private func report() {
        guard let book else { return }

        // behind the loading cover nothing is reported: the paged book publishes its total once,
        // final, when it is revealed, so no position lands against a total still climbing
        if book.paged, loadingCover != nil { return }

        // zero is an index just invalidated by a resize, and the host reads an empty page list as
        // a failed chapter, so a rotation announced a failure on every turn of the device
        let total = book.bookTotal
        if total > 0 && total != reportedTotal {
            reportedTotal = total
            delegate?.setPages(placeholderPages(count: total))
        }

        // the scroll style measures behind the reader, so its restores land through here once the
        // index can place them; the paged style resolves its start before anything is shown
        if !book.paged {
            if book.canShowPendingBookPage {
                navigate(isRestore: true) { await $0.showPendingBookPage() }
            }

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

// MARK: - Going places

extension ReaderEpubViewController {
    private func go(toDocument document: Int, fragment: String?) {
        guard let book else { return }
        if book.paged {
            navigate { [weak self] book in
                guard let self, let paged, let start = book.startOfDocument(at: document) else { return }
                await paged.show(bookPage: start, animated: false)
                guard let fragment, let renderer = paged.currentRenderer else { return }
                if let page = await renderer.fragmentPages([fragment])[fragment], page > 0 {
                    await paged.show(bookPage: start + page, animated: false)
                }
            }
        } else {
            navigate { await $0.showEntry(.init(id: 0, title: "", document: document, fragment: fragment, depth: 0)) }
        }
    }

    private func go(toPath path: String, fragment: String?) {
        guard let book else { return }
        guard let document = book.spinePaths.firstIndex(of: path) else {
            LogManager.logger.warn("ReaderEpubViewController: link to \(path) is not in the spine")
            return
        }
        go(toDocument: document, fragment: fragment)
    }

    func showBookPage(_ page: Int) {
        guard let book else { return }
        if book.paged {
            navigate { [weak self] _ in
                await self?.paged?.show(bookPage: page, animated: false)
            }
        } else {
            navigate { await $0.showBookPage(page) }
        }
    }

    private func openExternal(_ url: URL) {
        // a lookup or the settings sheet can already be up, and presenting over one fails
        guard presentedViewController == nil else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = view.tintColor
        present(safari, animated: true)
    }
}

// MARK: - Content taps

extension ReaderEpubViewController {
    // true consumes the tap. the paged style's pages take no touches, so their links are
    // answered here
    func handleContentTap(at point: CGPoint) async -> Bool {
        guard let book else { return false }
        let renderer = book.paged ? paged?.currentRenderer : book.renderer
        guard let renderer else { return false }
        let webView = renderer.webView
        let clientPoint = view.convert(point, to: webView)
        guard webView.bounds.contains(clientPoint) else { return false }

        if book.paged, let target = await renderer.linkTarget(at: clientPoint) {
            switch target {
                case let .inBook(path, fragment):
                    offerReturn()
                    go(toPath: path, fragment: fragment)
                case let .external(url):
                    openExternal(url)
            }
            return true
        }
        if let data = await book.imageData(at: clientPoint, renderer: renderer), let image = UIImage(data: data) {
            present(EpubImagePreviewController(image: image), animated: true)
            return true
        }
        if let html = await renderer.tableHTML(at: clientPoint) {
            present(EpubTablePreviewController(tableHTML: html), animated: true)
            return true
        }
        return false
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
        // content views are added under it, but a rebuild can reorder; it must stay on top
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
        showBookPage(target)
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
        guard let book else { return nil }
        return await book.currentEntry(renderer: book.paged ? paged?.currentRenderer : nil)
    }

    func bookPage(ofTableOfContentsEntry entry: EpubTableOfContents.Entry) -> Int? {
        book?.bookPage(ofEntry: entry)
    }

    func goToTableOfContentsEntry(_ entry: EpubTableOfContents.Entry) {
        offerReturn()
        go(toDocument: entry.document, fragment: entry.fragment)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ReaderEpubViewController: UIGestureRecognizerDelegate {
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
        if paged?.isSelecting == true { return true }
        guard let suppressedPageTurnAt else { return false }
        self.suppressedPageTurnAt = nil
        return Date().timeIntervalSince(suppressedPageTurnAt) < Self.suppressedPageTurnWindow
    }

    private func turn(forward: Bool) {
        endSliding()
        let animated = UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")
        guard let book else { return }
        if book.paged {
            navigate { [weak self] _ in
                await self?.paged?.turn(forward: forward, animated: animated)
            }
        } else {
            navigate { book in
                if forward {
                    await book.moveForward(animated: animated)
                } else {
                    await book.moveBackward(animated: animated)
                }
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
        showBookPage(bookPage(for: value))
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
