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

    /// The `.epub` every spine document of the open chapter lives inside.
    ///
    /// Resolved from the chapter's own page list rather than fixed when the reader is built, and
    /// held only until the chapter changes. A manga folder may hold several epubs, one chapter
    /// each, so the archive belongs to the chapter rather than to the reader: a reader that kept
    /// the archive it was born with reopened the first book on a chapter change while the host
    /// marked the second read and, with `Library.deleteDownloadAfterReading`, deleted it.
    ///
    /// Cached so that reopening the same chapter, which a settings change does, costs no fetch.
    private var bookURL: URL?

    /// An archive supplied by the host instead of one resolved from the chapter's pages.
    ///
    /// For a host that has a file and no source to ask for a page list, which is the debug host
    /// opening a book straight from the documents directory. Used for every chapter, which is
    /// correct only because such a host never changes chapter. The shipping host leaves it nil.
    private let providedBookURL: URL?

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

    /// When something in the reader last handled a tap itself, so the page turn the same tap
    /// produces in the host is not also performed.
    ///
    /// The tap zones sit over the web view and do not cancel its touches, which is what lets the
    /// document keep text selection and links at all. One tap therefore reaches both: WebKit
    /// activates a link, or the return button fires, and the host's tap zone asks for a page turn
    /// besides. The reader's own handling is the earlier of the two, since the host's single tap
    /// waits for its double tap to fail, so the turn is the one that can be suppressed.
    private var suppressedPageTurnAt: Date?

    /// How long after that a page turn is taken to belong to the same tap.
    ///
    /// Longer than the double-tap failure the host's single tap waits on, and short enough that a
    /// reader who follows a link and then deliberately taps to turn is not ignored.
    private static let suppressedPageTurnWindow: TimeInterval = 0.75

    /// The book page a jump left, offered back to the reader while `returnButton` is showing.
    private var returnBookPage: Int?

    /// The same place as a fraction of the whole book, which is what survives the book being laid
    /// out again.
    ///
    /// A page index is not a position: re-fragmenting moves text between pages, so the page number
    /// captured before a jump names somewhere else entirely after a rotation or a change of font
    /// size, by a margin that grows with depth. The fraction is only available once the book has
    /// been measured, since a total that is still a lower bound would place it too far in, so the
    /// page number carries the offer until then and `withdrawUnanchoredReturnOffer` takes it away
    /// if the layout changes first.
    private var returnPosition: Double?

    /// The offer to go back to where a jump was made from.
    ///
    /// A footnote is the case that needs it: the link takes the reader across the book, and the only
    /// other way back is the slider, which does not know where they were.
    ///
    /// Shaped after the readers that have solved this. Apple Books and Play Books both show a small
    /// opaque circle in a bottom corner; Kindle shows a pill with the page number in it. Two
    /// properties are common to all of them and each was got wrong first time: it is **opaque**, so
    /// it is legible over text rather than showing it through, and it is **cornered**, so it covers
    /// as little of the page as possible.
    ///
    /// Where they were followed and should not have been is how long it stays: they leave it until
    /// it is used, and in use here that was intrusive, so it expires. See `returnOfferLifetime`.
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

    /// A full touch target, which the icon alone is not.
    private static let returnButtonDiameter: CGFloat = 44

    /// How long the offer stands before it withdraws itself.
    ///
    /// The readers this was shaped after leave it until it is used, and that is what shipped first.
    /// Measured against the real thing that was wrong: a jump is a moment, and a control that
    /// outlives it by the rest of the chapter is in the corner of every page the reader turns. Five
    /// seconds covers the glance that follows an unexpected arrival without becoming furniture.
    private static let returnOfferLifetime: TimeInterval = 5

    /// The withdrawal `returnOfferLifetime` schedules, cancelled if the offer goes before it fires.
    private var returnOfferTask: Task<Void, Never>?

    /// The return button's distance from the bottom of the view.
    ///
    /// Held so it can be kept at the **window's** safe area rather than the view's. The view's
    /// insets include the bars and change when they toggle, and a control that moves between a
    /// touch going down and coming up never reports the touch at all: the first version was pinned
    /// to `view.safeAreaLayoutGuide` and every tap on it toggled the bars, which relaid it out from
    /// under the finger. It read as a button that did nothing. `applySafeArea` already avoids this
    /// for the web view and for the same reason.
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

    /// The debounced rebuild a settings change schedules; see `scheduleSettingsReload`.
    private var settingsReloadTask: Task<Void, Never>?

    override func observe() {
        // The text readers' settings apply to epubs too. They are baked into the renderer's
        // injection script and into every measured page count, so a change invalidates all of it;
        // rebuilding through `open` reuses the path a fresh open already exercises. Debounced
        // because the steppers in the settings sheet post once per tick.
        for key in [
            "Reader.epubReaderStyle", "Reader.textFontFamily", "Reader.textFontSize",
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
        withdrawUnanchoredReturnOffer()
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

    /// Shows a fullscreen preview when a tap landed on an image of the book, and reports whether
    /// it did, so the host runs its tap zones only for taps that hit no image.
    ///
    /// `point` is in this controller's view coordinates.
    func presentImagePreview(forTapAt point: CGPoint) async -> Bool {
        guard let book, let webView = book.renderer?.webView else { return false }
        let clientPoint = view.convert(point, to: webView)
        guard
            webView.bounds.contains(clientPoint),
            let data = await book.imageData(at: clientPoint),
            let image = UIImage(data: data)
        else { return false }
        present(EpubImagePreviewController(image: image), animated: true)
        return true
    }

    /// Tears the book down and opens it again at the same place, picking up the current settings.
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

    /// Takes the open book out of the reader, leaving it ready for `open` to build another.
    ///
    /// The web view is a subview and the counts it produced are in the toolbar, so a book that is
    /// being replaced has to be removed rather than merely dropped: `install` adds a web view
    /// without taking the previous one out, and a total is only rewritten when it changes.
    private func tearDownBook() {
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

    /// Places the return button in the leading bottom corner, where it covers the least text.
    ///
    /// Its distance from the bottom is set in `applySafeArea`, from the window's insets, so that
    /// showing or hiding the bars does not move it.
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

    /// How far the return button sits from the leading edge and from the safe area below it.
    ///
    /// Clear of the toolbar in both bar states, since the button appears in both: from the contents
    /// sheet, which is opened from a visible bar, and from a link tapped while reading with the bars
    /// hidden. Overlapping the toolbar would be cosmetic; moving to avoid it would not be.
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

    /// The size the document is laid out at, which is the web view's rather than the reader's.
    private func webViewSize() -> CGSize {
        book?.renderer?.webView.bounds.size ?? .zero
    }

    /// The archive the open chapter lives in, loaded once per chapter.
    ///
    /// The page list is asked for the way every other reader asks for it, since the archive is
    /// known only to the source: the ePub reader differs from its siblings in showing a whole book
    /// rather than those pages, not in where it learns what the chapter is.
    ///
    /// What the chapter being opened turned out to hold.
    private enum ChapterContent {
        /// The `.epub` every spine document of the chapter lives inside.
        case epub(URL)
        /// A chapter that is not an ePub at all, carrying its pages for the host to route.
        case pages([Page])
        /// An answer that describes a chapter the reader has already left, and so describes
        /// nothing the caller should act on.
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

    /// Opens the book and shows the page the reader left off at.
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

    /// Whether the reader is still being taken to the page the book was opened at.
    ///
    /// While it is, the position this reader reports describes the head of the book rather than the
    /// reader: the first page is what is on screen, and the page being resumed to is waiting for the
    /// counts that place it. Reporting it is right, because the toolbar has nothing else to show and
    /// a bar with no numbers reads as a book that has hung. Writing it is not: it saves page 1 over
    /// the very progress being resumed to. The host asks this before it persists a position.
    var isAwaitingResume: Bool {
        book?.pendingBookPage != nil
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
        // waiting on have landed. A restore, so it does not count as the reader taking over: this
        // fires during the very rebuild whose anchor is still waiting to be refined below.
        if book.canShowPendingBookPage {
            navigate(isRestore: true) { await $0.showPendingBookPage() }
        }

        // A rebuild's page-number landing is refined onto the place the reader actually left once the
        // new layout is finished being counted, which is the first moment the fraction can be turned
        // back into a page. Cleared first, so nothing downstream sees it as still pending, and only
        // while the reader has not moved themselves: `navigate` drops it precisely then.
        if book.isMeasured, let position = settingsReloadPosition, book.bookTotal > 1 {
            settingsReloadPosition = nil
            settingsReloadPage = nil
            let target = Int((position * Double(book.bookTotal - 1)).rounded())
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

    /// The toolbar takes its total from the number of pages it holds, so a book's length reaches it
    /// as pages.
    ///
    /// The paged text reader does the same once it has paginated, for the same reason: a reflowable
    /// document's page count is not known until it has been laid out, so the reader supplies it
    /// rather than the source.
    /// They carry the archive they came out of, so `isEpubPage` is true of what the reader reports.
    /// The host routes a page list by its content, and a page list that does not say it is an ePub
    /// takes a branch meant for something else.
    private func placeholderPages(count: Int) -> [Page] {
        guard count > 0 else { return [] }
        let sourceId = source?.key ?? manga.sourceKey
        let chapterId = chapter?.key ?? ""
        let archive = bookURL?.absoluteString
        return (0..<count).map { index in
            Page(sourceId: sourceId, chapterId: chapterId, index: index, zipURL: archive)
        }
    }

    /// Runs one navigation at a time, holding at most one more behind it.
    ///
    /// A turn crossing into another spine document has to load one, which takes long enough for a
    /// second tap to arrive during it. Dropping that tap outright makes quick paging feel broken;
    /// queuing every tap makes a burst of ten replay as ten turns after the fact. One slot gives
    /// the responsiveness without the replay, and a third tap replaces the one waiting rather than
    /// joining it.
    /// `isRestore` distinguishes a move the reader asked for from one made on their behalf while a
    /// book is being reopened. Only the former means they have taken over from where a rebuild was
    /// putting them, and only the former may therefore drop the anchor the rebuild is restoring to.
    /// Getting this wrong is silent: the restore still runs, and still lands on the wrong page.
    private func navigate(isRestore: Bool = false, _ work: @escaping (ReaderEpubViewModel) async -> Void) {
        if !isRestore {
            // The reader has taken over from wherever a rebuild was restoring them to.
            settingsReloadPage = nil
            settingsReloadPosition = nil
        }
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

// MARK: - Returning from a jump

extension ReaderEpubViewController {
    /// Remembers where the reader is and offers to bring them back.
    ///
    /// Called before the jump, since afterwards the page it would return to is the destination. A
    /// place the index cannot name yet is not offered: the offer is a book page, and one that
    /// cannot be named cannot be returned to either.
    ///
    /// The page number reaches the reader as the button's accessibility label rather than as a
    /// title. An icon alone is what the readers that solved this show, and a corner button that
    /// grows with the page number would cover a different amount of text at each end of a book.
    func offerReturn() {
        guard let book, let page = book.bookPage else { return }
        returnBookPage = page
        returnPosition = book.isMeasured && book.bookTotal > 1
            ? Double(page) / Double(book.bookTotal - 1)
            : nil
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

    /// The book page to return to, resolved against the layout as it stands now rather than the one
    /// the offer was made in.
    private var returnTarget: Int? {
        if let returnPosition, let book, book.isMeasured, book.bookTotal > 1 {
            return Int((returnPosition * Double(book.bookTotal - 1)).rounded())
        }
        return returnBookPage
    }

    /// Withdraws an offer that the book being laid out again has invalidated.
    ///
    /// Only one held as a bare page number, which is an offer made before the book finished being
    /// measured. Taking the reader to a page of a layout that no longer exists is worse than not
    /// offering to take them anywhere.
    func withdrawUnanchoredReturnOffer() {
        guard returnBookPage != nil, returnPosition == nil else { return }
        hideReturnOffer()
    }

    /// Withdraws the offer, whether it was taken, invalidated, or simply ran out.
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

    /// The contents are parsed as the book is opened, so an open book has read whatever it has.
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

    /// True when the tap arriving now is the one that just followed a link.
    ///
    /// Consumed either way: a tap that arrives late enough to be an intent of its own has also
    /// proved that the link before it is no longer the last thing that happened.
    ///
    /// Asked by the host rather than acted on inside `moveLeft`/`moveRight`, so that it covers
    /// everything one tap would otherwise do — the bars toggling as well as the page turning — and
    /// so that it covers nothing else: a keypress and a swipe do not pass through the host's tap
    /// handling and are never suppressed by it.
    func consumesTap() -> Bool {
        guard let suppressedPageTurnAt else { return false }
        self.suppressedPageTurnAt = nil
        return Date().timeIntervalSince(suppressedPageTurnAt) < Self.suppressedPageTurnWindow
    }

    /// A page turn, whichever gesture or key asked for it.
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
        // The page the offer names belongs to the book being left.
        hideReturnOffer()
        // The archive belonged to the chapter being left, so it is resolved again for this one.
        bookURL = nil
        settingsReloadPage = nil
        settingsReloadPosition = nil
        // The book being left goes with the chapter it belonged to.
        tearDownBook()
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

// MARK: - Image Preview

/// Fullscreen viewer for one image of the book: pinch and double-tap zoom via
/// `ZoomableScrollView`, a single tap or the close button dismisses.
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

    /// The size the image was last fitted to, so only a genuine size change (a rotation) re-fits
    /// and resets the zoom — not a layout pass that fires while the reader is pinching.
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
