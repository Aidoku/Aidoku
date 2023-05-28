//
//  ReaderPagedViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

class ReaderPagedViewController: BaseObservingViewController {

    let viewModel = ReaderPagedViewModel()

    weak var delegate: ReaderHoldingDelegate?

    var chapter: Chapter?
    var readingMode: ReadingMode = .rtl {
        didSet(oldValue) {
            guard readingMode != oldValue else { return }
            if readingMode == .vertical || oldValue == .vertical {
                pageViewController.remove()
                pageViewController = makePageViewController()
                configure()
            }
            Task {
                await loadChapter(startPage: currentPage)
            }
        }
    }
    var pageViewControllers: [ReaderPageViewController] = []
    var currentPage = 0

    var usesDoublePages = false
    var usesAutoPageLayout = false
    lazy var pagesToPreload = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")

    private var previousChapter: Chapter?
    private var nextChapter: Chapter?

    private lazy var pageViewController = makePageViewController()

    func makePageViewController() -> UIPageViewController {
        UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: readingMode == .vertical ? .vertical : .horizontal,
            options: nil
        )
    }

    override func configure() {
        pageViewController.delegate = self
        pageViewController.dataSource = self
        add(child: pageViewController)

        updatePageLayout()
    }

    override func observe() {
        addObserver(forName: "Reader.pagedPageLayout") { [weak self] _ in
            guard let self = self else { return }
            self.updatePageLayout()
            self.move(toPage: self.currentPage, animated: false)
        }
        addObserver(forName: "Reader.pagesToPreload") { [weak self] notification in
            self?.pagesToPreload = notification.object as? Int
                ?? UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
        }
    }

    func updatePageLayout() {
        usesDoublePages = {
            self.usesAutoPageLayout = false
            switch UserDefaults.standard.string(forKey: "Reader.pagedPageLayout") {
            case "single": return false
            case "double": return true
            case "auto":
                self.usesAutoPageLayout = true
                return self.view.bounds.width > self.view.bounds.height
            default: return false
            }
        }()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if usesAutoPageLayout {
            usesDoublePages = size.width > size.height
            // refresh all pages (TODO: can this be improved?)
            Task {
                await loadChapter(startPage: currentPage)
            }
        }
    }
}

extension ReaderPagedViewController {

    func loadPageControllers(chapter: Chapter) {
        guard !viewModel.pages.isEmpty else { return } // TODO: handle zero pages

        // if transitioning from an adjacent chapter, keep the existing pages
        var firstPageController: ReaderPageViewController?
        var lastPageController: ReaderPageViewController?
        var nextChapterPreviewController: ReaderPageViewController?
        var previousChapterPreviewController: ReaderPageViewController?
        if chapter == previousChapter {
            lastPageController = pageViewControllers.first
            nextChapterPreviewController = pageViewControllers[2]
        } else if chapter == nextChapter {
            firstPageController = pageViewControllers.last
            previousChapterPreviewController = pageViewControllers[pageViewControllers.count - 3]
        }

        pageViewControllers = []

        previousChapter = delegate?.getPreviousChapter()

        // last page of previous chapter
        if previousChapter != nil {
            if let previousChapterPreviewController = previousChapterPreviewController {
                pageViewControllers.append(previousChapterPreviewController)
            } else {
                let page = ReaderPageViewController(type: .page)
                page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                pageViewControllers.append(page)
            }
        }

        // previous chapter transition page
        let previousInfoController = ReaderPageViewController(type: .info(.previous))
        previousInfoController.currentChapter = chapter
        previousInfoController.previousChapter = previousChapter
        pageViewControllers.append(previousInfoController)

        // chapter pages
        let startPos = firstPageController != nil ? 1 : 0
        let endPos = viewModel.pages.count - (lastPageController != nil ? 1 : 0)

        if let firstPageController = firstPageController {
            pageViewControllers.append(firstPageController)
        }

        for _ in startPos..<endPos {
            let page = ReaderPageViewController(type: .page)
            page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
            pageViewControllers.append(page)
        }

        if let lastPageController = lastPageController {
            pageViewControllers.append(lastPageController)
        }

        nextChapter = delegate?.getNextChapter()

        // next chapter transition page
        let nextInfoController = ReaderPageViewController(type: .info(.next))
        nextInfoController.currentChapter = chapter
        nextInfoController.nextChapter = nextChapter
        pageViewControllers.append(nextInfoController)

        // first page of next chapter
        if nextChapter != nil {
            if let nextChapterPreviewController = nextChapterPreviewController {
                pageViewControllers.append(nextChapterPreviewController)
            } else {
                let page = ReaderPageViewController(type: .page)
                page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                pageViewControllers.append(page)
            }
        }
    }

    func move(toPage page: Int, animated: Bool) {
        guard page <= viewModel.pages.count && page > 0 else {
            return
        }

        let vcIndex = page + (previousChapter != nil ? 1 : 0)
        var targetViewController: UIViewController?

        if usesDoublePages && vcIndex + 1 < pageViewControllers.count - (nextChapter != nil ? 1 : 0) - 1 {
            let firstPage = pageViewControllers[vcIndex]
            let secondPage = pageViewControllers[vcIndex + 1]
            if case .page = firstPage.type, case .page = secondPage.type {
                targetViewController = ReaderDoublePageViewController(
                    firstPage: firstPage,
                    secondPage: secondPage,
                    direction: readingMode == .rtl ? .rtl : .ltr
                )
            }
        } else {
            targetViewController = pageViewControllers[vcIndex]
        }

        guard let targetViewController = targetViewController else {
            return
        }

        pageViewController.setViewControllers(
            [targetViewController],
            direction: .forward,
            animated: animated
        ) { completed in
            self.pageViewController(
                self.pageViewController,
                didFinishAnimating: true,
                previousViewControllers: [],
                transitionCompleted: completed
            )
        }
    }

    func loadPage(at index: Int) {
        guard index > 0, index <= viewModel.pages.count else { return }
        let vcIndex = index + (previousChapter != nil ? 1 : 0)
        pageViewControllers[vcIndex].setPage(viewModel.pages[index - 1], sourceId: chapter?.sourceId ?? "")
    }

    func loadPages(in range: ClosedRange<Int>) {
        for i in range {
            guard i > 0 else { continue }
            guard i <= viewModel.pages.count else { break }
            let vcIndex = i + (previousChapter != nil ? 1 : 0)
            pageViewControllers[vcIndex].setPage(viewModel.pages[i - 1], sourceId: chapter?.sourceId ?? "")
        }
    }

    enum PagePosition {
        case first
        case second
    }

    func getIndex(of viewController: UIViewController, pos: PagePosition = .first) -> Int? {
        var currentIndex: Int?
        if let viewController = viewController as? ReaderPageViewController {
            currentIndex = pageViewControllers.firstIndex(of: viewController)
        } else if let viewController = viewController as? ReaderDoublePageViewController {
            currentIndex = pageViewControllers.firstIndex(
                of: pos == .first
                    ? viewController.firstPageController
                    : viewController.secondPageController
            )
        }
        return currentIndex
    }

    func pageIndex(from index: Int) -> Int {
        index + (previousChapter != nil ? -1 : 0)
    }
}

// MARK: - Reader Delegate
extension ReaderPagedViewController: ReaderReaderDelegate {

    func sliderMoved(value: CGFloat) {
        let page = Int(round(value * CGFloat(viewModel.pages.count - 1))) + 1
        delegate?.displayPage(page)
    }

    func sliderStopped(value: CGFloat) {
        let page = Int(round(value * CGFloat(viewModel.pages.count - 1))) + 1
        move(toPage: page, animated: false)
    }

    func setChapter(_ chapter: Chapter, startPage: Int) {
        self.chapter = chapter
        Task {
            await loadChapter(startPage: startPage)
        }
    }

    func loadChapter(startPage: Int) async {
        guard let chapter = chapter else { return }
        await viewModel.loadPages(chapter: chapter)
        delegate?.setTotalPages(viewModel.pages.count)
        if viewModel.pages.isEmpty {
            let alert = UIAlertController(
                title: NSLocalizedString("FAILED_CHAPTER_LOAD", comment: ""),
                message: NSLocalizedString("FAILED_CHAPTER_LOAD_INFO", comment: ""),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
            present(alert, animated: true)
        } else {
            await MainActor.run {
                self.loadPageControllers(chapter: chapter)
                var startPage = startPage
                if startPage < 1 {
                    startPage = 1
                } else if startPage > viewModel.pages.count {
                    startPage = viewModel.pages.count
                }
                self.move(toPage: startPage, animated: false)
            }
        }
    }

    func loadPreviousChapter() {
        guard let previousChapter = previousChapter else { return }
        delegate?.setChapter(previousChapter)
        setChapter(previousChapter, startPage: Int.max)
    }

    func loadNextChapter() {
        guard let nextChapter = nextChapter else { return }
        delegate?.setChapter(nextChapter)
        setChapter(nextChapter, startPage: 1)
    }
}

// MARK: - Page Controller Delegate
extension ReaderPagedViewController: UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard
            completed,
            let viewController = pageViewController.viewControllers?.first,
            let currentIndex = getIndex(of: viewController, pos: .first),
            pagesToPreload > 0
        else {
            return
        }
        let page = currentIndex + (previousChapter != nil ? -1 : 0)
        switch page {
        case -1: // previous chapter last page
            // move previous
            loadPreviousChapter()

        case 0: // previous chapter transition page
            // preload previous
            if let previousChapter = previousChapter {
                Task {
                    await viewModel.preload(chapter: previousChapter)
                    if currentIndex > 0, let lastPage = viewModel.preloadedPages.last {
                        pageViewControllers[currentIndex - 1].setPage(lastPage, sourceId: previousChapter.sourceId)
                    }
                }
            }

        case viewModel.pages.count + 1: // next chapter transition page
            delegate?.setCurrentPage(viewModel.pages.count)
            // preload next
            if let nextChapter = nextChapter {
                Task {
                    await viewModel.preload(chapter: nextChapter)
                    if currentIndex + 1 < pageViewControllers.count, let firstPage = viewModel.preloadedPages.first {
                        pageViewControllers[currentIndex + 1].setPage(firstPage, sourceId: nextChapter.sourceId)
                    }
                }
            }

        case viewModel.pages.count + 2: // next chapter first page
            // move next
            loadNextChapter()

        default:
            currentPage = page
            delegate?.setCurrentPage(page)
            // preload 1 before and pagesToPreload ahead
            loadPages(in: page - 1 - (usesDoublePages ? 1 : 0)...page + pagesToPreload + (usesDoublePages ? 1 : 0))
        }
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        for controller in pendingViewControllers {
            if let controller = controller as? ReaderDoublePageViewController {
                if let first = getIndex(of: controller, pos: .first) {
                    let index = pageIndex(from: first) - 1
                    guard index >= 0, index < viewModel.pages.count else { break }
                    controller.setPage(viewModel.pages[index], for: .first)
                }
                if let second = getIndex(of: controller, pos: .second) {
                    let index = pageIndex(from: second) - 1
                    guard index >= 0, index < viewModel.pages.count else { break }
                    controller.setPage(viewModel.pages[index], for: .second)
                }
            } else {
                guard let index = getIndex(of: controller) else { continue }
                loadPage(at: index)
            }
        }
    }
}

// MARK: - Page Controller Data Source
extension ReaderPagedViewController: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        switch readingMode {
        case .rtl:
            return getPageController(before: viewController)
        case .ltr, .vertical:
            return getPageController(after: viewController)
        default:
            return nil
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        switch readingMode {
        case .rtl:
            return getPageController(after: viewController)
        case .ltr, .vertical:
            return getPageController(before: viewController)
        default:
            return nil
        }
    }

    func getPageController(after viewController: UIViewController) -> UIViewController? {
        guard let currentIndex = getIndex(of: viewController, pos: .second) else {
            return nil
        }
        if currentIndex + 1 < pageViewControllers.count {
            // check for double page layout
            if usesDoublePages && currentIndex + 2 < pageViewControllers.count {
                let firstPage = pageViewControllers[currentIndex + 1]
                let secondPage = pageViewControllers[currentIndex + 2]
                // make sure both pages are not info pages
                if case .page = firstPage.type, case .page = secondPage.type {
                    return ReaderDoublePageViewController(
                        firstPage: firstPage,
                        secondPage: secondPage,
                        direction: readingMode == .rtl ? .rtl : .ltr
                    )
                }
            }
            return pageViewControllers[currentIndex + 1]
        }
        return nil
    }

    func getPageController(before viewController: UIViewController) -> UIViewController? {
        guard let currentIndex = getIndex(of: viewController, pos: .first) else {
            return nil
        }
        if currentIndex - 1 >= 0 {
            // check for double page layout
            if usesDoublePages && currentIndex - 2 >= 0 {
                let firstPage = pageViewControllers[currentIndex - 2]
                let secondPage = pageViewControllers[currentIndex - 1]
                // make sure both pages are not info pages
                if case .page = firstPage.type, case .page = secondPage.type {
                    return ReaderDoublePageViewController(
                        firstPage: firstPage,
                        secondPage: secondPage,
                        direction: readingMode == .rtl ? .rtl : .ltr
                    )
                }
            }
            return pageViewControllers[currentIndex - 1]
        }
        return nil
    }
}

// MARK: - Context Menu Delegate
extension ReaderPagedViewController: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            UserDefaults.standard.bool(forKey: "Reader.saveImageOption"),
            let pageView = interaction.view as? UIImageView,
            pageView.image != nil
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            let saveToPhotosAction = UIAction(
                title: NSLocalizedString("SAVE_TO_PHOTOS", comment: ""),
                image: UIImage(systemName: "photo")
            ) { _ in
                if let image = pageView.image {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }

            let shareAction = UIAction(
                title: NSLocalizedString("SHARE", comment: ""),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                if let image = pageView.image {
                    let items = [image]
                    let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)

                    activityController.popoverPresentationController?.sourceView = self.view
                    activityController.popoverPresentationController?.sourceRect = CGRect(origin: location, size: .zero)

                    self.present(activityController, animated: true)
                }
            }

            return UIMenu(title: "", children: [saveToPhotosAction, shareAction])
        })
    }
}
