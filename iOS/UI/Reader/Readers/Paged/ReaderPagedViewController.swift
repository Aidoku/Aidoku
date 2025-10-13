//
//  ReaderPagedViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import AidokuRunner
import UIKit

class ReaderPagedViewController: BaseObservingViewController {

    let viewModel: ReaderPagedViewModel

    weak var delegate: ReaderHoldingDelegate?

    var chapter: AidokuRunner.Chapter?
    var readingMode: ReadingMode = .rtl {
        didSet(oldValue) {
            guard readingMode != oldValue else { return }
            if readingMode == .vertical || oldValue == .vertical {
                pageViewController.remove()
                pageViewController = makePageViewController()
                configure()
            }
            refreshChapter(startPage: currentPage)
        }
    }
    var pageViewControllers: [ReaderPageViewController] = []
    var currentPage = 0

    var usesDoublePages = false
    var usesAutoPageLayout = false
    var isolateFirstPageEnabled = UserDefaults.standard.bool(forKey: "Reader.pagedIsolateFirstPage")
    var splitWideImages = UserDefaults.standard.bool(forKey: "Reader.splitWideImages")
    var isolatedPages: Set<Int> = []
    lazy var pagesToPreload = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")

    // Split pages tracking
    var splitPages: [Int: [Page]] = [:]
    var previousPreviewSplitPages: [Page]?
    var nextPreviewSplitPages: [Page]?

    // Track navigation direction for smart split page selection
    private var lastPageIndex = 0
    private var navigationDirection: NavigationDirection = .unknown

    private enum NavigationDirection {
        case forward    // increasing index
        case backward   // decreasing index
        case unknown
    }

    private var previousChapter: AidokuRunner.Chapter?
    private var nextChapter: AidokuRunner.Chapter?

    private lazy var pageViewController = makePageViewController()

    func makePageViewController() -> UIPageViewController {
        UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: readingMode == .vertical ? .vertical : .horizontal,
            options: nil
        )
    }

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
        self.viewModel = ReaderPagedViewModel(source: source, manga: manga)
        super.init()
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
        addObserver(forName: "Reader.pagedIsolateFirstPage") { [weak self] _ in
            guard let self else { return }
            guard self.pageViewControllers.count > 2 else { return }

            let oldValue = self.isolateFirstPageEnabled
            let newValue = UserDefaults.standard.bool(forKey: "Reader.pagedIsolateFirstPage")
            self.isolateFirstPageEnabled = newValue

            var adjustedPage = self.currentPage

            if oldValue != newValue {
                let firstPageIndex = 1 + (self.previousChapter != nil ? 1 : 0)
                let isFirstPageAlreadyIsolated = self.pageViewControllers[firstPageIndex].isWideImage || self.isolatedPages.contains(1)

                if !isFirstPageAlreadyIsolated {
                    if newValue && self.currentPage >= 1 {
                        // Enabling isolate first page: shift page forward
                        adjustedPage = self.currentPage + 1
                    } else if !newValue && self.currentPage > 1 {
                        // Disabling isolate first page: shift page backward
                        adjustedPage = self.currentPage - 1
                    }

                    // Ensure page stays within valid range
                    adjustedPage = max(1, min(adjustedPage, self.viewModel.pages.count))
                }
            }

            if self.chapter != nil {
                self.refreshChapter(startPage: adjustedPage)
            }
        }
        addObserver(forName: "Reader.pagesToPreload") { [weak self] notification in
            self?.pagesToPreload = notification.object as? Int
                ?? UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
        }
        addObserver(forName: UIApplication.didReceiveMemoryWarningNotification.rawValue) { [weak self] _ in
            // clear pages that aren't in the preload range if we get a memory warning
            guard
                let self,
                let viewController = pageViewController.viewControllers?.first,
                let currentIndex = getIndex(of: viewController, pos: .first)
            else { return }
            let safeRange = max(0, currentIndex - pagesToPreload)...min(pageViewControllers.count - 1, currentIndex + pagesToPreload)
            for (idx, controller) in pageViewControllers.enumerated() where !safeRange.contains(idx) {
                controller.clearPage()
            }
        }
        let refreshSplitPages: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            splitWideImages = UserDefaults.standard.bool(forKey: "Reader.splitWideImages")
            if self.chapter != nil {
                // Calculate the original page index before clearing splits
                let originalPage = self.actualPageIndex(from: self.currentPage)
                // Clear existing split pages when setting changes
                self.splitPages.removeAll()
                // Jump to the original page (keep the same page index)
                self.refreshChapter(startPage: originalPage)
            }
        }
        addObserver(forName: "Reader.splitWideImages", using: refreshSplitPages)
        addObserver(forName: "Reader.reverseSplitOrder", using: refreshSplitPages)
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
            refreshChapter(startPage: currentPage)
        }
    }
}

extension ReaderPagedViewController {
    // swiftlint:disable:next cyclomatic_complexity
    func loadPageControllers(chapter: AidokuRunner.Chapter) {
        guard !viewModel.pages.isEmpty else { return } // TODO: handle zero pages

        // if transitioning from an adjacent chapter, keep the existing pages
        var firstPageController: ReaderPageViewController?
        var lastPageController: ReaderPageViewController?
        var nextChapterPreviewController: ReaderPageViewController?
        var previousChapterPreviewController: ReaderPageViewController?
        if chapter == previousChapter {
            lastPageController = pageViewControllers.first
            nextChapterPreviewController = pageViewControllers[2]

            if let previousPreviewSplitPages {
                splitPages[viewModel.pages.count] = previousPreviewSplitPages
                self.previousPreviewSplitPages = nil
            }
        } else if chapter == nextChapter {
            firstPageController = pageViewControllers.last
            previousChapterPreviewController = pageViewControllers[pageViewControllers.count - 3]

            if let nextPreviewSplitPages {
                splitPages[1] = nextPreviewSplitPages
                self.nextPreviewSplitPages = nil
            }
        }

        pageViewControllers = []

        previousChapter = delegate?.getPreviousChapter()

        // last page of previous chapter
        if previousChapter != nil {
            if let previousChapterPreviewController {
                pageViewControllers.append(previousChapterPreviewController)
            } else {
                let page = ReaderPageViewController(type: .page)
                page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                if let previousPreviewSplitPages, let splitPage = previousPreviewSplitPages.last {
                    // if we have split pages for the preview, use the last split page
                    page.setPage(splitPage, sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey)
                } else {
                    // Only set aspect ratio callback for double page layout
                    if usesDoublePages {
                        page.onAspectRatioUpdated = { [weak self] in
                            self?.handleAspectRatioUpdate()
                        }
                    } else if splitWideImages {
                        // Set up image load completion callback for splitting
                        let originalPageIndex = 0
                        page.onImageisWideImage = { [weak self, weak page] isWide in
                            guard let self, let page else { return }
                            if isWide && self.splitPages[originalPageIndex] == nil {
                                self.checkAndSplitWideImage(at: originalPageIndex, controller: page)
                            }
                        }
                    }
                }
                pageViewControllers.append(page)
            }
        }

        // previous chapter transition page
        let previousInfoController = ReaderPageViewController(type: .info(.previous))
        let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
        previousInfoController.currentChapter = chapter.toOld(sourceId: sourceId, mangaId: viewModel.manga.key)
        previousInfoController.previousChapter = previousChapter?.toOld(sourceId: sourceId, mangaId: viewModel.manga.key)
        pageViewControllers.append(previousInfoController)

        // chapter pages
        let startPos = firstPageController != nil ? 1 : 0
        let endPos = viewModel.pages.count - (lastPageController != nil ? 1 : 0)

        if let firstPageController {
            if let splitPageArray = splitPages[1] {
                for splitPage in splitPageArray {
                    let page = ReaderPageViewController(type: .page)
                    page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                    page.setPage(splitPage, sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey)
                    pageViewControllers.append(page)
                }
            } else {
                pageViewControllers.append(firstPageController)
            }
        }

        for i in startPos..<endPos {
            let originalPageIndex = i + 1

            // Check if this page has been split
            if let splitPageArray = splitPages[originalPageIndex] {
                // Create controllers for split pages
                for splitPage in splitPageArray {
                    let page = ReaderPageViewController(type: .page)
                    page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                    // Set the split page directly
                    page.setPage(splitPage, sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey)
                    pageViewControllers.append(page)
                }
            } else {
                // Create normal page controller
                let page = ReaderPageViewController(type: .page)
                page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                // Only set aspect ratio callback for double page layout
                if usesDoublePages {
                    page.onAspectRatioUpdated = { [weak self] in
                        self?.handleAspectRatioUpdate()
                    }
                } else if splitWideImages {
                    // Set up image load completion callback for splitting
                    page.onImageisWideImage = { [weak self, weak page] isWide in
                        guard let self, let page else { return }
                        if isWide && self.splitPages[originalPageIndex] == nil {
                            self.checkAndSplitWideImage(at: originalPageIndex, controller: page)
                        }
                    }
                }
                pageViewControllers.append(page)
            }
        }

        if let lastPageController {
            if let splitPageArray = splitPages[viewModel.pages.count] {
                for splitPage in splitPageArray {
                    let page = ReaderPageViewController(type: .page)
                    page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                    page.setPage(splitPage, sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey)
                    pageViewControllers.append(page)
                }
            } else {
                pageViewControllers.append(lastPageController)
            }
        }

        nextChapter = delegate?.getNextChapter()

        // next chapter transition page
        let nextInfoController = ReaderPageViewController(type: .info(.next))
        nextInfoController.currentChapter = chapter.toOld(sourceId: sourceId, mangaId: viewModel.manga.key)
        nextInfoController.nextChapter = nextChapter?.toOld(sourceId: sourceId, mangaId: viewModel.manga.key)
        pageViewControllers.append(nextInfoController)

        // first page of next chapter
        if nextChapter != nil {
            if let nextChapterPreviewController {
                pageViewControllers.append(nextChapterPreviewController)
            } else {
                let page = ReaderPageViewController(type: .page)
                page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                if let nextPreviewSplitPages, let splitPage = nextPreviewSplitPages.first {
                    page.setPage(splitPage, sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey)
                } else {
                    // Only set aspect ratio callback for double page layout
                    if usesDoublePages {
                        page.onAspectRatioUpdated = { [weak self] in
                            self?.handleAspectRatioUpdate()
                        }
                    } else if splitWideImages {
                        // Set up image load completion callback for splitting
                        let originalPageIndex = endPos + 3
                        page.onImageisWideImage = { [weak self, weak page] isWide in
                            guard let self, let page else { return }
                            if isWide && self.splitPages[originalPageIndex] == nil {
                                self.checkAndSplitWideImage(at: originalPageIndex, controller: page)
                            }
                        }
                    }
                }
                pageViewControllers.append(page)
            }
        }
    }

    func move(toPage page: Int, animated: Bool) {
        let page = min(max(page, 0), displayPageCount + 1)

        let vcIndex = page + (previousChapter != nil ? 1 : 0)
        var targetViewController: UIViewController?

        if usesDoublePages && vcIndex + 1 < pageViewControllers.count - (nextChapter != nil ? 1 : 0) - 1 {
            let firstPage = pageViewControllers[vcIndex]
            let secondPage = pageViewControllers[vcIndex + 1]
            if case .page = firstPage.type, case .page = secondPage.type {
                targetViewController =  createPageController(
                    firstPage: firstPage,
                    secondPage: secondPage,
                    page: page
                )
            }
        } else {
            targetViewController = pageViewControllers[vcIndex]
        }

        guard let targetViewController = targetViewController else {
            return
        }

        let forward = switch readingMode {
            case .rtl: currentPage > page
            default: currentPage < page
        }

        pageViewController.setViewControllers(
            [targetViewController],
            direction: forward ? .forward : .reverse,
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
        guard index > 0, index <= displayPageCount else { return }

        // Convert display index to actual page index and split page index
        let actualPageIndex = actualPageIndex(from: index)
        guard actualPageIndex > 0, actualPageIndex <= viewModel.pages.count else { return }

        let vcIndex = index + (previousChapter != nil ? 1 : 0)

        // Check if this is a split page
        if let splitPageArray = splitPages[actualPageIndex] {
            // Calculate which split page this is
            var splitIndex = 0
            var currentDisplayIndex = 0

            for i in 1...actualPageIndex {
                currentDisplayIndex += 1
                if let splitArray = splitPages[i], i < actualPageIndex {
                    currentDisplayIndex += splitArray.count - 1
                } else if i == actualPageIndex {
                    splitIndex = index - (currentDisplayIndex - 1) - 1
                    break
                }
            }

            if splitIndex < splitPageArray.count {
                pageViewControllers[vcIndex].setPage(
                    splitPageArray[splitIndex],
                    sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey
                )
            }
        } else {
            // Normal page - load the page
            let pageController = pageViewControllers[vcIndex]
            pageController.setPage(
                viewModel.pages[actualPageIndex - 1],
                sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey
            )
        }
    }

    func loadPages(in range: ClosedRange<Int>) {
        for i in range {
            guard i > 0 else { continue }
            guard i <= displayPageCount else { break }
            loadPage(at: i)
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

    /// Convert display page index to actual page index, accounting for split pages
    func actualPageIndex(from displayIndex: Int) -> Int {
        let actualIndex = displayIndex
        var currentDisplayIndex = 0

        for i in 1...viewModel.pages.count {
            currentDisplayIndex += 1
            if let splitPageArray = splitPages[i] {
                currentDisplayIndex += splitPageArray.count - 1 // additional pages from split
            }

            if currentDisplayIndex >= displayIndex {
                return i
            }
        }

        return actualIndex
    }

    /// Get the display page count including split pages
    var displayPageCount: Int {
        var count = viewModel.pages.count
        for (_, splitPageArray) in splitPages {
            count += splitPageArray.count - 1 // add extra pages from splits
        }
        return count
    }

    /// Check if double page controller should be created (wide images don't combine with other pages)
    private func shouldCreateDoublePageController(firstPage: ReaderPageViewController, secondPage: ReaderPageViewController, page: Int) -> Bool {
        // If either page is wide image, don't create double page
        if firstPage.isWideImage || secondPage.isWideImage {
            return false
        }
        return true
    }

    private func createPageController(
        firstPage: ReaderPageViewController,
        secondPage: ReaderPageViewController,
        page: Int,
        forBefore: Bool = false
    ) -> UIViewController {
        if shouldCreateDoublePageController(firstPage: firstPage, secondPage: secondPage, page: page) {
            if isolateFirstPageEnabled && page == 1 {
                // For isolate first page: show single page for page 1
                return forBefore ? secondPage : firstPage
            } else if isolatedPages.contains(page) {
                // For isolated page: show single page
                return forBefore ? secondPage : firstPage
            } else {
                // Normal double page combination
                return ReaderDoublePageViewController(
                    firstPage: firstPage,
                    secondPage: secondPage,
                    direction: readingMode == .rtl ? .rtl : .ltr
                )
            }
        } else {
            // If double page should not be created, use first page
            return forBefore ? secondPage : firstPage
        }
    }

    /// Handle aspect ratio update - reload current page if wide image detected in double page view
    private func handleAspectRatioUpdate() {
        guard
            let currentViewController = pageViewController.viewControllers?.first,
            let currentIndex = getIndex(of: currentViewController)
        else { return }

        // Check if current view is a double page controller
        if let doublePageController = currentViewController as? ReaderDoublePageViewController {
            // Check if either page in the double page is now detected as wide
            if doublePageController.firstPageController.isWideImage || doublePageController.secondPageController.isWideImage {
                // Reload current page to show single page instead
                let page = pageIndex(from: currentIndex)
                move(toPage: page, animated: false)
            }
        }
    }

    /// Check if a wide image should be split and handle the splitting
    private func checkAndSplitWideImage(at pageIndex: Int, controller: UIViewController) {
        guard
            !usesDoublePages,
            splitWideImages,
            let pageController = controller as? ReaderPageViewController,
            pageController.isWideImage,
            splitPages[pageIndex] == nil,
            let splitResult = pageController.pageView?.splitImage(),
            let leftImage = splitResult.left,
            let rightImage = splitResult.right
        else {
            return
        }

        // Create split pages
        let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
        let chapterId = chapter?.id ?? ""
        let reverseOrder = UserDefaults.standard.bool(forKey: "Reader.reverseSplitOrder")

        let leftPage = Page(sourceId: sourceId, chapterId: chapterId, index: pageIndex, image: leftImage)
        let rightPage = Page(sourceId: sourceId, chapterId: chapterId, index: pageIndex, image: rightImage)

        let splitPagesGroup = reverseOrder ? [leftPage, rightPage] : [rightPage, leftPage]

        if pageIndex <= 0 {
            previousPreviewSplitPages = splitPagesGroup
            return
        } else if pageIndex >= displayPageCount {
            nextPreviewSplitPages = splitPagesGroup
            return
        } else {
            splitPages[pageIndex] = splitPagesGroup
        }

        // After splitting, we need to maintain the user's current viewing position
        // Since the page structure has changed, we refresh and stay at the current display position
        if chapter != nil {
            // Calculate the correct display page after splitting
            let currentActualPage = actualPageIndex(from: currentPage)
            var targetDisplayPage = currentPage

            if pageIndex == viewModel.pages.count {
                // For last page, jump to last split page
                targetDisplayPage = currentPage + (splitPages[pageIndex]?.count ?? 1)
            } else if pageIndex == currentActualPage {
                // We're splitting the current page
                // Smart jump based on navigation direction (index size)
                switch navigationDirection {
                    case .forward:
                        // User came from smaller index
                        // Jump to first split page
                        targetDisplayPage = currentPage
                    case .backward:
                        // User came from larger index
                        // Jump to second split page
                        targetDisplayPage = currentPage + 1
                    case .unknown:
                        // Default to first split page when direction is unknown
                        targetDisplayPage = currentPage
                }
            } else if pageIndex < currentActualPage {
                // We're splitting a page before the current page
                // The split adds one extra page, so increment display position
                targetDisplayPage = currentPage + 1
            }

            // Store the target page before refresh
            let targetPage = targetDisplayPage

            // Refresh chapter to rebuild page controllers with split pages
            refreshChapter(startPage: targetPage)
        }
    }
}

// MARK: - Reader Delegate
extension ReaderPagedViewController: ReaderReaderDelegate {
    func moveLeft() {
        if
            let currentViewController = pageViewController.viewControllers?.first,
            let targetViewController = pageViewController(pageViewController, viewControllerBefore: currentViewController)
        {
            let animated = UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")
            pageViewController.setViewControllers(
                [targetViewController],
                direction: .reverse,
                animated: animated
            ) { completed in
                self.pageViewController(
                    self.pageViewController,
                    didFinishAnimating: true,
                    previousViewControllers: [currentViewController],
                    transitionCompleted: completed
                )
            }
        }
    }

    func moveRight() {
        if
            let currentViewController = pageViewController.viewControllers?.last,
            let targetViewController = pageViewController(pageViewController, viewControllerAfter: currentViewController)
        {
            let animated = UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")
            pageViewController.setViewControllers(
                [targetViewController],
                direction: .forward,
                animated: animated
            ) { completed in
                self.pageViewController(
                    self.pageViewController,
                    didFinishAnimating: true,
                    previousViewControllers: [currentViewController],
                    transitionCompleted: completed
                )
            }
        }
    }

    func sliderMoved(value: CGFloat) {
        let displayPage = Int(round(value * CGFloat(displayPageCount - 1))) + 1
        let actualPage = actualPageIndex(from: displayPage)
        delegate?.displayPage(actualPage)
    }

    func sliderStopped(value: CGFloat) {
        let displayPage = Int(round(value * CGFloat(displayPageCount - 1))) + 1
        move(toPage: displayPage, animated: false)
    }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {
        self.chapter = chapter
        Task {
            await loadChapter(startPage: startPage)
        }
    }

    func loadChapter(startPage: Int) async {
        guard let chapter else { return }
        await viewModel.loadPages(chapter: chapter)
        delegate?.setPages(viewModel.pages)
        if !viewModel.pages.isEmpty {
            await MainActor.run {
                // clear isolated and split pages when switching chapters
                isolatedPages = []
                splitPages = [:]

                loadPageControllers(chapter: chapter)

                let displayPageCount = displayPageCount
                var startPage = startPage
                if startPage < 1 {
                    startPage = 1
                } else if startPage > displayPageCount {
                    startPage = displayPageCount
                }
                // if we're moving to the previous chapter and the final page is split, move to the true final page
                if let targetSplitPages = splitPages[startPage] {
                    if navigationDirection == .backward {
                        startPage += targetSplitPages.count - 1
                    }
                }
                move(toPage: startPage, animated: false)
            }
        }
    }

    func refreshChapter(startPage: Int) {
        guard let chapter else { return }

        loadPageControllers(chapter: chapter)
        let displayPageCount = displayPageCount
        var startPage = startPage
        if startPage < 1 {
            startPage = 1
        } else if startPage > displayPageCount {
            startPage = displayPageCount
        }

        self.move(toPage: startPage, animated: false)
    }

    func loadPreviousChapter() {
        guard let previousChapter else { return }
        nextPreviewSplitPages = splitPages[1]
        delegate?.setChapter(previousChapter)
        setChapter(previousChapter, startPage: Int.max)
    }

    func loadNextChapter() {
        guard let nextChapter else { return }
        previousPreviewSplitPages = splitPages[viewModel.pages.count]
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
            delegate?.setCurrentPage(0)
            // preload previous
            if let previousChapter = previousChapter {
                Task {
                    await viewModel.preload(chapter: previousChapter)
                    if currentIndex > 0, let lastPage = viewModel.preloadedPages.last {
                        pageViewControllers[currentIndex - 1].setPage(
                            lastPage,
                            sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey
                        )
                    }
                }
            }

        case displayPageCount + 1: // next chapter transition page
            delegate?.setCurrentPage(displayPageCount + 1)
            // preload next
            if let nextChapter = nextChapter {
                Task {
                    await viewModel.preload(chapter: nextChapter)
                    if currentIndex + 1 < pageViewControllers.count, let firstPage = viewModel.preloadedPages.first {
                        pageViewControllers[currentIndex + 1].setPage(
                            firstPage,
                            sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey
                        )
                    }
                }
            }

        case displayPageCount + 2: // next chapter first page
            // move next
            loadNextChapter()

        default:
            // Track navigation direction for smart split page selection
            if page > lastPageIndex {
                navigationDirection = .forward
            } else if page < lastPageIndex {
                navigationDirection = .backward
            }
            lastPageIndex = page
            currentPage = page

            if usesDoublePages {
                // For double pages, report the actual page range
                let actualPage = actualPageIndex(from: page)
                delegate?.setCurrentPages(actualPage...actualPage + 1)
            } else {
                // For single pages, report the actual page index
                let actualPage = actualPageIndex(from: page)
                delegate?.setCurrentPage(actualPage)
            }
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
                    return createPageController(
                        firstPage: firstPage,
                        secondPage: secondPage,
                        page: pageIndex(from: currentIndex + 1)
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
                    return createPageController(
                        firstPage: firstPage,
                        secondPage: secondPage,
                        page: pageIndex(from: currentIndex - 1),
                        forBefore: true
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
            !UserDefaults.standard.bool(forKey: "Reader.disableQuickActions"),
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
                    image.saveToAlbum(viewController: self)
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

            let reloadAction = UIAction(
                title: NSLocalizedString("RELOAD", comment: ""),
                image: UIImage(systemName: "arrow.clockwise")
            ) { _ in
                Task { @MainActor in
                    await self.reloadCurrentPageImage(for: pageView)
                }
            }

            var actions = [saveToPhotosAction, shareAction, reloadAction]

            // Only show isolate page action if using double pages and page is not already isolated
            if self.usesDoublePages {
                var isAlreadyIsolated = false
                for (index, pageViewController) in self.pageViewControllers.enumerated() {
                    if
                        case .page = pageViewController.type,
                        let readerPageView = pageViewController.pageView,
                        readerPageView.imageView == pageView
                    {
                        let page = self.pageIndex(from: index)
                        if self.isolatedPages.contains(page) {
                            isAlreadyIsolated = true
                        }
                        break
                    }
                }
                if !isAlreadyIsolated {
                    let isolatePageAction = UIAction(
                        title: NSLocalizedString("SET_AS_SINGLE_PAGE", comment: ""),
                        image: UIImage(systemName: "rectangle.portrait")
                    ) { _ in
                        Task { @MainActor in
                            self.isolateCurrentPage(for: pageView)
                        }
                    }
                    actions.insert(isolatePageAction, at: 2)
                }
            }

            return UIMenu(title: "", children: actions)
        })
    }

    @MainActor
    private func reloadCurrentPageImage(for imageView: UIImageView) async {
        for pageViewController in pageViewControllers {
            if
                case .page = pageViewController.type,
                let readerPageView = pageViewController.pageView,
                readerPageView.imageView == imageView
            {
                let success = await readerPageView.reloadCurrentImage()
                if !success {
                    showReloadError()
                }
                return
            }
        }
    }

    @MainActor
    private func isolateCurrentPage(for imageView: UIImageView) {
        for (index, pageViewController) in pageViewControllers.enumerated() {
            if
                case .page = pageViewController.type,
                let readerPageView = pageViewController.pageView,
                readerPageView.imageView == imageView
            {
                let page = pageIndex(from: index)
                isolatedPages.insert(page)

                refreshChapter(startPage: page)
                return
            }
        }
    }

    private func showReloadError() {
        let alert = UIAlertController(
            title: NSLocalizedString("RELOAD_FAILED"),
            message: NSLocalizedString("RELOAD_FAILED_TEXT"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .default))
        present(alert, animated: true)
    }
}
