//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import UIKit
import SwiftUI

class ReaderViewController: BaseObservingViewController {

    enum Reader {
        case paged
        case scroll
    }

    var chapter: Chapter
    var readingMode: ReadingMode = .rtl

    var chapterList: [Chapter] = []
    var currentPage = 1

    weak var reader: ReaderReaderDelegate?

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

    init(chapter: Chapter, chapterList: [Chapter] = []) {
        self.chapter = chapter
        self.chapterList = chapterList
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
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis"),
                style: .plain,
                target: nil,
                action: nil
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "textformat.size"),
                style: .plain,
                target: self,
                action: #selector(openReaderSettings)
            )
        ]
        navigationItem.rightBarButtonItems?.first?.isEnabled = false

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
        setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode"))

        // load chapter list
        Task {
            await loadCurrentChapter()
        }
    }

    override func constrain() {
        toolbarViewWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func observe() {
        addObserver(forName: "Reader.readingMode") { [weak self] _ in
            guard let self = self else { return }
            self.setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode"))
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard currentPage >= 1 else { return }
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            Task {
                if currentPage == 1 && !CoreDataManager.shared.hasHistory(
                    sourceId: chapter.sourceId,
                    mangaId: chapter.mangaId,
                    chapterId: chapter.id
                ) {
                    // don't add history if there is none and we're at the first page
                    return
                }
                await CoreDataManager.shared.setRead(sourceId: chapter.sourceId, mangaId: chapter.mangaId)
                await CoreDataManager.shared.setProgress(
                    currentPage,
                    sourceId: chapter.sourceId,
                    mangaId: chapter.mangaId,
                    chapterId: chapter.id
                )
                NotificationCenter.default.post(name: NSNotification.Name("updateLibrary"), object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            self.toolbarViewWidthConstraint?.constant = size.width
        }
    }

    func loadChapterList() async {
        chapterList = (try? await SourceManager.shared.source(for: chapter.sourceId)?
            .getChapterList(manga: Manga(sourceId: chapter.sourceId, id: chapter.mangaId))) ?? []
    }

    func loadCurrentChapter() async {
        if chapterList.isEmpty {
            await loadChapterList()
        }

        let startPage = CoreDataManager.shared.getProgress(
            sourceId: chapter.sourceId,
            mangaId: chapter.mangaId,
            chapterId: chapter.id
        )
        currentPage = startPage
        reader?.setChapter(chapter, startPage: startPage)
    }

    func loadNavbarTitle() {
        navigationItem.setTitle(
            upper: chapter.volumeNum ?? 0 != 0 ? String(format: NSLocalizedString("VOLUME_X", comment: ""), chapter.volumeNum!) : nil,
            lower: String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapter.chapterNum ?? 0)
        )
    }

    @objc func openReaderSettings() {
        let vc = UINavigationController(rootViewController: ReaderSettingsViewController())
        present(vc, animated: true)
    }

    @objc func openChapterList() {
        var view = ReaderChapterListView(chapterList: chapterList, chapter: chapter)
        view.chapterSet = { chapter in
            self.setChapter(chapter)
            Task {
                await self.loadCurrentChapter()
            }
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
        default:
            // use source's given reading mode
            let sourceMode = CoreDataManager.shared.getMangaSourceReadingMode(sourceId: chapter.sourceId, mangaId: chapter.mangaId)
            if let mode = ReadingMode(rawValue: sourceMode) {
                readingMode = mode
            } else {
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
        // find next non-duplicate chapter
        index -= 1
        while index >= 0 {
            let new = chapterList[index]
            if new.chapterNum != chapter.chapterNum || new.volumeNum != chapter.volumeNum {
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
        index += 1
        while index < chapterList.count {
            let new = chapterList[index]
            if new.chapterNum != chapter.chapterNum || new.volumeNum != chapter.volumeNum {
                return new
            }
            index += 1
        }
        return nil
    }

    func setChapter(_ chapter: Chapter) {
        self.chapter = chapter
        loadNavbarTitle()
    }

    func setCurrentPage(_ page: Int) {
        guard page > 0 && page <= toolbarView.totalPages ?? Int.max else { return }
        currentPage = page
        toolbarView.currentPage = page
        toolbarView.updateSliderPosition()
        if page == toolbarView.totalPages {
            setCompleted(true, page: page)
        }
    }

    func setTotalPages(_ pages: Int) {
        toolbarView.totalPages = pages
        activityIndicator.stopAnimating()
    }

    func displayPage(_ page: Int) {
        toolbarView.displayPage(page)
    }

    func setCompleted(_ completed: Bool = true, page: Int? = nil) {
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            Task {
                await CoreDataManager.shared.setCompleted(
                    completed,
                    progress: page,
                    sourceId: chapter.sourceId,
                    mangaId: chapter.mangaId,
                    chapterId: chapter.id
                )
                await TrackerManager.shared.setCompleted(chapter: chapter)
            }
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
                self.view.backgroundColor = .black
            } completion: { _ in
                navigationController.toolbar.isHidden = true
            }
        }
    }
}
