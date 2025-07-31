//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import UIKit
import SafariServices
import SwiftUI
import AidokuRunner

class ReaderViewController: BaseObservingViewController {

    enum Reader {
        case paged
        case scroll
        case text
    }

    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    var chapter: AidokuRunner.Chapter
    var pages: [Page] = []
    var readingMode: ReadingMode = .rtl
    var defaultReadingMode: ReadingMode?
    private var tapZone: TapZone?

    var chapterList: [AidokuRunner.Chapter]
    var chaptersToMark: [AidokuRunner.Chapter] = []
    var chaptersToRemoveDownload: [AidokuRunner.Chapter] = []
    var currentPage = 1

    weak var reader: ReaderReaderDelegate?

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var toolbarView = ReaderToolbarView()
    private var toolbarViewWidthConstraint: NSLayoutConstraint?

    private lazy var descriptionButtonController: UIHostingController<ReaderPageDescriptionButtonView> = {
        let buttonView = ReaderPageDescriptionButtonView(source: source, pages: [])
        let hostingController = UIHostingController(rootView: buttonView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.alpha = 0
        hostingController.view.isHidden = true
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingController
    }()
    private lazy var pageDescriptionButtonBottomConstraint: NSLayoutConstraint =
        descriptionButtonController.view.bottomAnchor.constraint(
            equalTo: {
                if #available(iOS 16.0, *) {
                    view.bottomAnchor
                } else {
                    view.safeAreaLayoutGuide.bottomAnchor
                }
            }()
        )

    private lazy var barToggleTapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1

        let doubleTap = UITapGestureRecognizer(target: self, action: nil)
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        tap.require(toFail: doubleTap)

        return tap
    }()

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
        chapter: AidokuRunner.Chapter
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
        super.init()
    }

    override func configure() {
        node.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        // navbar buttons
        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(close)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "list.bullet"),
                style: .plain,
                target: self,
                action: #selector(openChapterList)
            )
        ]
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            style: .plain,
            target: self,
            action: #selector(openWebView)
        )
        moreButton.isEnabled = chapter.url != nil
        navigationItem.rightBarButtonItems = [
            moreButton,
            UIBarButtonItem(
                image: UIImage(systemName: "textformat.size"),
                style: .plain,
                target: self,
                action: #selector(openReaderSettings)
            )
        ]

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
        toolbarButtonItemView.customView?.transform = CGAffineTransform(translationX: 0, y: -10)
        toolbarButtonItemView.customView?.heightAnchor.constraint(equalToConstant: 40).isActive = true
        if #available(iOS 26.0, *) {
            toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(
                equalToConstant: node.bounds.width - 32 - 10
            )
        } else {
            toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(equalToConstant: view.bounds.width)
        }

        add(child: descriptionButtonController)

        toolbarItems = [toolbarButtonItemView]
        navigationController?.isToolbarHidden = false
        navigationController?.toolbar.fitContentViewToToolbar()

        // loading indicator
        activityIndicator.startAnimating()
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        // bar toggle tap gesture
        view.addGestureRecognizer(barToggleTapGesture)

        // set reader
        let readingModeKey = "Reader.readingMode.\(manga.key)"
        UserDefaults.standard.register(defaults: [readingModeKey: "default"])
        setReadingMode(UserDefaults.standard.string(forKey: readingModeKey))

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

            descriptionButtonController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            pageDescriptionButtonBottomConstraint
        ])
    }

    override func observe() {
        addObserver(forName: "Reader.readingMode.\(manga.key)") { [weak self] _ in
            guard let self else { return }
            self.setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode.\(self.manga.key)"))
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
            // if the tap zone is auto, it will changed based on the current reader
            self.updateTapZone()
        }
        // reload pages when processors change
        addObserver(forName: "Reader.downsampleImages") { [weak self] _ in
            guard let self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        addObserver(forName: "Reader.upscaleImages") { [weak self] _ in
            guard let self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        addObserver(forName: "Reader.cropBorders") { [weak self] _ in
            guard let self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        addObserver(forName: "Reader.tapZones") { [weak self] _ in
            self?.updateTapZone()
        }
        addObserver(forName: UIScene.willDeactivateNotification) { [weak self] _ in
            guard let self else { return }
            self.updateReadPosition()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // there's a bug on ios 15 where the toolbar just disappears when adding a child hosting controller
        navigationController?.isToolbarHidden = false
        navigationController?.toolbar.alpha = 1
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if !chaptersToRemoveDownload.isEmpty {
            DownloadManager.shared.delete(chapters: chaptersToRemoveDownload.map {
                $0.toOld(sourceId: source?.key ?? manga.sourceKey, mangaId: manga.key)
            })
        }

        guard currentPage >= 1 else { return }
        updateReadPosition()
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

    func updateReadPosition() {
        guard
            !UserDefaults.standard.bool(forKey: "General.incognitoMode"),
            (toolbarView.totalPages ?? 0) > 0
        else { return }
        Task {
            // don't add history if there is none and we're at the first page
            let sourceId = source?.key ?? manga.sourceKey
            let mangaId = manga.key
            if currentPage == 1 {
                let chapterId = chapter.key
                let hasHistory = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                    !CoreDataManager.shared.hasHistory(
                        sourceId: sourceId,
                        mangaId: mangaId,
                        chapterId: chapterId,
                        context: context
                    )
                }
                if hasHistory {
                    return
                }
            }
            await HistoryManager.shared.setProgress(
                chapter: chapter.toOld(sourceId: sourceId, mangaId: mangaId),
                progress: currentPage,
                totalPages: toolbarView.totalPages
            )
        }
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
        reader?.setChapter(chapter, startPage: currentPage)
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
        let vc = UIHostingController(
            rootView: ReaderSettingsView(mangaId: manga.key)
        )
        present(vc, animated: true)
    }

    @objc func openWebView() {
        guard let url = chapter.url, url.scheme == "http" || url.scheme == "https" else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    @objc func openChapterList() {
        var view = ReaderChapterListView(
            chapterList: chapterList,
            chapter: chapter
        )
        view.chapterSet = { [weak self] chapter in
            guard let self else { return }
            self.setChapter(chapter)
            self.loadCurrentChapter()
        }
        let vc = UIHostingController(rootView: view)
        present(vc, animated: true)
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
            case .text:
                toolbarView.sliderView.direction = .forward
                if !(reader is ReaderTextViewController) {
                    pageController = ReaderTextViewController(source: source, manga: manga)
                } else {
                    pageController = nil
                }
        }
        if let pageController {
            reader?.remove()
            pageController.delegate = self
            reader = pageController
            add(child: pageController, below: descriptionButtonController.view)
        }
        reader?.readingMode = readingMode
    }
}

// MARK: - Reader Holding Delegate
extension ReaderViewController: ReaderHoldingDelegate {

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

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: new.toOld(sourceId: manga.sourceKey, mangaId: manga.key)) == .finished

            if readable {
                let isDuplicate =
                    new.chapterNumber == chapter.chapterNumber
                    && new.volumeNumber == chapter.volumeNumber
                    && (!(new.chapterNumber == nil && new.volumeNumber == nil) || new.title == chapter.title)

                if nextChapterInList == nil {
                    nextChapterInList = new
                }
                if markDuplicates && isDuplicate {
                    chaptersToMark.append(new)
                }
                if !isDuplicate {
                    return skipDuplicates ? new : nextChapterInList
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

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: new.toOld(sourceId: manga.sourceKey, mangaId: manga.key)) == .finished

            if readable {
                let isDuplicate =
                    new.chapterNumber == chapter.chapterNumber
                    && new.volumeNumber == chapter.volumeNumber
                    && (!(new.chapterNumber == nil && new.volumeNumber == nil) || new.title == chapter.title)
                if !isDuplicate {
                    return new
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
        self.chapter = chapter
        self.chaptersToMark = [chapter]
        loadNavbarTitle()
    }

    func setCurrentPage(_ page: Int) {
        setCurrentPages(page...page)
    }

    func setCurrentPages(_ pages: ClosedRange<Int>) {
        guard let totalPages = toolbarView.totalPages else { return }

        updateDescriptionButton(pages: pages)

        let page = max(1, min(pages.lowerBound, totalPages))
        currentPage = page
        toolbarView.currentPage = page
        toolbarView.updateSliderPosition()
        if pages.upperBound >= totalPages {
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
        self.pages = pages
        toolbarView.totalPages = pages.count
        activityIndicator.stopAnimating()
        if pages.isEmpty {
            // no pages, show error
            showLoadFailAlert()
        } else if pages.count == 1 && pages[0].text != nil {
            // single text page, should switch to text reader
            if !(reader is ReaderTextViewController) {
                setReader(.text)
                setChapter(chapter)
                loadCurrentChapter()
            }
        } else {
            // otherwise, make sure we're not in the text reader
            if reader is ReaderTextViewController {
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
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            Task {
                await HistoryManager.shared.addHistory(
                    chapters: chaptersToMark.map {
                        $0.toOld(sourceId: source?.key ?? manga.sourceKey, mangaId: manga.key)
                    }
                )
            }
        }
        if UserDefaults.standard.bool(forKey: "Library.deleteDownloadAfterReading") {
            chaptersToRemoveDownload.append(chapter)
        }
    }
}

// MARK: - Tap Zones
extension ReaderViewController {
    func updateTapZone() {
        let enabledTapZone = UserDefaults.standard.string(forKey: "Reader.tapZones")
        let tapZone: TapZone? = switch enabledTapZone {
            case "auto": switch reader {
                case is ReaderPagedViewController: .leftRight
                case is ReaderWebtoonViewController: .lShaped
                case is ReaderTextViewController: .lShaped
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
        guard let reader, let tapZone else {
            toggleBarVisibility()
            return
        }

        let point = gestureRecognizer.location(in: view)
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
            switch type {
                case .left: reader.moveLeft()
                case .right: reader.moveRight()
            }
        } else {
            toggleBarVisibility()
        }
    }
}

// MARK: - Bar Visibility
extension ReaderViewController {
    func toggleBarVisibility() {
        guard let navigationController else { return }
        if navigationController.navigationBar.alpha > 0 {
            hideBars()
        } else {
            showBars()
        }
    }

    func showBars() {
        guard let navigationController else { return }

        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.statusBarHidden = false
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        } completion: { _ in
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
            self.pageDescriptionButtonBottomConstraint.constant = 0
            UIView.setAnimationsEnabled(true)
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                navigationController.navigationBar.alpha = 1
                navigationController.toolbar.alpha = 1
                if #available(iOS 26.0, *) {
                    (navigationController.value(forKey: "_floatingBarContainerView") as? UIView)?.alpha = 1
                }
                self.node.backgroundColor = .systemBackground
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
            self.pageDescriptionButtonBottomConstraint.constant = 30

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
                if #available(iOS 26.0, *) {
                    navigationController.isToolbarHidden = true
                } else {
                    navigationController.toolbar.isHidden = true
                }
            }
        }
    }
}

// MARK: - Keyboard Shortcuts
extension ReaderViewController {
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_LEFT"),
                action: #selector(moveLeft),
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_RIGHT"),
                action: #selector(moveRight),
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
//            UIKeyCommand(
//                title: "Scroll up",
//                action: #selector(scrollUp),
//                input: UIKeyCommand.inputUpArrow,
//                modifierFlags: [],
//                alternates: [],
//                attributes: [],
//                state: .off
//            ),
//            UIKeyCommand(
//                title: "Scroll down",
//                action: #selector(scrollDown),
//                input: UIKeyCommand.inputDownArrow,
//                modifierFlags: [],
//                alternates: [],
//                attributes: [],
//                state: .off
//            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_FORWARD"),
                action: #selector(nextChapter),
                input: ",",
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_BACKWARD"),
                action: #selector(previousChapter),
                input: ".",
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("OPEN_CHAPTER_LIST"),
                action: #selector(openChapterList),
                input: "\t",
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("CLOSE_READER"),
                action: #selector(close),
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            )
        ]
    }

    @objc func moveLeft() {
        reader?.moveLeft()
    }

    @objc func moveRight() {
        reader?.moveRight()
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
