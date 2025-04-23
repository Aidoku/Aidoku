//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import UIKit
import SafariServices
import SwiftUI

class ReaderViewController: BaseObservingViewController {

    enum Reader {
        case paged
        case scroll
    }

    var chapter: Chapter
    var readingMode: ReadingMode = .rtl
    var defaultReadingMode: ReadingMode?

    var chapterList: [Chapter] = []
    var chaptersToMark: [Chapter] = []
    var currentPage = 1

    weak var reader: ReaderReaderDelegate?

    private let moreButton = UIBarButtonItem(
        image: UIImage(systemName: "ellipsis"),
        style: .plain,
        target: nil,
        action: nil
    )

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var toolbarView = ReaderToolbarView()
    private var toolbarViewWidthConstraint: NSLayoutConstraint?

    private lazy var barToggleTapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleBarVisibility))
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

    init(chapter: Chapter, chapterList: [Chapter] = [], defaultReadingMode: ReadingMode? = nil) {
        self.chapter = chapter
        self.chapterList = chapterList
        self.chaptersToMark = [chapter]
        self.defaultReadingMode = defaultReadingMode
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        view.backgroundColor = .systemBackground
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
        navigationItem.rightBarButtonItems = [
            moreButton,
            UIBarButtonItem(
                image: UIImage(systemName: "textformat.size"),
                style: .plain,
                target: self,
                action: #selector(openReaderSettings)
            )
        ]
        updateMoreButton()

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
        toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(equalToConstant: view.bounds.width)

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
        let readingModeKey = "Reader.readingMode.\(chapter.mangaId)"
        UserDefaults.standard.register(defaults: [readingModeKey: "default"])
        setReadingMode(UserDefaults.standard.string(forKey: readingModeKey))

        // load chapter list
        loadCurrentChapter()
    }

    override func constrain() {
        toolbarViewWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func observe() {
        addObserver(forName: "Reader.readingMode.\(chapter.mangaId)") { [weak self] _ in
            guard let self = self else { return }
            self.setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode.\(self.chapter.mangaId)"))
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        addObserver(forName: "Reader.downsampleImages") { [weak self] _ in
            guard let self = self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        addObserver(forName: "Reader.cropBorders") { [weak self] _ in
            guard let self = self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        addObserver(forName: UIScene.willDeactivateNotification) { [weak self] _ in
            guard let self = self else { return }
            self.updateReadPosition()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard currentPage >= 1 else { return }
        updateReadPosition()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            self.toolbarViewWidthConstraint?.constant = size.width
        }
    }

    func updateReadPosition() {
        guard !UserDefaults.standard.bool(forKey: "General.incognitoMode") else { return }
        Task {
            // don't add history if there is none and we're at the first page
            if currentPage == 1 {
                let sourceId = chapter.sourceId
                let mangaId = chapter.mangaId
                let chapterId = chapter.id
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
                chapter: chapter,
                progress: currentPage,
                totalPages: toolbarView.totalPages
            )
        }
    }

    func loadChapterList() async {
        chapterList = (try? await SourceManager.shared.source(for: chapter.sourceId)?
            .getChapterList(manga: Manga(sourceId: chapter.sourceId, id: chapter.mangaId))) ?? []
    }

    func loadCurrentChapter() {
        if chapterList.isEmpty {
            Task {
                await loadChapterList()
            }
        }

        let (completed, startPage) = CoreDataManager.shared.getProgress(
            sourceId: chapter.sourceId,
            mangaId: chapter.mangaId,
            chapterId: chapter.id
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
            if chapter.chapterNum != nil, let volumeNum = chapter.volumeNum {
                String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNum)
            } else {
                nil
            }

        let title =
            if let chapterNum = chapter.chapterNum {
                String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
            } else if let volumeNum = chapter.volumeNum {
                String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNum)
            } else {
                chapter.title ?? ""
            }

        navigationItem.setTitle(upper: volume, lower: title)
    }

    func updateMoreButton() {
        let webViewActionTitle = NSLocalizedString("OPEN_WEBSITE", comment: "")
        let webViewActionImage = UIImage(systemName: "safari")
        let webViewAction =
            if let url = chapter.url, let chapterURL = URL(string: url) {
                UIAction(title: webViewActionTitle, image: webViewActionImage) { [weak self] _ in
                    self?.present(SFSafariViewController(url: chapterURL), animated: true)
                }
            } else {
                UIAction(
                    title: webViewActionTitle, image: webViewActionImage, attributes: .disabled
                ) { _ in }
            }

        moreButton.menu = UIMenu(children: [webViewAction])
    }

    @objc func openReaderSettings() {
        let vc = UINavigationController(rootViewController: ReaderSettingsViewController(mangaId: chapter.mangaId))
        present(vc, animated: true)
    }

    @objc func openChapterList() {
        var view = ReaderChapterListView(chapterList: chapterList, chapter: chapter)
        view.chapterSet = { chapter in
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

    // swiftlint:disable:next cyclomatic_complexity
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
        default: // auto
            // use given default reading mode
            if let defaultReadingMode = defaultReadingMode {
                readingMode = defaultReadingMode
            } else if CoreDataManager.shared.hasManga(sourceId: chapter.sourceId, mangaId: chapter.mangaId) {
                // fall back to stored manga viewer
                let sourceMode = CoreDataManager.shared.getMangaSourceReadingMode(
                    sourceId: chapter.sourceId,
                    mangaId: chapter.mangaId
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

        if readingMode == .rtl {
            toolbarView.sliderView.direction = .backward
        } else {
            toolbarView.sliderView.direction = .forward
        }

        switch readingMode {
        case .ltr, .rtl, .vertical:
            setReader(.paged)
        case .webtoon, .continuous:
            setReader(.scroll)
        }
    }

    func setReader(_ type: Reader) {
        let pageController: ReaderReaderDelegate?
        switch type {
        case .paged:
            if !(reader is ReaderPagedViewController) {
                pageController = ReaderPagedViewController()
            } else {
                pageController = nil
            }
        case .scroll:
            if !(reader is ReaderWebtoonViewController) {
                pageController = ReaderWebtoonViewController()
            } else {
                pageController = nil
            }
        }
        if let pageController = pageController {
            reader?.remove()
            pageController.delegate = self
            reader = pageController
            add(child: pageController)
        }
        reader?.readingMode = readingMode
    }
}

// MARK: - Reader Holding Delegate
extension ReaderViewController: ReaderHoldingDelegate {

    func getChapter() -> Chapter {
        chapter
    }

    func getNextChapter() -> Chapter? {
        guard
            var index = chapterList.firstIndex(of: chapter)
        else {
            return nil
        }

        let skipDuplicates = UserDefaults.standard.bool(forKey: "Reader.skipDuplicateChapters")
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index -= 1
        var nextChapterInList: Chapter?

        while index >= 0 {
            let new = chapterList[index]
            let isDuplicate =
                new.chapterNum == chapter.chapterNum
                && new.volumeNum == chapter.volumeNum
                && (!(new.chapterNum == nil && new.volumeNum == nil) || new.title == chapter.title)

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
            index -= 1
        }
        return nil
    }

    func getPreviousChapter() -> Chapter? {
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
            let isDuplicate =
                new.chapterNum == chapter.chapterNum
                && new.volumeNum == chapter.volumeNum
                && (!(new.chapterNum == nil && new.volumeNum == nil) || new.title == chapter.title)
            if !isDuplicate {
                return new
            }
            if markDuplicates {
                chaptersToMark.append(new)
            }
            index += 1
        }
        return nil
    }

    func setChapter(_ chapter: Chapter) {
        self.chapter = chapter
        self.chaptersToMark = [chapter]
        loadNavbarTitle()
        updateMoreButton()
    }

    func setCurrentPage(_ page: Int) {
        guard page > 0 && page <= toolbarView.totalPages ?? Int.max else { return }
        currentPage = page
        toolbarView.currentPage = page
        toolbarView.updateSliderPosition()
        if page == toolbarView.totalPages {
            setCompleted()
        }
    }

    func setTotalPages(_ pages: Int) {
        toolbarView.totalPages = pages
        activityIndicator.stopAnimating()
    }

    func displayPage(_ page: Int) {
        toolbarView.displayPage(page)
    }

    func setCompleted() {
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            Task {
                await HistoryManager.shared.addHistory(chapters: chaptersToMark)
            }
        }
        if UserDefaults.standard.bool(forKey: "Library.deleteDownloadAfterReading") {
            DownloadManager.shared.delete(chapters: [chapter])
        }
    }
}

// MARK: - Bar Visibility
extension ReaderViewController {

    @objc func toggleBarVisibility() {
        guard let navigationController = navigationController else { return }
        if navigationController.navigationBar.alpha > 0 {
            hideBars()
        } else {
            showBars()
        }
    }

    func showBars() {
        guard let navigationController = navigationController else { return }
        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.statusBarHidden = false
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        } completion: { _ in
            if navigationController.toolbar.isHidden {
                navigationController.toolbar.alpha = 0
                navigationController.toolbar.isHidden = false
            }
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                navigationController.navigationBar.alpha = 1
                navigationController.toolbar.alpha = 1
                self.view.backgroundColor = .systemBackground
            }
        }
    }

    func hideBars() {
        guard let navigationController = navigationController else { return }
        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.statusBarHidden = true
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        } completion: { _ in
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                navigationController.navigationBar.alpha = 0
                navigationController.toolbar.alpha = 0
                self.view.backgroundColor = switch UserDefaults.standard.string(forKey: "Reader.backgroundColor") {
                case "system":
                    .systemBackground
                case "white":
                    .white
                default:
                    .black
                }
            } completion: { _ in
                navigationController.toolbar.isHidden = true
            }
        }
    }
}
