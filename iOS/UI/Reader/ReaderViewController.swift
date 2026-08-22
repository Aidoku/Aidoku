//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import AidokuRunner
import SafariServices
import SwiftUI
import UIKit

class ReaderViewController: BaseObservingViewController {
    enum Reader {
        case paged
        case scroll
        case text
        /// Chosen by inference from page content, as `text` is, rather than by the reading-mode
        /// picker. Those entries are directional layout for images and an ePub entry among them
        /// would be selectable for manga, where it means nothing.
        case epub
    }

    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    var chapter: AidokuRunner.Chapter
    var pages: [Page] = []
    var readingMode: ReadingMode = .rtl
    var defaultReadingMode: ReadingMode?
    private var tapZone: TapZone?

    private var chapterList: [AidokuRunner.Chapter]
    private var chaptersToMark: [AidokuRunner.Chapter] = []
    private var chaptersToRemoveDownload: [AidokuRunner.Chapter] = [] {
        didSet {
            // ensure chapters queued for deletion are persistent, in case of app termination
            if chaptersToRemoveDownload.isEmpty {
                UserDefaults.standard.removeObject(forKey: "Data.chaptersToBeDeleted")
            } else {
                let data = try? JSONEncoder().encode(chaptersToRemoveDownload.map {
                    ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
                })
                UserDefaults.standard.set(data, forKey: "Data.chaptersToBeDeleted")
            }
        }
    }
    private var forceStartPage: Int?
    private var currentPage = 1
    private var currentPosition: Double?
    private var sessionReadPages: Set<Int> = []
    private var sessionStartDate: Date?
    private var sessionLastInteraction: Date?

    weak var reader: ReaderReaderDelegate?

    // Dictionary popup state
    private lazy var dictionaryCoordinator = ReaderDictionaryCoordinator(owner: self)
    private var _dictionaryLongPressSelection: Any?
    @available(iOS 18.0, *)
    private var dictionaryLongPressSelection: TextRecognizer.Result? {
        get { _dictionaryLongPressSelection as? TextRecognizer.Result }
        set { _dictionaryLongPressSelection = newValue }
    }
    private var isDictionaryOCRActiveForCurrentChapter: Bool {
        AppSettings.dictionary.isOCREnabled(language: chapter.language ?? source?.languages.first)
    }
    private var isDictionarySingleTapLookupActiveForCurrentChapter: Bool {
        AppSettings.dictionary.lookupGesture.get() == .singleTap && isDictionaryOCRActiveForCurrentChapter
    }
    private var isDictionaryLongPressLookupActiveForCurrentChapter: Bool {
        AppSettings.dictionary.lookupGesture.get() == .longPress && isDictionaryOCRActiveForCurrentChapter
    }

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var toolbarView = ReaderToolbarView()
    private var toolbarViewWidthConstraint: NSLayoutConstraint?

    private var squeezeTimer: Timer?
    private var longSqueezeTimer: Timer?
    private var squeezeStartTime: Date?
    private let doubleSqueezeInterval: TimeInterval = 0.3
    private let longSqueezeThreshold: TimeInterval = 0.5

    private lazy var autoScrollButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = .secondarySystemBackground
            configuration.baseForegroundColor = .label
        }
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: "play.fill")
        configuration.contentInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10)

        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(toggleAutoScroll), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    private lazy var descriptionButtonController: UIHostingController<ReaderPageDescriptionButtonView> = {
        let buttonView = ReaderPageDescriptionButtonView(source: source, pages: [])
        let hostingController = UIHostingController(rootView: buttonView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.alpha = 0
        hostingController.view.isHidden = true
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingController
    }()
    private lazy var descriptionTrailingConstraint =
        descriptionButtonController.view.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: -16
        )
    private lazy var descriptionTrailingToAutoScrollConstraint =
        descriptionButtonController.view.trailingAnchor.constraint(
            equalTo: autoScrollButton.leadingAnchor,
            constant: -16
        )

    /// What the bar items were last built for, so they are rebuilt only when one of those answers
    /// changes.
    ///
    /// The ePub reader reports a new total for every spine document the measurement pass counts,
    /// which is 217 calls in five seconds on the largest book in the corpus. Rebuilding the items
    /// each time replaced the very `UIBarButtonItem` a finger was resting on, so its action never
    /// fired and the button read as dead for the whole of pagination.
    private struct BarButtonState: Equatable {
        let hostsContents: Bool
        let contentsRead: Bool
        let web: Bool
    }

    private var builtBarState: BarButtonState?

    /// The chapter-list button, held so that it can be disabled while contents are being read.
    private var chapterListButton: UIBarButtonItem?

    private var barToggleTapGesture: UITapGestureRecognizer?
    private var barToggleSecondaryTapGesture: UITapGestureRecognizer?
    private var barDismissNavigationBarTapGesture: UITapGestureRecognizer?
    private var dictionaryLongPressGesture: UILongPressGestureRecognizer?

    var statusBarHidden = false

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        UIStatusBarAnimation.fade
    }
    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }
    override var prefersHomeIndicatorAutoHidden: Bool {
        statusBarHidden
    }

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter,
        startPage: Int? = nil
    ) {
        self.source = source
        self.manga = manga
        self.chapter = chapter
        self.chapterList = manga.chapters ?? []
        self.chaptersToMark = [chapter]
        self.defaultReadingMode = switch manga.viewer {
            case .rightToLeft: .rtl
            case .leftToRight: .ltr
            case .vertical: .vertical
            case .webtoon: .webtoon
            case .unknown: .none
        }
        self.forceStartPage = startPage
        super.init()
    }

    override func configure() {
        node.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        // navbar buttons
        let chapterListButton = UIBarButtonItem(
            image: UIImage(systemName: "list.bullet"),
            style: .plain,
            target: self,
            action: #selector(openContents)
        )
        self.chapterListButton = chapterListButton
        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(close)
            ),
            chapterListButton
        ]
        updateBarButtonItems()

        // fix navbar being clear
        let navigationBarAppearance = UINavigationBarAppearance()
        let toolbarAppearance = UIToolbarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        toolbarAppearance.configureWithDefaultBackground()
        navigationController?.navigationBar.standardAppearance = navigationBarAppearance
        navigationController?.navigationBar.compactAppearance = navigationBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navigationBarAppearance
        navigationController?.toolbar.standardAppearance = toolbarAppearance
        navigationController?.toolbar.compactAppearance = toolbarAppearance
        if #available(iOS 15.0, *) {
            navigationController?.toolbar.scrollEdgeAppearance = toolbarAppearance
        }

        loadNavbarTitle()

        // toolbar view
        toolbarView.sliderView.addTarget(self, action: #selector(sliderMoved(_:)), for: .valueChanged)
        toolbarView.sliderView.addTarget(self, action: #selector(sliderStopped(_:)), for: .editingDidEnd)
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        let toolbarButtonItemView = UIBarButtonItem(customView: toolbarView)
        toolbarButtonItemView.customView?.heightAnchor.constraint(equalToConstant: 40).isActive = true
        if #available(iOS 26.0, *) {
            toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(
                equalToConstant: node.bounds.width - 32 - 10
            )
            // shift down farther to account for different toolbar and slider knob size
            toolbarButtonItemView.customView?.transform = CGAffineTransform(translationX: 0, y: -5)
        } else {
            toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(equalToConstant: view.bounds.width)
            toolbarButtonItemView.customView?.transform = CGAffineTransform(translationX: 0, y: -10)
        }

        add(child: descriptionButtonController)
        view.addSubview(autoScrollButton)

        toolbarItems = [toolbarButtonItemView]
        navigationController?.isToolbarHidden = false
        navigationController?.toolbar.fitContentViewToToolbar()

        // loading indicator
        activityIndicator.startAnimating()
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        // initialize dictionary engine
        if
            #available(iOS 18.0, *),
            AppSettings.dictionary.enable.get()
                {
            DictionaryManager.shared.rebuildLookupQuery()
        }
        configureDictionaryLookupGesture()
        configureDictionaryOverlayInteractionMode()

        // bar toggle tap gesture
        configureBarToggleTapGestures()

        // page offset tap gesture
        let pageOffsetGesture = UITapGestureRecognizer(target: self, action: #selector(toggleOffset))
        pageOffsetGesture.numberOfTouchesRequired = 2
        pageOffsetGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(pageOffsetGesture)

        // set reader
        let readingModeKey = "Reader.readingMode.\(manga.identifier)"
        UserDefaults.standard.register(defaults: [readingModeKey: "default"])
        setReadingMode(UserDefaults.standard.string(forKey: readingModeKey))

        // set up apple pencil squeeze handler
        if #available(iOS 17.5, *) {
            let pencilInteraction = UIPencilInteraction(delegate: self)
            view.addInteraction(pencilInteraction)
        }

        // load current tap zone
        updateTapZone()

        // load chapter list
        loadCurrentChapter()
    }

    override func constrain() {
        toolbarViewWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            descriptionButtonController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            autoScrollButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            autoScrollButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        updateAutoScrollButton()
    }

    override func observe() {
        addObserver(forName: "Reader.readingMode.\(manga.identifier)") { [weak self] _ in
            guard let self else { return }
            self.setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode.\(self.manga.identifier)"))
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
            // if the tap zone is auto, it will changed based on the current reader
            self.updateTapZone()
        }
        addObserver(forName: "Reader.disableDoubleTap") { [weak self] _ in
            self?.configureBarToggleTapGestures()
        }
        addObserver(forName: "Reader.autoScroll") { [weak self] _ in
            self?.updateAutoScrollButton()
        }
        addObserver(forName: .readerTapZones) { [weak self] _ in
            self?.updateTapZone()
        }
        let reloadBlock: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        // reload pages when processors change
        addObserver(forName: "Reader.downsampleImages", using: reloadBlock)
        addObserver(forName: "Reader.upscaleImages", using: reloadBlock)
        addObserver(forName: "Reader.cropBorders", using: reloadBlock)
        addObserver(forName: "Reader.liveText", using: reloadBlock)
        addObserver(forName: AppSettings.dictionary.overlayPadding.key, using: reloadBlock)
        addObserver(forName: AppSettings.dictionary.overlayTextScaleMultiplier.key, using: reloadBlock)
        let dictionaryReloadBlock: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.configureBarToggleTapGestures()
            self.configureDictionaryLookupGesture()
            self.configureDictionaryOverlayInteractionMode()
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        for key in [
            AppSettings.dictionary.enable.key,
            AppSettings.dictionary.lookupGesture.key,
            AppSettings.dictionary.textOverlayMode.key,
            AppSettings.dictionary.restrictOCRLanguages.key,
            AppSettings.dictionary.restrictedOCRLanguages.key
        ] {
            addObserver(forName: key, using: dictionaryReloadBlock)
        }
        addObserver(forName: .dictionaryDictionariesChanged, using: dictionaryReloadBlock)
        // Switch text reader style (paged <-> scroll) without restart
        addObserver(forName: "Reader.textReaderStyle") { [weak self] _ in
            guard let self else { return }
            // Only switch if we're currently in a text reader
            if self.reader is ReaderTextViewController || self.reader is ReaderPagedTextViewController {
                // Save current position before switching so the new reader can restore it
                Task {
                    await self.updateReadPosition()
                    await MainActor.run {
                        self.setReader(.text)
                        self.reader?.setChapter(self.chapter, startPage: self.currentPage)
                        self.updateTapZone()
                    }
                }
            }
        }
        addObserver(forName: UIScene.willDeactivateNotification) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.updateReadPosition()
            }

            if #available(iOS 26.0, *) {
                statusBarHidden = false
            }
        }
        addObserver(forName: UIScene.didActivateNotification) { [weak self] _ in
            guard let self else { return }
            if self.sessionStartDate == nil {
                self.sessionReadPages = [self.currentPage]
                self.sessionStartDate = Date.now
                self.sessionLastInteraction = nil
            }
        }
        if #available(iOS 26.0, *) {
            addObserver(forName: UIScene.willEnterForegroundNotification) { [weak self] _ in
                if self?.navigationController?.toolbar.alpha == 0 {
                    self?.hideBars()
                }
            }
        }
        addObserver(forName: "Reader.autoScroll") { [weak self] _ in
            self?.updateAutoScrollButton()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        sessionReadPages = [self.currentPage]
        sessionStartDate = Date.now
        sessionLastInteraction = nil

        if navigationController?.toolbar.alpha == 0 {
            hideBars()
        }

        // there's a bug on ios 15 where the toolbar just disappears when adding a child hosting controller
        navigationController?.isToolbarHidden = false
        navigationController?.toolbar.alpha = 1

        disableSwipeGestures()
        configureNavigationBarDismissTapGesture(enabled: isDictionarySingleTapLookupActiveForCurrentChapter)

        // resume auto scroll if it was paused when presenting a sheet
        if let reader = reader as? ReaderWebtoonViewController {
            reader.resumeAutoScroll()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()

        if !chaptersToRemoveDownload.isEmpty {
            Task {
                await DownloadManager.shared.delete(chapters: chaptersToRemoveDownload.map {
                    .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
                })
                chaptersToRemoveDownload = []
            }
        }

        guard currentPage >= 1 else { return }
        Task {
            await updateReadPosition()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            if #available(iOS 26.0, *) {
                self.toolbarViewWidthConstraint?.constant = size.width - 32 - 10
            } else {
                self.toolbarViewWidthConstraint?.constant = size.width
            }
        }
    }
}

extension ReaderViewController {
    func disableSwipeGestures() {
        let isVerticalReader = reader is ReaderWebtoonViewController || readingMode == .vertical

        // the view with the target gesture recognizers changes based on if it was presented from uikit or swiftui
        let gestureRecognizers = (parent?.view.gestureRecognizers ?? []) + (parent?.view.superview?.superview?.gestureRecognizers ?? [])

        for recognizer in gestureRecognizers {
            switch String(describing: type(of: recognizer)) {
                case "_UIParallaxTransitionPanGestureRecognizer": // swipe edge gesture
                    recognizer.isEnabled = isVerticalReader

                case "_UIContentSwipeDismissGestureRecognizer": // swipe down gesture
                    recognizer.isEnabled = !isVerticalReader
                    recognizer.delegate = self // ensure gesture only activates on swipe down, not swipe right

//                case "_UITransformGestureRecognizer": // pinch gesture
//                    recognizer.isEnabled = true

                default:
                    break
            }
        }
    }

    func updateReadPosition(
        currentPage: Int? = nil,
        totalPages: Int? = nil,
        chapter: AidokuRunner.Chapter? = nil
    ) async {
        let effectiveTotalPages = totalPages ?? toolbarView.totalPages ?? 0
        let effectiveCurrentPage = currentPage ?? self.currentPage

        guard
            !UserDefaults.standard.bool(forKey: "General.incognitoMode"),
            effectiveTotalPages > 0 // ensure chapter pages are loaded
        else {
            return
        }

        // An epub still being taken to the page it was opened at is showing the head of the book,
        // and reports that so the toolbar has numbers to display while the spine is counted. It is
        // not where the reader is, and writing it saves page 1 over the progress being resumed to.
        // The sibling of the guard in `setCompleted`, for the same reason: what an epub reports
        // before its counts land describes the book rather than the reader.
        if (reader as? ReaderEpubViewController)?.isAwaitingResume == true {
            return
        }

        let currentPage = effectiveCurrentPage
        let chapter = chapter ?? self.chapter

        let sourceId = manga.sourceKey
        let mangaId = manga.key
        let chapterId = chapter.key
        let (completed, progress) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.getProgress(
                sourceId: sourceId,
                mangaId: mangaId,
                chapterId: chapterId,
                context: context
            )
        }
        let hasHistory = completed || progress != nil

        // don't add history if there is none and we're at the first page
        if currentPage == 1 && !hasHistory {
            return
        }

        await HistoryManager.shared.setProgress(
            chapter: chapter.toOld(sourceId: sourceId, mangaId: mangaId),
            progress: currentPage,
            totalPages: totalPages,
            scrollPosition: currentPosition,
            completed: completed
        )
        await saveReadingSession(chapter: chapter)
    }

    private func saveReadingSession(chapter: AidokuRunner.Chapter? = nil) async {
        guard let sessionStartDate else { return }
        let pagesRead = sessionReadPages.count
        if pagesRead > 0 && sessionLastInteraction != nil {
            let chapter = chapter ?? self.chapter
            await HistoryManager.shared.addSession(
                chapterIdentifier: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key),
                data: .init(startDate: sessionStartDate, endDate: .now, pagesRead: pagesRead)
            )
        }
        self.sessionStartDate = nil
    }

    func loadChapterList() async {
        let updatedManga = try? await source?.getMangaUpdate(
            manga: manga,
            needsDetails: false,
            needsChapters: true
        )
        chapterList = updatedManga?.chapters ?? []
    }

    func loadCurrentChapter() {
        if chapterList.isEmpty {
            Task {
                await loadChapterList()
            }
        }

        if let forceStartPage {
            currentPage = forceStartPage
            self.forceStartPage = nil
        } else {
            let (completed, startPage) = CoreDataManager.shared.getProgress(
                sourceId: source?.key ?? manga.sourceKey,
                mangaId: manga.key,
                chapterId: chapter.key
            )
            if !completed, let startPage {
                currentPage = startPage
            } else {
                currentPage = -1
            }
        }
        reader?.setChapter(chapter, startPage: currentPage)
        // The contents belong to the chapter being left. Refreshed here so the button goes with it
        // rather than standing over the next chapter's load, where it opens nothing; `setPages`
        // brings it back once the new chapter has contents of its own.
        updateBarButtonItems()
    }

    func loadNavbarTitle() {
        let volume: String? =
            if chapter.chapterNumber != nil, let volumeNum = chapter.volumeNumber {
                String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNum)
            } else {
                nil
            }

        let title =
            if let chapterNum = chapter.chapterNumber {
                String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
            } else if let volumeNum = chapter.volumeNumber {
                String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNum)
            } else {
                chapter.title ?? ""
            }

        navigationItem.setTitle(upper: volume, lower: title)
    }

    func showLoadFailAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("FAILED_CHAPTER_LOAD", comment: ""),
            message: NSLocalizedString("FAILED_CHAPTER_LOAD_INFO", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    @objc func openReaderSettings() {
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()

        let currentReader: Reader
        switch reader {
            case is ReaderTextViewController, is ReaderPagedTextViewController:
                currentReader = .text
            case is ReaderPagedViewController:
                currentReader = .paged
            case is ReaderWebtoonViewController:
                currentReader = .scroll
            case is ReaderEpubViewController:
                currentReader = .epub
            default:
                currentReader = .paged
        }
        let vc = UIHostingController(
            rootView: ReaderSettingsView(
                mangaId: manga.identifier,
                reader: currentReader,
                chapterLanguage: chapter.language ?? source?.languages.first
            )
        )
        present(vc, animated: true)
    }

    @objc func openWebView() {
        guard let url = chapter.url, url.scheme == "http" || url.scheme == "https" else { return }
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()
        present(SFSafariViewController(url: url), animated: true)
    }

    @objc func openChapterList() {
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()

        var view = ReaderChapterListView(
            chapterList: chapterList,
            chapter: chapter
        )
        view.chapterSet = { [weak self] chapter in
            guard let self else { return }
            if chapter != self.chapter {
                self.setChapter(chapter)
                self.loadCurrentChapter()
            }
        }
        present(UIHostingController(rootView: view), animated: true)
    }

    @objc func close() {
        dismiss(animated: true)
    }

    @objc func sliderMoved(_ sender: ReaderSliderView) {
        reader?.sliderMoved(value: sender.currentValue)
    }
    @objc func sliderStopped(_ sender: ReaderSliderView) {
        reader?.sliderStopped(value: sender.currentValue)
    }
}

// MARK: - Reading Mode
extension ReaderViewController {
    func setReadingMode(_ mode: String?) {
        switch mode {
            case "rtl": readingMode = .rtl
            case "ltr": readingMode = .ltr
            case "vertical": readingMode = .vertical
            case "scroll", "webtoon": readingMode = .webtoon
            case "continuous": readingMode = .continuous
            case "default":
                let defaultMode = UserDefaults.standard.string(forKey: "Reader.readingMode")
                if defaultMode == "default" {
                    setReadingMode("auto")
                } else {
                    setReadingMode(defaultMode)
                }
                return
            default: // auto
                // use given default reading mode
                if let defaultReadingMode {
                    readingMode = defaultReadingMode
                } else if CoreDataManager.shared.hasManga(
                    sourceId: source?.key ?? manga.sourceKey,
                    mangaId: manga.key
                ) {
                    // fall back to stored manga viewer
                    let sourceMode = CoreDataManager.shared.getMangaSourceReadingMode(
                        sourceId: source?.key ?? manga.sourceKey,
                        mangaId: manga.key
                    )
                    if let mode = ReadingMode(rawValue: sourceMode) {
                        readingMode = mode
                    } else {
                        readingMode = .rtl
                    }
                } else {
                    // fall back to rtl reading mode
                    readingMode = .rtl
                }
        }

        if !(reader is ReaderTextViewController) {
            switch readingMode {
                case .ltr, .rtl, .vertical:
                    setReader(.paged)
                case .webtoon, .continuous:
                    setReader(.scroll)
            }
        }
    }

    @objc private func toggleAutoScroll() {
        guard let webtoonReader = reader as? ReaderWebtoonViewController else { return }
        webtoonReader.toggleAutoScroll()
    }

    private func updateAutoScrollButton() {
        let webtoonReader = reader as? ReaderWebtoonViewController
        let visible = webtoonReader != nil && UserDefaults.standard.bool(forKey: "Reader.autoScroll")

        if !visible {
            webtoonReader?.stopAutoScroll()
        }

        webtoonReader?.onAutoScrollStateChange = { [weak self] _ in
            self?.updateAutoScrollButtonIcon()
        }

        autoScrollButton.isHidden = !visible
        descriptionTrailingConstraint.isActive = !visible
        descriptionTrailingToAutoScrollConstraint.isActive = visible
        updateAutoScrollButtonIcon()
    }

    private func updateAutoScrollButtonIcon() {
        let isAutoScrolling = (reader as? ReaderWebtoonViewController)?.isAutoScrolling == true
        autoScrollButton.configuration?.image = UIImage(systemName: isAutoScrolling ? "pause.fill" : "play.fill")
    }

    func setReader(_ type: Reader) {
        let pageController: ReaderReaderDelegate?
        switch type {
            case .paged:
                if readingMode == .rtl {
                    toolbarView.sliderView.direction = .backward
                } else {
                    toolbarView.sliderView.direction = .forward
                }
                if !(reader is ReaderPagedViewController) {
                    pageController = ReaderPagedViewController(source: source, manga: manga)
                } else {
                    pageController = nil
                }
            case .scroll:
                toolbarView.sliderView.direction = .forward
                if !(reader is ReaderWebtoonViewController) {
                    pageController = ReaderWebtoonViewController(source: source, manga: manga)
                } else {
                    pageController = nil
                }
            case .epub:
                // An ePub reads left-to-right regardless of the manga setting, as text does
                toolbarView.sliderView.direction = .forward
                // Which archive to open is the reader's to resolve, from the chapter it is given:
                // the archive belongs to the chapter rather than to the reader, and a manga folder
                // may hold several epubs, one chapter each.
                if !(reader is ReaderEpubViewController) {
                    pageController = ReaderEpubViewController(source: source, manga: manga)
                } else {
                    pageController = nil
                }
            case .text:
                // Text always reads left-to-right, regardless of manga setting
                toolbarView.sliderView.direction = .forward

                // Check user preference for text reader style
                let textReaderStyle = UserDefaults.standard.string(forKey: "Reader.textReaderStyle") ?? "paged"
                if textReaderStyle == "paged" {
                    // Kindle-like paginated experience
                    if !(reader is ReaderPagedTextViewController) {
                        pageController = ReaderPagedTextViewController(source: source, manga: manga)
                    } else {
                        pageController = nil
                    }
                } else {
                    // Original scroll-based text reader
                    if !(reader is ReaderTextViewController) {
                        pageController = ReaderTextViewController(source: source, manga: manga)
                    } else {
                        pageController = nil
                    }
                }
        }
        if let pageController {
            if let webtoonReader = reader as? ReaderWebtoonViewController {
                webtoonReader.stopAutoScroll()
            }
            // Severed, not just removed: the reader being replaced still finishes its in-flight
            // work. The paged reader that hands an epub over completes its own move afterwards,
            // and the page it then delivered — against the one-page placeholder list — read as
            // the last page of the chapter and marked it completed, or overwrote its progress.
            reader?.delegate = nil
            reader?.remove()
            pageController.delegate = self
            reader = pageController
            add(child: pageController, below: descriptionButtonController.view)
            // The bar toggle tap is built differently for a reader hosting a web view, so it is
            // rebuilt whenever which reader is hosted changes rather than only on a chapter change.
            configureBarToggleTapGestures()
            updateBarButtonItems()
        }
        reader?.readingMode = readingMode
        configureDictionaryOverlayInteractionMode()
        configureDictionaryOverlayTapHandler()
        updateAutoScrollButton()
        disableSwipeGestures()
    }
}

// MARK: - Reader Holding Delegate
extension ReaderViewController: ReaderHoldingDelegate {
    var barsHidden: Bool { statusBarHidden }

    private func areDuplicates(_ a: AidokuRunner.Chapter, _ b: AidokuRunner.Chapter) -> Bool {
        a.chapterNumber == b.chapterNumber
            && a.volumeNumber == b.volumeNumber
            && (!(a.chapterNumber == nil && a.volumeNumber == nil) || a.title == b.title)
    }

    private func isValidScanlatorMatch(for next: AidokuRunner.Chapter, current: Set<String>) -> Bool {
        let nextScanlators = Set(next.scanlators ?? [])
        return current.isEmpty ? nextScanlators.isEmpty : !current.isDisjoint(with: nextScanlators)
    }

    private func findBestChapterMatch(from index: Int, step: Int) -> AidokuRunner.Chapter {
        let firstCandidate = chapterList[index]
        let currentScanlators = Set(chapter.scanlators ?? [])

        var i = index
        while i >= 0 && i < chapterList.count {
            let next = chapterList[i]
            guard areDuplicates(next, firstCandidate) else { break }

            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: next.key)
            let isReadable = !next.locked || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if isReadable && isValidScanlatorMatch(for: next, current: currentScanlators) {
                return next
            }
            i += step
        }

        return firstCandidate
    }

    func getNextChapter() -> AidokuRunner.Chapter? {
        guard
            var index = chapterList.firstIndex(of: chapter)
        else {
            return nil
        }

        let skipDuplicates = UserDefaults.standard.bool(forKey: "Reader.skipDuplicateChapters")
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index -= 1
        var nextChapterInList: AidokuRunner.Chapter?

        while index >= 0 {
            let new = chapterList[index]
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: new.key)

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if readable {
                let isDuplicate = areDuplicates(new, chapter)

                if nextChapterInList == nil {
                    nextChapterInList = new
                }
                if markDuplicates && isDuplicate {
                    chaptersToMark.append(new)
                }
                if !isDuplicate {
                    return skipDuplicates ? findBestChapterMatch(from: index, step: -1) : nextChapterInList
                } else if !skipDuplicates && !markDuplicates {
                    return new
                }
            }
            index -= 1
        }
        return nil
    }

    func getPreviousChapter() -> AidokuRunner.Chapter? {
        guard
            var index = chapterList.firstIndex(of: chapter)
        else {
            return nil
        }
        // find previous non-duplicate chapter
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index += 1
        while index < chapterList.count {
            let new = chapterList[index]
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: new.key)

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if readable {
                let isDuplicate = areDuplicates(new, chapter)
                if !isDuplicate {
                    return findBestChapterMatch(from: index, step: 1)
                }
                if markDuplicates {
                    chaptersToMark.append(new)
                }
            }
            index += 1
        }
        return nil
    }

    func setChapter(_ chapter: AidokuRunner.Chapter) {
        guard chapter != self.chapter else { return }

        // store current history data since it will change when new chapter loads
        let currentPage = currentPage
        let totalPages = toolbarView.totalPages
        let oldChapter = self.chapter
        Task {
            await updateReadPosition(currentPage: currentPage, totalPages: totalPages, chapter: oldChapter)
            sessionReadPages = [self.currentPage]
            sessionStartDate = Date.now
            sessionLastInteraction = nil
        }

        self.chapter = chapter
        self.chaptersToMark = [chapter]
        configureBarToggleTapGestures()
        configureDictionaryLookupGesture()
        configureDictionaryOverlayInteractionMode()
        loadNavbarTitle()
    }

    func setCurrentPage(_ page: Int, position: Double? = nil) {
        setCurrentPages(page...page, position: position)
    }

    func setCurrentPages(_ pages: ClosedRange<Int>) {
        setCurrentPages(pages, position: nil)
    }

    private func setCurrentPages(_ pages: ClosedRange<Int>, position: Double? = nil) {
        guard let totalPages = toolbarView.totalPages else { return }

        updateDescriptionButton(pages: pages)
        updateAutoScrollButton()

        sessionLastInteraction = Date.now
        for page in pages {
            guard page >= 1 && page <= totalPages else { continue }
            sessionReadPages.insert(page)
        }

        let page = max(1, min(pages.lowerBound, totalPages))
        currentPage = page
        currentPosition = position
        toolbarView.currentPage = page
        toolbarView.updateSliderPosition()
        // Mark as completed when reaching the last page
        // Exception: Don't mark for the pre-pagination placeholder (single text page before
        // ReaderPagedTextViewController has paginated it). Once paginated, even single-page
        // chapters should be marked as read.
        let isPrePaginationPlaceholder = totalPages == 1
            && self.pages.first?.isTextPage == true
            && !(reader is ReaderPagedTextViewController && (reader as? ReaderPagedTextViewController)?.hasPaginated == true)
        if pages.upperBound >= totalPages && !isPrePaginationPlaceholder {
            setCompleted()
        }
    }

    private func updateDescriptionButton(pages: ClosedRange<Int>) {
        let pageItems = pages.compactMap { self.pages[safe: $0 - 1]?.toNew() }
        if pageItems.contains(where: { $0.hasDescription }) {
            descriptionButtonController.rootView = ReaderPageDescriptionButtonView(
                source: source,
                pages: pageItems
            )
            descriptionButtonController.view.isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.descriptionButtonController.view.alpha = 1
            }
        } else {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.descriptionButtonController.view.alpha = 0
            } completion: { _ in
                self.descriptionButtonController.view.isHidden = true
            }
        }
    }

    func setPages(_ pages: [Page]) {
        // If already in a text reader with text pages, just update toolbar - don't trigger any switches
        if
            reader is ReaderPagedTextViewController || reader is ReaderTextViewController,
            pages.allSatisfy({ $0.isTextPage }),
            pages.count > 1
        {
            self.pages = pages
            toolbarView.totalPages = pages.count
            activityIndicator.stopAnimating()
            return
        }
        self.pages = pages
        toolbarView.totalPages = pages.count
        activityIndicator.stopAnimating()
        // A reader with contents of its own only has them once it has opened what it was given, and
        // this is the call it makes when it has.
        updateBarButtonItems()
        if pages.isEmpty {
            // no pages, show error
            showLoadFailAlert()
        } else if pages.contains(where: { $0.isEpubPage }) {
            // an epub is one chapter spanning its whole spine, so the reader is handed the book
            // and reports its own page count back through setPages once it has been laid out
            if !(reader is ReaderEpubViewController) {
                setReader(.epub)
                setChapter(chapter)
                loadCurrentChapter()
            }
        } else if pages.count == 1 && pages[0].isTextPage {
            // single text page, should switch to text reader
            if !(reader is ReaderPagedTextViewController) && !(reader is ReaderTextViewController) {
                setReader(.text)
                setChapter(chapter)
                loadCurrentChapter()
            } else {
            }
        } else if reader is ReaderPagedTextViewController && pages.allSatisfy({ $0.isTextPage }) {
            // Already in paginated text reader with multiple text pages (from pagination)
            // Don't switch away - this is our internal page count update
            // Just update the toolbar, don't reload
        } else {
            // otherwise, make sure we're not in the text or epub reader.
            // an epub reader reaches this by handing over a chapter that turned out not to be an
            // epub, which a folder holding an epub beside a cbz produces.
            if reader is ReaderTextViewController
                || reader is ReaderPagedTextViewController
                || reader is ReaderEpubViewController {
                switch readingMode {
                    case .ltr, .rtl, .vertical:
                        setReader(.paged)
                    case .webtoon, .continuous:
                        setReader(.scroll)
                }
                setChapter(chapter)
                loadCurrentChapter()
            }
        }
    }

    func displayPage(_ page: Int) {
        toolbarView.displayPage(page)
    }

    func setSliderOffset(_ offset: CGFloat) {
        toolbarView.sliderView.currentValue = offset
    }

    func setCompleted() {
        guard !UserDefaults.standard.bool(forKey: "General.incognitoMode") else { return }

        // An epub is one chapter spanning a whole spine, and its total is a lower bound until
        // every spine document has been counted — and unknown entirely while the book is still
        // opening, when the reader that handed the chapter over delivers one last position against
        // the single placeholder page. Completing on either marks a book read from its first
        // document and, with deleteDownloadAfterReading, deletes it. Guarded here rather than at
        // the last-page check so a completion no reader may claim yet is refused whichever
        // delegate path it arrives by.
        if let epubReader = reader as? ReaderEpubViewController, epubReader.book?.isMeasured != true {
            return
        }

        Task { [chaptersToMark] in
            await HistoryManager.shared.addHistory(
                sourceId: manga.sourceKey,
                mangaId: manga.key,
                chapters: chaptersToMark
            )
        }

        if UserDefaults.standard.bool(forKey: "Library.deleteDownloadAfterReading") {
            chaptersToRemoveDownload.append(chapter)
        }
    }

    private func configureBarToggleTapGestures() {
        if let barToggleTapGesture {
            view.removeGestureRecognizer(barToggleTapGesture)
        }
        if let barToggleSecondaryTapGesture {
            view.removeGestureRecognizer(barToggleSecondaryTapGesture)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = self
        // The epub reader is the only one with a web view under the tap zones, and the only one
        // whose tap must not cancel touches in its view: that is what lets the web view keep text
        // selection and links.
        if reader is ReaderEpubViewController {
            tap.cancelsTouchesInView = false
        }
        let singleTapLookupEnabled = isDictionarySingleTapLookupActiveForCurrentChapter
        configureNavigationBarDismissTapGesture(enabled: singleTapLookupEnabled)

        if !singleTapLookupEnabled, !UserDefaults.standard.bool(forKey: "Reader.disableDoubleTap") {
            let doubleTap = UITapGestureRecognizer(
                target: self,
                action: nil
            )
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            view.addGestureRecognizer(doubleTap)
            tap.require(toFail: doubleTap)
            barToggleSecondaryTapGesture = doubleTap
        } else {
            barToggleSecondaryTapGesture = nil
        }

        view.addGestureRecognizer(tap)
        barToggleTapGesture = tap
    }

    private func configureNavigationBarDismissTapGesture(enabled: Bool) {
        guard let navigationBar = navigationController?.navigationBar else { return }

        if barDismissNavigationBarTapGesture == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleNavigationBarTapToDismissBars(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            navigationBar.addGestureRecognizer(tap)
            barDismissNavigationBarTapGesture = tap
        }
        barDismissNavigationBarTapGesture?.isEnabled = enabled
    }

    @objc private func handleNavigationBarTapToDismissBars(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        guard isDictionarySingleTapLookupActiveForCurrentChapter else { return }
        hideBars()
    }

    private func configureDictionaryLookupGesture() {
        if let gesture = dictionaryLongPressGesture {
            view.removeGestureRecognizer(gesture)
            dictionaryLongPressGesture = nil
        }
        clearDictionarySelectionHighlight()
        if #available(iOS 18.0, *) {
            dictionaryLongPressSelection = nil
        }

        guard
            isDictionaryLongPressLookupActiveForCurrentChapter,
            !AppSettings.dictionary.textOverlayMode.get()
        else {
            return
        }

        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDictionaryLongPress(_:)))
        gesture.minimumPressDuration = 0.25
        gesture.allowableMovement = 60
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        dictionaryLongPressGesture = gesture
    }

    @objc private func handleDictionaryLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard
            #available(iOS 18.0, *),
            isDictionaryLongPressLookupActiveForCurrentChapter,
            !AppSettings.dictionary.textOverlayMode.get(),
            !dictionaryCoordinator.isPopupVisible,
            LookupEngine.shared.isReady
        else {
            return
        }

        let point = gestureRecognizer.location(in: view)
        switch gestureRecognizer.state {
            case .began, .changed:
                guard
                    let reader = reader as? ReaderDictionaryReader,
                    let result = reader.recognizedText(at: point)
                else {
                    dictionaryLongPressSelection = nil
                    clearDictionarySelectionHighlight()
                    return
                }
                dictionaryLongPressSelection = result
                updateDictionarySelectionHighlight(text: result.text, charRects: result.charRects)

            case .ended:
                defer {
                    dictionaryLongPressSelection = nil
                    clearDictionarySelectionHighlight()
                }
                var selection = dictionaryLongPressSelection
                if selection == nil, let reader = reader as? ReaderDictionaryReader {
                    selection = reader.recognizedText(at: point)
                }
                if let selection {
                    _ = dictionaryCoordinator.performLookup(
                        text: selection.text,
                        contextText: selection.fullText,
                        anchorRect: selection.charRect,
                        charRects: selection.charRects,
                        page: currentPage
                    )
                }

            default:
                dictionaryLongPressSelection = nil
                clearDictionarySelectionHighlight()
        }
    }

    @available(iOS 18.0, *)
    private func updateDictionarySelectionHighlight(text: String, charRects: [CGRect]) {
        dictionaryCoordinator.updateSelectionHighlight(text: text, charRects: charRects)
    }

    private func clearDictionarySelectionHighlight() {
        if #available(iOS 18.0, *) {
            dictionaryCoordinator.clearSelectionHighlight()
        }
    }
}

// MARK: - Tap Zones
extension ReaderViewController {
    private enum ReaderControlTapZoneConstants {
        static let minimumTapZoneHeight: CGFloat = 44
    }

    func updateTapZone() {
        let enabledTapZone = UserDefaults.standard.string(forKey: "Reader.tapZones")
        let tapZone: TapZone? = switch enabledTapZone {
            case "auto": switch reader {
                case is ReaderPagedViewController: .leftRight
                case is ReaderWebtoonViewController: .lShaped
                case is ReaderTextViewController: .lShaped
                case is ReaderPagedTextViewController: .leftRight  // Kindle-style tap zones
                default: .leftRight
            }
            case "left-right": .leftRight
            case "l-shaped": .lShaped
            case "kindle": .kindle
            case "edge": .edge
            default: nil
        }
        self.tapZone = tapZone
    }

    @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let point = gestureRecognizer.location(in: view)
        let overlayModeEnabled = AppSettings.dictionary.textOverlayMode.get()
        let singleTapLookupEnabled = isDictionarySingleTapLookupActiveForCurrentChapter
        let singleTapOCRLookupEnabled = singleTapLookupEnabled && !overlayModeEnabled

        // dismiss dictionary popup if visible
        if #available(iOS 18.0, *), dictionaryCoordinator.isPopupVisible {
            dictionaryCoordinator.dismissAllPopups()
            return
        }

        // dismiss text overlay box if visible
        if
            #available(iOS 18.0, *),
            overlayModeEnabled,
            let reader = reader as? ReaderDictionaryReader,
            reader.dismissActiveDictionaryOverlay()
        {
            return
        }

        // a tap the reader has already answered for itself, such as a link inside an ePub. Asked
        // before anything here acts on it, because the alternative is undoing what was done: the
        // bars were toggled and a page turned by the same tap that followed a footnote.
        if reader?.consumesTap() == true {
            return
        }

        // toggle bars when tapping safe areas
        if singleTapLookupEnabled, isReaderControlToggleTapZone(point) {
            toggleBarVisibility()
            return
        }

        // check for dictionary lookup
        if
            #available(iOS 18.0, *),
            singleTapOCRLookupEnabled,
            let reader = reader as? ReaderDictionaryReader,
            LookupEngine.shared.isReady
        {
            if let result = reader.recognizedText(at: point) {
                if dictionaryCoordinator.performLookup(
                    text: result.text,
                    contextText: result.fullText,
                    anchorRect: result.charRect,
                    charRects: result.charRects,
                    page: currentPage
                ).openedPopup {
                    return
                }
            }
        }

        // A tap on an image inside an ePub shows a fullscreen preview of it, the way the readium
        // toolkit's image previews behave. Asked before the zones so a page cannot also turn out
        // from under the preview; taps that hit no image fall through unchanged.
        if let epub = reader as? ReaderEpubViewController {
            let location = view.convert(point, to: epub.view)
            Task { [weak self] in
                guard let self else { return }
                if await epub.presentImagePreview(forTapAt: location) { return }
                self.handleZoneTap(at: point)
            }
            return
        }

        handleZoneTap(at: point)
    }

    /// The tap-zone half of `handleTap`: turn a page or toggle the bars.
    private func handleZoneTap(at point: CGPoint) {
        guard let reader, let tapZone else {
            toggleBarVisibility()
            return
        }

        let relativePoint = CGPoint(
            x: point.x / view.bounds.width,
            y: point.y / view.bounds.height
        )

        let type = tapZone.regions
            .first { $0.bounds.contains(relativePoint) }
            .map(\.type)

        if let type {
            // hide the bars when tapping regardless
            if let navigationController, navigationController.navigationBar.alpha > 0 {
                hideBars()
            }
            // handle page moving
            if UserDefaults.standard.bool(forKey: "Reader.invertTapZones") {
                switch type {
                    case .left: reader.moveRight()
                    case .right: reader.moveLeft()
                }
            } else {
                switch type {
                    case .left: reader.moveLeft()
                    case .right: reader.moveRight()
                }
            }
        } else {
            toggleBarVisibility()
        }
    }

    private func isReaderControlToggleTapZone(_ point: CGPoint) -> Bool {
        let topZoneHeight = readerControlTopTapZoneHeight
        if point.y <= topZoneHeight {
            return true
        }
        let bottomZoneMinY = view.bounds.height - readerControlBottomTapZoneHeight
        return point.y >= bottomZoneMinY
    }

    private var readerControlTopTapZoneHeight: CGFloat {
        view.safeAreaInsets.top + ReaderControlTapZoneConstants.minimumTapZoneHeight
    }

    private var readerControlBottomTapZoneHeight: CGFloat {
        view.safeAreaInsets.bottom + ReaderControlTapZoneConstants.minimumTapZoneHeight
    }
}

// MARK: - Apple Pencil Squeeze
extension ReaderViewController: UIPencilInteractionDelegate {
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // if pencil squeezing is disabled globally, ignore interaction (hig)
        guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }

        switch squeeze.phase {
            case .began:
                squeezeStartTime = Date()
                longSqueezeTimer = Timer.scheduledTimer(
                    withTimeInterval: longSqueezeThreshold,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.longSqueezeTimer = nil
                        self?.openContents()
                    }
                }
            case .ended:
                guard let startTime = squeezeStartTime else { return }
                let duration = Date().timeIntervalSince(startTime)
                squeezeStartTime = nil
                longSqueezeTimer?.invalidate()
                longSqueezeTimer = nil

                if duration >= longSqueezeThreshold {
                    // long squeeze: chapter selector
                    squeezeTimer?.invalidate()
                    squeezeTimer = nil
                    return
                } else {
                    if let timer = squeezeTimer {
                        // double squeeze: previous page
                        timer.invalidate()
                        squeezeTimer = nil
                        previousPage()
                    } else {
                        // single squeeze: next page
                        squeezeTimer = Timer.scheduledTimer(
                            withTimeInterval: doubleSqueezeInterval,
                            repeats: false
                        ) { [weak self] _ in
                            Task { @MainActor in
                                self?.squeezeTimer = nil
                                self?.nextPage()
                            }
                        }
                    }
                }
            default:
                break
        }

    }

    private func nextPage() {
        switch readingMode {
            case .rtl: reader?.moveLeft()
            default: reader?.moveRight()
        }
    }

    private func previousPage() {
        switch readingMode {
            case .rtl: reader?.moveRight()
            default: reader?.moveLeft()
        }
    }
}

extension ReaderViewController {
    private func configureDictionaryOverlayInteractionMode() {
        guard #available(iOS 18.0, *), let reader = reader as? ReaderDictionaryReader else { return }

        let mode: DictionaryOverlayInteractionMode
        if !AppSettings.dictionary.textOverlayMode.get() {
            mode = .none
        } else if isDictionarySingleTapLookupActiveForCurrentChapter {
            mode = .singleTap
        } else if isDictionaryLongPressLookupActiveForCurrentChapter {
            mode = .longPress
        } else {
            mode = .none
        }

        reader.setDictionaryOverlayInteractionMode(mode)
    }

    private func configureDictionaryOverlayTapHandler() {
        guard #available(iOS 18.0, *), let reader = reader as? ReaderDictionaryReader else { return }
        reader.setDictionaryOverlayTapHandler { [weak self] text, contextText, rect, charRects in
            guard let self, AppSettings.dictionary.textOverlayMode.get() else { return }
            _ = dictionaryCoordinator.performLookup(
                text: text,
                contextText: contextText,
                anchorRect: rect,
                charRects: charRects,
                page: currentPage
            )
        }
    }
}

// MARK: - Bar Visibility
extension ReaderViewController {
    @objc func toggleBarVisibility() {
        guard let navigationController else { return }
        if !navigationController.navigationBar.isHidden {
            hideBars()
        } else {
            showBars()
        }
    }

    func showBars() {
        guard let navigationController else { return }

        if #available(iOS 27.0, *) {
            navigationController.navigationBar.isHidden = true
            navigationController.isNavigationBarHidden = false
        }

        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.statusBarHidden = false
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        } completion: { _ in
            NotificationCenter.default.post(name: .readerShowingBars, object: nil)

            UIView.setAnimationsEnabled(false)
            if #available(iOS 26.0, *) {
                if navigationController.isToolbarHidden {
                    (navigationController.value(forKey: "_floatingBarContainerView") as? UIView)?.alpha = 0
                    navigationController.isToolbarHidden = false
                }
            } else {
                if navigationController.toolbar.isHidden {
                    navigationController.toolbar.alpha = 0
                    navigationController.toolbar.isHidden = false
                }
            }
            navigationController.navigationBar.isHidden = false
            UIView.setAnimationsEnabled(true)
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                navigationController.navigationBar.alpha = 1
                navigationController.toolbar.alpha = 1
                if #available(iOS 26.0, *) {
                    (navigationController.value(forKey: "_floatingBarContainerView") as? UIView)?.alpha = 1
                }
                self.node.backgroundColor = if UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                    .systemBackground
                } else {
                    if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                        .white
                    } else {
                        .black
                    }
                }
                self.node.layoutIfNeeded()
            }
        }
    }

    func hideBars() {
        guard let navigationController else { return }

        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.statusBarHidden = true
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        } completion: { _ in
            NotificationCenter.default.post(name: .readerHidingBars, object: nil)

            UIView.animate(withDuration: CATransaction.animationDuration()) {
                navigationController.navigationBar.alpha = 0
                navigationController.toolbar.alpha = 0

                if #available(iOS 26.0, *) {
                    (navigationController.value(forKey: "_floatingBarContainerView") as? UIView)?.alpha = 0
                }

                self.node.backgroundColor = switch UserDefaults.standard.string(forKey: "Reader.backgroundColor") {
                    case "system":
                        .systemBackground
                    case "white":
                        .white
                    default:
                        .black
                }
                self.node.layoutIfNeeded()
            } completion: { _ in
                if #available(iOS 27.0, *) {
                    navigationController.isNavigationBarHidden = true
                } else {
                    navigationController.navigationBar.isHidden = true
                }
                if #available(iOS 26.0, *) {
                    navigationController.isToolbarHidden = true
                } else {
                    navigationController.toolbar.isHidden = true
                }
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension ReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return velocity.y > velocity.x && (abs(velocity.x) < 40 || abs(velocity.y) > abs(velocity.x) * 3)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard
            gestureRecognizer === barDismissNavigationBarTapGesture
                || gestureRecognizer === barToggleTapGesture
                || gestureRecognizer === barToggleSecondaryTapGesture
        else {
            return true
        }

        var view: UIView? = touch.view
        while let currentView = view {
            if currentView is UIControl {
                return false
            }
            view = currentView.superview
        }
        return true
    }

    // A WKWebView installs its own recognizers on its content view, and they claim a single tap
    // before an ancestor's recognizer sees it. Recognising simultaneously is what lets a tap reach
    // the tap zones while an epub's web view sits under them; no other reader puts a web view there,
    // so everything else keeps the default exclusivity.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === barToggleTapGesture || gestureRecognizer === barToggleSecondaryTapGesture)
            && reader is ReaderEpubViewController
    }

}

// MARK: - Keyboard Shortcuts
extension ReaderViewController {
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_LEFT"),
                action: #selector(moveLeft),
                input: UIKeyCommand.inputLeftArrow
            ),
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_RIGHT"),
                action: #selector(moveRight),
                input: UIKeyCommand.inputRightArrow
            ),
            UIKeyCommand(
                title: NSLocalizedString("TOGGLE_PAGE_OFFSET"),
                action: #selector(toggleOffset),
                input: "o"
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_FORWARD"),
                action: #selector(nextChapter),
                input: ","
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_BACKWARD"),
                action: #selector(previousChapter),
                input: "."
            ),
            UIKeyCommand(
                title: NSLocalizedString("OPEN_CHAPTER_LIST"),
                action: #selector(openContents),
                input: "\t"
            ),
            UIKeyCommand(
                title: NSLocalizedString("TOGGLE_BARS"),
                action: #selector(toggleBarVisibility),
                input: " "
            ),
            UIKeyCommand(
                title: NSLocalizedString("CLOSE_READER"),
                action: #selector(close),
                input: UIKeyCommand.inputEscape
            )
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc func moveLeft() {
        reader?.moveLeft()
    }

    @objc func moveRight() {
        reader?.moveRight()
    }

    @objc func toggleOffset() {
        reader?.toggleOffset()
    }

    @objc func nextChapter() {
        if let nextChapter = getNextChapter() {
            reader?.setChapter(nextChapter, startPage: 1)
            setChapter(nextChapter)
        }
    }

    @objc func previousChapter() {
        if let previousChaoter = getPreviousChapter() {
            reader?.setChapter(previousChaoter, startPage: 1)
            setChapter(previousChaoter)
        }
    }
}

// MARK: - Table of Contents

extension ReaderViewController {
    /// The hosted reader when it carries contents of its own, which is what decides whether the
    /// chapter-list button opens those contents or the chapters of the series.
    private var contentsReader: ReaderTableOfContentsReader? {
        reader as? ReaderTableOfContentsReader
    }

    /// Whether the hosted reader has read its own contents yet. False for a reader that has none.
    ///
    /// Asked of the reader rather than of the table, because a book that declares no contents reads
    /// them and finds none: taking an empty table for "not read yet" left the chapter-list button
    /// disabled for as long as such a book was open, and the fallback in `openContents` that exists
    /// for exactly that book was then reachable only by keyboard or pencil.
    private var hasReadContents: Bool {
        contentsReader?.hasReadTableOfContents == true
    }

    /// Whether the hosted reader has contents worth showing, which decides which list the button
    /// opens once it is enabled.
    private var hasContents: Bool {
        contentsReader?.tableOfContents.isEmpty == false
    }

    /// Rebuilds the bar items that depend on what the hosted reader can offer.
    ///
    /// Rebuilt rather than hidden: `UIBarButtonItem.isHidden` is iOS 16 and the reader deploys to
    /// 15. Which reader is hosted, and whether it has read a table of contents yet, are both known
    /// only after a chapter has been loaded, so this is called again whenever either can have moved.
    func updateBarButtonItems() {
        let state = BarButtonState(
            hostsContents: contentsReader != nil,
            contentsRead: hasReadContents,
            web: chapter.url != nil
        )
        guard state != builtBarState else { return }
        builtBarState = state

        // A reader carrying contents of its own opens them from the chapter-list button, so the
        // button waits rather than opening the wrong list. Disabled rather than removed: removing it
        // reflowed the items either side, so the buttons moved between chapters and a tap aimed at
        // one landed on another; a disabled item holds its place and says plainly it is not ready.
        chapterListButton?.isEnabled = !state.hostsContents || state.contentsRead

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            style: .plain,
            target: self,
            action: #selector(openWebView)
        )
        moreButton.isEnabled = state.web

        var items = [moreButton]
        items.append(
            UIBarButtonItem(
                image: UIImage(systemName: "textformat.size"),
                style: .plain,
                target: self,
                action: #selector(openReaderSettings)
            )
        )
        navigationItem.rightBarButtonItems = items
    }

    /// Shows the contents of what is open, so the reader can move about inside it.
    ///
    /// Reached through `openContents` rather than from a button of its own, since one ePub is one
    /// chapter and its chapter list holds a single row: the two answer the same question, and only
    /// one of them answers it usefully.
    @objc func openTableOfContents() {
        guard let reader = contentsReader else { return }
        let view = ReaderEpubContentsView(
            contents: reader.tableOfContents,
            currentEntry: { await reader.currentTableOfContentsEntry() },
            bookPage: { reader.bookPage(ofTableOfContentsEntry: $0) },
            entrySet: { [weak self] entry in
                self?.dismiss(animated: true)
                reader.goToTableOfContentsEntry(entry)
            }
        )
        present(UIHostingController(rootView: view), animated: true)
    }

    /// Opens whichever list places the reader in what they are reading.
    ///
    /// A reader carrying contents of its own answers that with them; every other reader answers it
    /// with the chapters of the series. The button is disabled until a contents-carrying reader has
    /// read them, so what is decided here is only which list a reader that has read them opens.
    ///
    /// A book that declares no contents still opens its own sheet, which says so, unless the series
    /// holds more than one book: an ePub is one chapter, so a series of several is a list worth
    /// showing, and it is the only way to reach the next book without leaving the reader.
    @objc func openContents() {
        guard contentsReader != nil else {
            openChapterList()
            return
        }
        if hasContents || chapterList.count <= 1 {
            openTableOfContents()
        } else {
            openChapterList()
        }
    }
}
