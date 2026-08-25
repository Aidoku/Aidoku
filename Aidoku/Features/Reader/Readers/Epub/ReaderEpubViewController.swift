//
//  ReaderEpubViewController.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/13/26.
//

import AidokuRunner
import UIKit
import WebKit

// ReaderEpubViewModel owns the reading state and the navigation; this owns the view, the chrome
// and the conversation with ReaderHoldingDelegate.
//
// no UIPageViewController, unlike the paged image reader: one web view carries a whole spine
// document and its pages are scroll offsets within it, so there is no per-page view controller to
// give a data source. ReaderWebtoonViewController is the sibling precedent
class ReaderEpubViewController: BaseObservingViewController {
    weak var delegate: ReaderHoldingDelegate?

    // epub text reads left to right regardless of the manga setting, as the text reader does. a
    // right-to-left publication is a readium-css concern rather than a gesture one
    var readingMode: ReadingMode = .ltr

    var chapter: AidokuRunner.Chapter?

    private let source: AidokuRunner.Source?
    private let manga: AidokuRunner.Manga

    // resolved from the chapter's own page list rather than fixed when the reader is built, since a
    // manga folder may hold several epubs, one chapter each: a reader that kept the archive it was
    // born with reopened the first book on a chapter change while the host marked the second read
    // and, with Library.deleteDownloadAfterReading, deleted it
    private var bookURL: URL?

    // for a host that has a file and no source to ask for a page list, which is the debug host.
    // used for every chapter, which is correct only because such a host never changes chapter
    private let providedBookURL: URL?

    private(set) var book: ReaderEpubViewModel?
    private var openTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?

    // the one turn held while another is in flight. see navigate
    private var pendingMove: ((ReaderEpubViewModel) async -> Void)?

    // carried alongside the work because the slot is drained by starting the move again, and a
    // restore that came back through that route as a reader's own move dropped the anchor it was
    // restoring to
    private var pendingMoveIsRestore = false

    // so a layout pass that changes nothing does not invalidate every page count
    private var lastViewport: CGSize = .zero

    // held so their constants can be updated as the safe area changes, without rebuilding them
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

    // so the total firming up does not move the thumb under the finger
    private var isSliding = false

    // a move crossing into another spine document reports twice on its way, once when the document
    // loads at its first page and once when the page asked for is shown, so a drag across a
    // document boundary landed near the target, jumped to the head of that document, then settled
    private var isNavigating = false

    // so the toolbar is rewritten when the total changes rather than on every count that lands
    private var reportedTotal = 0

    // the tap zones sit over the web view and do not cancel its touches, which is what lets the
    // document keep text selection and links at all, so one tap reaches both. the reader's own
    // handling is the earlier of the two, since the host's single tap waits for its double tap to
    // fail, so the turn is the one that can be suppressed
    private var suppressedPageTurnAt: Date?

    // longer than the double-tap failure the host's single tap waits on, and short enough that a
    // reader who follows a link and then deliberately taps to turn is not ignored
    private static let suppressedPageTurnWindow: TimeInterval = 0.75

    // offered back to the reader while returnButton is showing
    private var returnBookPage: Int?

    // the same place as a fraction, which is what survives the book being laid out again: a page
    // number captured before a jump names somewhere else entirely after a rotation. only available
    // once the book is measured, so the page number carries the offer until then and
    // withdrawUnanchoredReturnOffer takes it away if the layout changes first
    private var returnPosition: Double?

    // a footnote is the case that needs it: the link takes the reader across the book, and the only
    // other way back is the slider, which does not know where they were. opaque so it is legible
    // over text, and cornered so it covers as little of the page as possible
    private lazy var returnButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "arrow.uturn.backward",
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .body)
        )
        configuration.contentInsets = .zero
        // A capsule around a square is a circle, which is the shape iOS gives a floating control of
        // this size. The fill and the stroke belong to the configuration rather than to the layer:
        // a configured button draws its own background, so styling the layer instead left the
        // configuration's rounded rectangle sitting on top of the circle the layer had drawn.
        configuration.cornerStyle = .capsule
        // Opaque rather than a material or a translucent fill. The page behind it is text, and a
        // fill that lets text through is what made the first version unreadable.
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
        // The layer has no background to cast a shadow from, and the size is a constant, so the
        // path is given rather than derived.
        button.layer.shadowPath = UIBezierPath(
            ovalIn: CGRect(x: 0, y: 0, width: Self.returnButtonDiameter, height: Self.returnButtonDiameter)
        ).cgPath
        button.alpha = 0
        button.isHidden = true
        button.addTarget(self, action: #selector(returnToJumpOrigin), for: .touchUpInside)
        return button
    }()

    // a full touch target, which the icon alone is not
    private static let returnButtonDiameter: CGFloat = 44

    // the readers this was shaped after leave the offer until it is used, which in use here was a
    // control in the corner of every page for the rest of the chapter
    private static let returnOfferLifetime: TimeInterval = 5

    // cancelled if the offer goes before it fires
    private var returnOfferTask: Task<Void, Never>?

    // kept at the window's safe area rather than the view's, whose insets include the bars and
    // change when they toggle: a control that moves between a touch going down and coming up never
    // reports the touch at all, and pinned to view.safeAreaLayoutGuide every tap on this toggled
    // the bars and relaid it out from under the finger, reading as a button that did nothing
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

    // the debounced rebuild a settings change schedules
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

    // held across the whole run rather than per rebuild: a second settings change arrives while the
    // rebuild for the first is still opening the book, and a mid-open book reports the start of the
    // book, so clearing this after one rebuild put a reader who tapped a stepper twice on page one.
    //
    // the page number is the immediate landing, being the only anchor available before the new
    // layout is counted, and is not where the reader belongs: 18pt to 20pt took a 456 page book to
    // 520, which puts page 400 about fifty-six pages out
    private var settingsReloadPage: Int?

    // only for a place saved by another layout entirely, where the book fraction is all that was
    // kept. an in-session rebuild has settingsReloadAnchor instead
    private var settingsReloadPosition: Double?

    // per document rather than as a fraction of the whole book: scroll mode rounds every document's
    // count up, so a long spine inflates the scroll total by half a page per document and a book
    // fraction carried between modes drifted by several pages. the leading edge rather than the
    // column anchor the history uses, since the column anchor put a reader still in an iPad
    // spread's left column onto the right column's text when they switched to scroll mode
    private var settingsReloadAnchor: (document: Int, fraction: Double)?

    // the anchor outlives its first application because the count it was applied against can be
    // provisional: WebKit lays a freshly loaded document out again a moment later, and an anchor at
    // 0.675 applied at 32 pages landed on page 21 of what settled at 40. a changed count is the
    // signal to apply it again, and an unchanged one keeps re-applying from looping, since a
    // navigation this controller performs cannot change a count
    private var settingsReloadAnchorAppliedCount: Int?

    private func scheduleSettingsReload() {
        withdrawUnanchoredReturnOffer()
        // Only from a reader who is where the last rebuild put them. A rebuild lands them on the
        // old layout's page number and refines that onto the anchor once the new counts arrive, and
        // between the two the reader is at a coarse landing rather than at their place: capturing
        // then divided a landing by the new layout's count and recorded a reader at 0.667 of their
        // document as 0.467, resuming twelve pages early. A move still in flight is worse than
        // coarse, since scroll mode's fraction is read from an offset the move has not yet set: a
        // capture during one recorded 0.954.
        //
        // The anchor already held is what a reader in either state belongs at, so it is kept rather
        // than replaced. Settled means no move in flight and the anchor applied against the count
        // its document currently holds; a run with no anchor yet has nothing to keep and captures,
        // except mid-move, where no anchor restores nearer than a wrong one.
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

    // reports whether it did, so the host runs its tap zones only for taps that hit neither.
    // point is in this controller's view coordinates
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

    // tears the book down and opens it again at the same place, with the current settings
    private func rebuildBook() {
        guard book != nil else { return }
        // The page numbers of the old layout are the best available guess at a place in the
        // new one; `open` holds it as a pending page until the new counts can place it.
        let page = settingsReloadPage ?? (book?.bookPage).map { $0 + 1 } ?? 1
        tearDownBook()
        openTask = Task { [weak self] in
            await self?.open(startPage: page)
        }
    }

    // a book being replaced has to be removed rather than merely dropped: install adds a web view
    // without taking the previous one out, and a total is only rewritten when it changes
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

        installReturnButton()
    }

    // its distance from the bottom is set in applySafeArea, from the window's insets, so showing
    // or hiding the bars does not move it
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

    // clear of the toolbar in both bar states, since the button appears in both
    private static let returnButtonMargin: CGFloat = 16
    private static let returnButtonToolbarClearance: CGFloat = 60

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        // ePub text reads left to right, so swiping the content left goes forward.
        //
        // Turned directly rather than through `moveRight`/`moveLeft`: those suppress the turn that
        // a tap on a link produces alongside it, and a swipe is never that tap.
        switch gesture.direction {
            case .left: turn(forward: true)
            case .right: turn(forward: false)
            default: break
        }
    }

    // the column count is baked into the renderer's injection script, so a re-measure alone cannot
    // change it and a rotation that changes it has to rebuild the book
    private var appliedColumnCount = 1

    // readium-css scopes its page gutter to a paged document, so a scrolling one has no horizontal
    // padding at all and its text runs to both edges. answered by insetting the view rather than by
    // adding a rule, since the view's own size is the one input the renderer re-measures against
    private var appliedHorizontalGutter: CGFloat = 0

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySafeArea()
        let size = webViewSize()
        guard size != lastViewport, size.width > 0, size.height > 0 else { return }
        lastViewport = size
        // Either branch lays the book out again, which moves every page boundary.
        withdrawUnanchoredReturnOffer()
        if book != nil, EpubPaginationSettings.columnCount(for: view.bounds.size) != appliedColumnCount {
            // An iPad rotating between one column (portrait) and two (landscape). Debounced with
            // the settings path so the rebuild sees the size the rotation settles at.
            scheduleSettingsReload()
        } else {
            book?.viewportChanged(to: size)
        }
    }

    // nothing about the safe area is expressed in css. an earlier attempt injected
    // env(safe-area-inset-*) rules and broke pagination: a web view's safe area depends on where it
    // sits in its window, so resizing it changes env(), which re-fragments the document on a
    // different tick from the one the renderer waits for. insetting the view instead leaves the
    // document with exactly one thing deciding its layout, its own size
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

    // the window's insets are the notch and home indicator and do not change when the bars toggle;
    // the view's include the bars and do. a column is 100vh by 100vw, so a web view that resized on
    // every tap toggling the chrome would move every page boundary. same distinction, and reason,
    // as ReaderPagedTextViewController's use of view.window?.safeAreaInsets.
    //
    // the buffer reserves fixed space for the translucent bars, which overlay the reader, without
    // the viewport changing when they are toggled
    private static let chromeBuffer: CGFloat = 50

    // an iPad has no notch, so its top window inset is the status bar, which hides with the bars:
    // read on every layout pass, that resized the web view on every toggle and the text visibly
    // jumped. a rotation or split-view change is the case the insets have to follow, and both
    // change the view's size
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

    // the web view's size rather than the reader's
    private func webViewSize() -> CGSize {
        book?.renderer?.webView.bounds.size ?? .zero
    }

    // the page list is asked for the way every other reader asks for it, since the archive is known
    // only to the source: this reader differs from its siblings in showing a whole book rather than
    // those pages, not in where it learns what the chapter is
    private enum ChapterContent {
        // the .epub every spine document of the chapter lives inside
        case epub(URL)
        // not an epub at all, carrying its pages for the host to route
        case pages([Page])
        // describes a chapter the reader has already left, so nothing the caller should act on
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
        // The chapter is captured before the fetch and checked again after it. `getPages` suspends,
        // and cancellation is cooperative, so the task a chapter change cancelled still resumes
        // here, after `setChapter` has cleared the cache for the chapter now open. Writing then
        // caches the archive of the chapter being left, and whichever read of the cache comes next
        // opens the wrong book: the settings rebuild swaps the book out mid-read, and a stale write
        // that lands before the new task's first read opens it outright, which is what the doc
        // comment on `bookURL` describes the cost of.
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

    // opens the book and shows the page the reader left off at
    private func open(startPage: Int) async {
        let bookURL: URL
        switch await chapterContent() {
            case let .epub(url):
                bookURL = url
            case let .pages(pages):
                // A chapter whose content is not an ePub is handed over as it stands rather than
                // reported as a failure: the host reads a page list to decide which reader shows a
                // chapter, so this is how the ePub reader is replaced by the one the new chapter
                // belongs to. An empty list is a chapter that could not be read at all, which the
                // host shows its failure alert for.
                delegate?.setPages(pages)
                return
            case .superseded:
                return
        }
        guard !Task.isCancelled else { return }

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
        book.onLink = { [weak self] path, fragment in
            guard let self else { return }
            // Recorded before the jump rather than after it: the host's tap zone fires a few
            // hundred milliseconds later and would otherwise turn a page on top of the jump.
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

        // Held before the book is opened rather than asked for after it. Opening counts the first
        // document, and that count is reported: a report published between the open and the resume
        // describes the head of the book, which the host then takes as the reader's position, and a
        // close before the resume settles saves page 1 over the progress being resumed to. The total
        // still climbs throughout, since `report` publishes it above the guard that withholds a
        // position.
        if startPage > 1 {
            book.holdBookPage(startPage - 1)
            // A fresh open refines its page-number landing by the saved fraction through the same
            // route a settings reload does: the saved page belongs to the viewport that counted
            // it, so on any other screen it names the wrong text. Never over an anchor a settings
            // reload already holds, which describes this session rather than the last one.
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

        // Placed now if the counts already reach it, and retried by `report` as they land if not.
        await book.showPendingBookPage()

        report()
    }

    // ReaderPagedTextViewController.loadReadingProgress is the sibling: both readers reflow, so
    // both persist a fraction alongside the page number and resume from the fraction
    private func savedScrollPosition() async -> Double? {
        guard let chapterKey = chapter?.key else { return nil }
        let chapterId = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapterKey)
        return await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getHistory(chapterId: chapterId, context: context)?
                .scrollPosition?.doubleValue
        }
    }

    // while it is, the position reported describes the head of the book rather than the reader.
    // reporting it is right, since the toolbar has nothing else to show; writing it is not, since it
    // saves page 1 over the very progress being resumed to, so the host asks before it persists
    var isAwaitingResume: Bool {
        book?.pendingBookPage != nil
    }

    // the total is not withheld while the slider is dragged: it is a label, and setPages only
    // updates the page count text, while the thumb is moved by setCurrentPage, which is where the
    // guard belongs. withholding it froze a book's total at whatever it held when a drag began,
    // for the rest of the book, whenever the flag outlived the drag by any route
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
        // waiting on have landed. A restore, so it does not count as the reader taking over: this
        // fires during the very rebuild whose anchor is still waiting to be refined below.
        if book.canShowPendingBookPage {
            navigate(isRestore: true) { await $0.showPendingBookPage() }
        }

        // A rebuild's page-number landing is refined onto the place the reader actually left once
        // the new layout is finished being counted, which is the first moment a fraction can be
        // turned back into a page.
        //
        // Both anchors restore to the page *containing* the place — floor, not the nearest
        // boundary; rounding sent an iPhone position from the right half of an iPad spread onto
        // the spread after it. The epsilon keeps an edge-anchored fraction, which lands exactly on
        // a page boundary, from flooring into the page before it: a scroll offset comes back a few
        // pixels under what was set (the browser rounds `scrollTo`), so the margin is a hundredth
        // of a page — half a line — rather than float dust, which one pixel already exceeds.
        //
        // The scroll-mode landing is refined onto the exact fraction after the page lands it in
        // the right document: a scroll viewport can rest anywhere, and resting it on the page
        // boundary instead — which sits *before* the anchor, that being what floor means — walked
        // every paged → scroll → paged round trip one page back: the switch back floored a second
        // time from the already-behind boundary. `showEdge` is why this navigates even when the
        // coarse landing already sits on the target page.
        //
        // The anchor is kept rather than consumed, and applies again whenever its document's count
        // has changed since it last did; see `settingsReloadAnchorAppliedCount`. Only the page
        // number and the book fraction are cleared, so a later reload re-seeds instead of reusing
        // them.
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

    // the toolbar takes its total from the number of pages it holds, so a book's length reaches it
    // as pages, as the paged text reader does once it has paginated. they carry the archive they
    // came out of, so isEpubPage is true of what the reader reports and the host routes it correctly
    private func placeholderPages(count: Int) -> [Page] {
        guard count > 0 else { return [] }
        let sourceId = source?.key ?? manga.sourceKey
        let chapterId = chapter?.key ?? ""
        let archive = bookURL?.absoluteString
        return (0..<count).map { index in
            Page(sourceId: sourceId, chapterId: chapterId, index: index, zipURL: archive)
        }
    }

    // one navigation at a time, holding at most one more behind it: dropping a tap that arrives
    // during a load makes quick paging feel broken, and queuing every tap makes a burst of ten
    // replay as ten turns after the fact, so a third tap replaces the one waiting.
    //
    // isRestore separates a move the reader asked for from one made on their behalf during a
    // rebuild. only the former may drop the anchor the rebuild is restoring to, and getting it
    // wrong is silent: the restore still runs, and still lands on the wrong page
    private func navigate(isRestore: Bool = false, _ work: @escaping (ReaderEpubViewModel) async -> Void) {
        if !isRestore {
            // The reader has taken over from wherever a rebuild was restoring them to.
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
                // The queued turn continues the same navigation, so the position stays withheld
                // until the last of them has settled rather than surfacing between them.
                pendingMove = nil
                navigate(isRestore: pendingMoveIsRestore, next)
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

// MARK: - Returning from a jump

extension ReaderEpubViewController {
    // called before the jump, since afterwards the page it would return to is the destination. the
    // page number reaches the reader as the button's accessibility label rather than as a title,
    // since a corner button that grew with it would cover a different amount of text in each book
    func offerReturn() {
        guard let book, let page = book.bookPage else { return }
        returnBookPage = page
        // The same mid-page fraction every other anchor in this reader carries, withheld until
        // measured by `progression` itself.
        returnPosition = book.progression
        returnButton.accessibilityLabel = String(
            format: NSLocalizedString("BACK_TO_PAGE_X", comment: ""),
            page + 1
        )
        // The web view is added when a book opens, which is after this button, so it would
        // otherwise sit above it.
        view.bringSubviewToFront(returnButton)
        // Ahead of the guard below: a second jump while the offer is up replaces where it leads,
        // so it restarts the countdown rather than inheriting what is left of the first one.
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
            // The page containing the place, same as the restore in `report`.
            return min(Int(returnPosition * Double(book.bookTotal) + 0.01), book.bookTotal - 1)
        }
        return returnBookPage
    }

    // only an offer held as a bare page number, made before the book finished being measured:
    // taking the reader to a page of a layout that no longer exists is worse than not offering
    func withdrawUnanchoredReturnOffer() {
        guard returnBookPage != nil, returnPosition == nil else { return }
        hideReturnOffer()
    }

    // whether it was taken, invalidated, or simply ran out
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

    // the contents are parsed as the book is opened, so an open book has read whatever it has
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
        turn(forward: false)
    }

    func moveRight() {
        turn(forward: true)
    }

    // consumed either way, since a tap late enough to be an intent of its own has also proved the
    // link before it is no longer the last thing that happened. asked by the host rather than acted
    // on inside moveLeft/moveRight, so it covers the bars toggling as well as the page turning, and
    // covers nothing else: a keypress and a swipe never pass through the host's tap handling
    func consumesTap() -> Bool {
        guard let suppressedPageTurnAt else { return false }
        self.suppressedPageTurnAt = nil
        return Date().timeIntervalSince(suppressedPageTurnAt) < Self.suppressedPageTurnWindow
    }

    // a page turn, whichever gesture or key asked for it
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

    // left set, the flag stops the toolbar being told where the reader is. sliderStopped clears it,
    // but that depends on a single callback arriving and a cancelled touch does not send one, so a
    // page turn, which proves no drag is in progress, heals the state instead
    private func endSliding() {
        guard isSliding else { return }
        isSliding = false
        report()
    }

    // dragging across a book of several thousand pages crosses many spine documents, and loading
    // each one it passes over would make the slider unusable, so the book moves once the thumb stops
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
        // The page the offer names belongs to the book being left.
        hideReturnOffer()
        // The archive belonged to the chapter being left, so it is resolved again for this one.
        bookURL = nil
        settingsReloadPage = nil
        settingsReloadPosition = nil
        settingsReloadAnchor = nil
        settingsReloadAnchorAppliedCount = nil
        // The book being left goes with the chapter it belonged to.
        tearDownBook()
        openTask = Task { [weak self] in
            await self?.open(startPage: startPage)
        }
    }

    // value is a fraction of the whole book, matching the index / (count - 1) convention the
    // toolbar and both text readers already use
    private func bookPage(for value: CGFloat) -> Int {
        let last = max(reportedTotal - 1, 0)
        return min(max(Int((value * CGFloat(last)).rounded()), 0), last)
    }
}

// MARK: - Image Preview

// fullscreen viewer for one image of the book: pinch and double-tap zoom via ZoomableScrollView,
// a single tap or the close button dismisses
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

    // so only a genuine size change, a rotation, re-fits and resets the zoom, rather than a layout
    // pass firing while the reader is pinching
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

// fullscreen viewer for one table, at its natural size inside a web view that scrolls both axes
// and pinch-zooms
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

    // a plain shell of its own: the book's stylesheets are not carried over, and the scale the
    // injection script left inline is undone. user-scalable, so a pinch zooms the way the book
    // itself deliberately cannot
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
