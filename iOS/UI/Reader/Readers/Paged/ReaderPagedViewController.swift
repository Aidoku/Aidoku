//
//  ReaderPagedViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import AidokuRunner
import UIKit
import VisionKit

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

    private var usesDoublePages = false
    private var usesAutoPageLayout = false
    private var pageOffsetEnabled = false

    private var pageOffsetKey: String {
        "Reader.pagedPageOffset.\(viewModel.manga.identifier)"
    }

    private var splitWideImages = UserDefaults.standard.bool(forKey: "Reader.splitWideImages")
    private var isolatedPages: Set<Int> = []
    private var manuallyIsolatedPages: Set<Int> = []
    private lazy var pagesToPreload = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")

    // Split pages tracking
    private var actualPageIndices: [Int] = []
    private var splitPages: [Int: [Page]] = [:]
    private var previousPreviewSplitPages: [Page]?
    private var nextPreviewSplitPages: [Page]?

    private var isTransitioning = false
    private var programmaticMove = false
    private var pendingSpreadRebuild = false

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
        addObserver(forName: "Reader.pagesToPreload") { [weak self] notification in
            self?.pagesToPreload = notification.object as? Int
                ?? UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
        }
        addObserver(forName: UIApplication.didReceiveMemoryWarningNotification.rawValue) { [weak self] _ in
            // clear pages that aren't in the preload range if we get a memory warning
            LogManager.logger.warn("Received memory warning")
            Self.clearSplitPageCache()
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
            guard let self, let chapter = self.chapter else { return }
            let actualPage = self.actualPageIndex(from: self.currentPage)
            let wasSplit = self.splitWideImages
            self.splitWideImages = UserDefaults.standard.bool(forKey: "Reader.splitWideImages")
            self.splitPages.removeAll()
            if wasSplit, self.splitWideImages {
                if let key = self.splitPageCacheKey {
                    self.reverseSplitStoreEntries(for: key)
                }
            }
            self.loadPageControllers(chapter: chapter)
            self.resetIsolation()
            let targetPage = max(1, min(self.firstDisplayPage(forActual: actualPage), self.displayPageCount))
            self.move(toPage: targetPage, animated: false)
        }
        addObserver(forName: "Reader.splitWideImages", using: refreshSplitPages)
        addObserver(forName: "Reader.reverseSplitOrder", using: refreshSplitPages)

        if let value = UserDefaults.standard.object(forKey: pageOffsetKey) as? Bool {
            pageOffsetEnabled = value
        } else {
            pageOffsetEnabled = UserDefaults.standard.bool(forKey: "Reader.pagedPageOffset")
        }

        addObserver(forName: pageOffsetKey) { [weak self] _ in
            guard let self, self.chapter != nil else { return }
            let newValue = UserDefaults.standard.bool(forKey: self.pageOffsetKey)

            guard self.pageOffsetEnabled != newValue else { return }
            self.pageOffsetEnabled = newValue

            self.resetIsolation()
            self.refreshChapter(startPage: self.currentPage)
        }
        addObserver(forName: "Reader.pagedPageOffset") { [weak self] _ in
            guard let self, self.chapter != nil else { return }
            // only follow global when no per-manga override exists
            guard UserDefaults.standard.object(forKey: self.pageOffsetKey) == nil else { return }
            let newValue = UserDefaults.standard.bool(forKey: "Reader.pagedPageOffset")

            guard self.pageOffsetEnabled != newValue else { return }
            self.pageOffsetEnabled = newValue

            self.resetIsolation()
            self.refreshChapter(startPage: self.currentPage)
        }

        addObserver(forName: .readerShowingBars) { [weak self] _ in
            self?.setLiveTextButtonHidden(false)
        }
        addObserver(forName: .readerHidingBars) { [weak self] _ in
            self?.setLiveTextButtonHidden(true)
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
            refreshChapter(startPage: currentPage)
        }
    }
}

extension ReaderPagedViewController {
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

        if splitWideImages {
            restoreCachedSplitPages()
        }

        previousChapter = delegate?.getPreviousChapter()

        // last page of previous chapter
        if previousChapter != nil {
            if let previousChapterPreviewController {
                pageViewControllers.append(previousChapterPreviewController)
            } else {
                pageViewControllers.append(
                    makePageController(
                        hasImageCallbacks: true,
                        preloadPage: previousPreviewSplitPages?.last
                    )
                )
            }
        }

        // previous chapter transition page
        let previousInfoController = ReaderPageViewController(type: .info(.previous), delegate: delegate)
        let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
        previousInfoController.currentChapter = chapter.toOld(sourceId: sourceId, mangaId: viewModel.manga.key)
        previousInfoController.previousChapter = previousChapter?.toOld(sourceId: sourceId, mangaId: viewModel.manga.key)
        pageViewControllers.append(previousInfoController)

        // chapter pages
        let startPos = firstPageController != nil ? 1 : 0
        let endPos = viewModel.pages.count - (lastPageController != nil ? 1 : 0)

        if let firstPageController {
            if let splitPageArray = splitPages[1] {
                pageViewControllers.append(contentsOf: splitPageArray.map { makePageController(preloadPage: $0, skipProcessing: true) })
            } else {
                pageViewControllers.append(firstPageController)
            }
        }

        for i in startPos..<endPos {
            let originalPageIndex = i + 1
            if let splitPageArray = splitPages[originalPageIndex] {
                pageViewControllers.append(contentsOf: splitPageArray.map { makePageController(preloadPage: $0, skipProcessing: true) })
            } else {
                pageViewControllers.append(makePageController(hasImageCallbacks: true))
            }
        }

        if let lastPageController {
            if let splitPageArray = splitPages[viewModel.pages.count] {
                pageViewControllers.append(contentsOf: splitPageArray.map { makePageController(preloadPage: $0, skipProcessing: true) })
            } else {
                pageViewControllers.append(lastPageController)
            }
        }

        nextChapter = delegate?.getNextChapter()

        // next chapter transition page
        let nextInfoController = ReaderPageViewController(type: .info(.next), delegate: delegate)
        nextInfoController.currentChapter = chapter.toOld(sourceId: sourceId, mangaId: viewModel.manga.key)
        nextInfoController.nextChapter = nextChapter?.toOld(sourceId: sourceId, mangaId: viewModel.manga.key)
        pageViewControllers.append(nextInfoController)

        // first page of next chapter
        if nextChapter != nil {
            if let nextChapterPreviewController {
                pageViewControllers.append(nextChapterPreviewController)
            } else {
                pageViewControllers.append(
                    makePageController(
                        hasImageCallbacks: true,
                        preloadPage: nextPreviewSplitPages?.first
                    )
                )
            }
        }

        rebuildPageIndices()
    }

    private func makePageController(
        hasImageCallbacks: Bool = false,
        preloadPage: Page? = nil,
        skipProcessing: Bool = false
    ) -> ReaderPageViewController {
        let page = ReaderPageViewController(type: .page, delegate: delegate)
        page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
        if hasImageCallbacks {
            page.onImageisWideImage = { [weak self, weak page] isWide in
                guard let self, let page, isWide else { return }
                guard let vcIndex = self.pageViewControllers.firstIndex(of: page) else { return }
                let liveDisplay = self.pageIndex(from: vcIndex)
                let actualPage = self.actualPageIndex(from: liveDisplay)
                if self.splitWideImages {
                    self.checkAndSplitWideImage(at: actualPage, controller: page)
                } else if
                    self.usesDoublePages,
                    abs(liveDisplay - self.currentPage) <= self.pagesToPreload
                {
                    self.adjustAutoIsolation()
                    if self.isTransitioning {
                        self.pendingSpreadRebuild = true
                    } else {
                        self.move(toPage: self.currentPage, animated: false, resetGesture: true)
                    }
                }
            }
            page.onAspectRatioUpdated = { [weak self, weak page] in
                guard let self, let page else { return }
                self.handleAspectRatioUpdate(from: page)
            }
        }
        if let preloadPage {
            page.setPage(preloadPage, skipProcessing: skipProcessing)
        }
        return page
    }

    func move(toPage page: Int, animated: Bool, resetGesture: Bool = true) {
        let page = min(max(page, 0), displayPageCount + 1)
        let vcIndex = page + (previousChapter != nil ? 1 : 0)
        var targetViewController: UIViewController = pageViewControllers[vcIndex]

        let lastContentIndex = pageViewControllers.count - (nextChapter != nil ? 1 : 0) - 1

        if usesDoublePages && vcIndex + 1 <= lastContentIndex {
            let firstPage = pageViewControllers[vcIndex]
            let secondPage = pageViewControllers[vcIndex + 1]
            if
                case .page = firstPage.type, case .page = secondPage.type,
                spreadStart(for: page) == page,
                let double = createPageController(firstPage: firstPage, secondPage: secondPage, page: page)
            {
                targetViewController = double
            }
        }

        if
            usesDoublePages, !(targetViewController is ReaderDoublePageViewController),
            vcIndex - 1 >= (previousChapter != nil ? 2 : 1)
        {
            let firstPage = pageViewControllers[vcIndex - 1]
            let secondPage = pageViewControllers[vcIndex]
            if case .page = firstPage.type, case .page = secondPage.type {
                let backPage = page - 1
                if
                    spreadStart(for: backPage) == backPage,
                    let double = createPageController(firstPage: firstPage, secondPage: secondPage, page: backPage)
                {
                    targetViewController = double
                }
            }
        }

        let forward = switch readingMode {
            case .rtl: currentPage > page
            default: currentPage < page
        }
        isTransitioning = true
        programmaticMove = true
        currentPage = page

        if !animated, resetGesture {
            for subview in pageViewController.view.subviews {
                if let scrollView = subview as? UIScrollView {
                    scrollView.panGestureRecognizer.isEnabled = false
                    scrollView.panGestureRecognizer.isEnabled = true
                    break
                }
            }
        }

        let previousViewControllers = pageViewController.viewControllers ?? []
        pageViewController.setViewControllers(
            [targetViewController],
            direction: forward ? .forward : .reverse,
            animated: animated
        ) { completed in
            self.pageViewController(
                self.pageViewController,
                didFinishAnimating: true,
                previousViewControllers: previousViewControllers,
                transitionCompleted: completed
            )
        }
    }

    func loadPage(at index: Int) {
        guard index > 0, index <= displayPageCount else { return }

        let actualPageIndex = actualPageIndex(from: index)
        guard actualPageIndex > 0, actualPageIndex <= viewModel.pages.count else { return }

        let vcIndex = index + (previousChapter != nil ? 1 : 0)
        guard vcIndex < pageViewControllers.count else { return }

        let targetVC = pageViewControllers[vcIndex]
        let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey

        if let splitPageArray = splitPages[actualPageIndex] {
            let splitIndex = splitIndex(for: index, actualPageIndex: actualPageIndex)
            if splitIndex < splitPageArray.count {
                targetVC.setPage(splitPageArray[splitIndex], sourceId: sourceId)
            }
        } else {
            targetVC.setPage(viewModel.pages[actualPageIndex - 1], sourceId: sourceId)
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

    private func rebuildPageIndices() {
        guard !viewModel.pages.isEmpty else {
            actualPageIndices = []
            return
        }
        actualPageIndices = (1...viewModel.pages.count).flatMap {
            Array(repeating: $0, count: splitPages[$0]?.count ?? 1)
        }
    }

    /// Convert display page index to actual page index, accounting for split pages
    func actualPageIndex(from displayIndex: Int) -> Int {
        let index = displayIndex - 1
        guard actualPageIndices.indices.contains(index) else { return displayIndex }
        return actualPageIndices[index]
    }

    var displayPageCount: Int {
        actualPageIndices.count
    }

    private func splitIndex(for displayPage: Int, actualPageIndex: Int) -> Int {
        let segmentStart = actualPageIndices.firstIndex(of: actualPageIndex) ?? (displayPage - 1)
        return (displayPage - 1) - segmentStart
    }

    private func isPagePairable(_ page: Int) -> Bool {
        guard page >= 1, page <= displayPageCount else { return false }
        if manuallyIsolatedPages.contains(page) { return false }
        let vcIndex = page + (previousChapter != nil ? 1 : 0)
        guard pageViewControllers.indices.contains(vcIndex) else { return false }
        let vc = pageViewControllers[vcIndex]
        guard case .page = vc.type else { return false }
        let actual = actualPageIndex(from: page)
        if splitPages[actual] == nil, vc.isWideImage || hasCachedSplit(actual) {
            return false
        }
        return true
    }

    private func canDisplayAsDoublePage(_ page: Int) -> Bool {
        isPagePairable(page) && !isPageIsolated(page)
    }

    private func segmentHeadForPage(_ page: Int) -> Int {
        var head = page
        while head > 1 && isPagePairable(head - 1) { head -= 1 }
        return head
    }

    private func spreadStart(for page: Int, head: Int? = nil) -> Int {
        guard page >= 1, page <= displayPageCount, canDisplayAsDoublePage(page) else { return page }

        let segHead = head ?? segmentHeadForPage(page)
        let delta = page - segHead
        if isPageIsolated(segHead) {
            guard delta > 0 else { return segHead }
            return ((delta - 1) % 2 == 0) ? page : page - 1
        }
        return (delta % 2 == 0) ? page : page - 1
    }

    private func createPageController(
        firstPage: ReaderPageViewController,
        secondPage: ReaderPageViewController,
        page: Int
    ) -> ReaderDoublePageViewController? {
        guard
            canDisplayAsDoublePage(page),
            canDisplayAsDoublePage(page + 1)
        else { return nil }
        return ReaderDoublePageViewController(
            firstPage: firstPage,
            secondPage: secondPage,
            direction: readingMode == .rtl ? .rtl : .ltr
        )
    }

    private func handleAspectRatioUpdate(from source: ReaderPageViewController) {
        guard
            usesDoublePages,
            !isTransitioning,
            let doubleVC = pageViewController.viewControllers?.first as? ReaderDoublePageViewController,
            doubleVC.firstPageController == source || doubleVC.secondPageController == source
        else { return }

        if splitWideImages && source.isWideImage { return }

        move(toPage: currentPage, animated: false)
    }

    private func makeSplitPages(leftImage: UIImage, rightImage: UIImage, pageIndex: Int) -> [Page] {
        let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
        let chapterId = chapter?.id ?? ""
        let reverseOrderSetting = UserDefaults.standard.bool(forKey: "Reader.reverseSplitOrder")
        let reverseOrder = readingMode == .rtl ? reverseOrderSetting : !reverseOrderSetting

        let leftPage = Page(sourceId: sourceId, chapterId: chapterId, index: pageIndex, image: leftImage)
        let rightPage = Page(sourceId: sourceId, chapterId: chapterId, index: pageIndex, image: rightImage)
        return reverseOrder ? [leftPage, rightPage] : [rightPage, leftPage]
    }

    private func storeSplitPages(left: UIImage, right: UIImage, at pageIndex: Int) {
        let pages = makeSplitPages(leftImage: left, rightImage: right, pageIndex: pageIndex)
        splitPages[pageIndex] = pages
        cacheSplitPages(pages, at: pageIndex)
    }

    /// Check if a wide image should be split and handle the splitting
    private func checkAndSplitWideImage(at pageIndex: Int, controller: ReaderPageViewController) {
        guard
            splitWideImages,
            splitPages[pageIndex] == nil,
            controller.isWideImage,
            pageViewControllers.contains(controller),
            let (leftImage, rightImage) = controller.pageView?.splitImage()
        else { return }

        if pageIndex <= 0 || pageIndex > viewModel.pages.count {
            let pages = makeSplitPages(leftImage: leftImage, rightImage: rightImage, pageIndex: pageIndex)
            if pageIndex <= 0 {
                previousPreviewSplitPages = pages
            } else {
                nextPreviewSplitPages = pages
            }
            return
        }
        storeSplitPages(left: leftImage, right: rightImage, at: pageIndex)
        rebuildPageIndices()
        guard let stored = splitPages[pageIndex] else { return }
        applySplit(replacing: controller, with: stored)
    }

    private func applySplit(
        replacing controller: ReaderPageViewController,
        with stored: [Page]
    ) {
        guard
            stored.count >= 2,
            let replacingIndex = pageViewControllers.firstIndex(of: controller)
        else { return }

        controller.onImageisWideImage = nil
        controller.clearPage()
        if let image = stored[0].image {
            controller.pageView?.imageView.image = image
            controller.pageView?.fixImageSize()
        }
        controller.setPage(stored[0], skipProcessing: true)

        let newVCs = stored.dropFirst().map { makePageController(preloadPage: $0, skipProcessing: true) }
        pageViewControllers.insert(contentsOf: newVCs, at: replacingIndex + 1)

        let splitDisplayPage = pageIndex(from: replacingIndex)
        shiftIsolation(after: splitDisplayPage, by: newVCs.count)

        if splitDisplayPage < currentPage {
            currentPage += newVCs.count
        }

        if isTransitioning {
            pendingSpreadRebuild = true
        } else {
            move(toPage: currentPage, animated: false, resetGesture: false)
        }
    }

    private func shiftIsolation(after displayPage: Int, by shift: Int) {
        guard shift > 0 else { return }
        isolatedPages = Set(isolatedPages.map { $0 > displayPage ? $0 + shift : $0 })
        manuallyIsolatedPages = Set(manuallyIsolatedPages.map { $0 > displayPage ? $0 + shift : $0 })
    }

    private func firstDisplayPage(forActual actualIndex: Int) -> Int {
        actualPageIndices.firstIndex(of: actualIndex).map { $0 + 1 } ?? actualIndex
    }

    private func lastDisplayPage(forActual actualIndex: Int) -> Int {
        actualPageIndices.lastIndex(of: actualIndex).map { $0 + 1 } ?? actualIndex
    }

    private func setLiveTextButtonHidden(_ hidden: Bool) {
        pageViewController.viewControllers?.forEach {
            let pageControllers: [ReaderPageViewController]
            let zoomScale: CGFloat?
            if let pageController = $0 as? ReaderPageViewController {
                pageControllers = [pageController]
                zoomScale = pageController.zoomView?.zoomScale
            } else if let doublePageController = $0 as? ReaderDoublePageViewController {
                pageControllers = [doublePageController.firstPageController, doublePageController.secondPageController]
                zoomScale = doublePageController.zoomView.zoomScale
            } else {
                pageControllers = []
                zoomScale = nil
            }
            for pageController in pageControllers {
                if hidden {
                    pageController.pageView?.setLiveTextHidden(true)
                } else {
                    guard let zoomScale else { return }
                    pageController.pageView?.setLiveTextHidden(zoomScale != 1)
                }
            }
        }
    }
}

// MARK: - Page Offset
extension ReaderPagedViewController {
    func toggleOffset() {
        guard !isTransitioning, canToggleOffset() else { return }

        let head = findSegmentHead()
        guard isPagePairable(head) else { return }

        let wasIsolated = isPageIsolated(head)
        setPageIsolated(head, isolated: !wasIsolated)

        // other segment heads are toggled independently
        if head == firstToggleableHead() {
            pageOffsetEnabled = !wasIsolated
            UserDefaults.standard.set(!wasIsolated, forKey: pageOffsetKey)
        }

        let targetPage: Int
        if currentPage < head {
            targetPage = currentPage
        } else {
            let reference = wasIsolated
                ? min(currentPage + 1, displayPageCount)
                : currentPage
            targetPage = spreadStart(for: reference, head: head)
        }
        move(toPage: targetPage, animated: false)
    }

    private func firstToggleableHead() -> Int {
        let end = min(8, displayPageCount)
        guard end >= 2 else { return 0 }
        guard let first = (1...end).first(where: { isPagePairable($0) }) else { return 0 }
        // skip offset if the first pairable page is sandwiched by non-pairable pages
        return isPagePairable(first + 1) ? first : 0
    }

    private func findSegmentHead() -> Int {
        var head = currentPage
        while head <= displayPageCount && !isPagePairable(head) { head += 1 }
        while head > 1 && isPagePairable(head - 1) { head -= 1 }

        // skip single-page segments where toggling offset has no effect
        while head < displayPageCount && isPagePairable(head) && !isPagePairable(head + 1) {
            var next = head + 1
            while next <= displayPageCount && !isPagePairable(next) { next += 1 }

            guard next <= displayPageCount else { break }
            head = next
        }

        return min(head, displayPageCount)
    }

    private func canToggleOffset() -> Bool {
        guard
            usesDoublePages,
            displayPageCount > 1,
            chapter != nil,
            let vc = pageViewController.viewControllers?.first,
            let idx = getIndex(of: vc, pos: .first)
        else { return false }
        let page = pageIndex(from: idx)
        return page >= 1 && page <= displayPageCount
    }

    private func isPageIsolated(_ displayPage: Int) -> Bool {
        isolatedPages.contains(displayPage)
    }

    private func setPageIsolated(_ page: Int, isolated: Bool, isManual: Bool = false) {
        if isolated {
            isolatedPages.insert(page)
            if isManual { manuallyIsolatedPages.insert(page) }
        } else {
            isolatedPages.remove(page)
            if isManual { manuallyIsolatedPages.remove(page) }
        }
    }

    private func resetIsolation() {
        isolatedPages = []
        manuallyIsolatedPages = []

        if pageOffsetEnabled {
            let head = splitWideImages ? 1 : firstToggleableHead()
            isolatedPages.insert(head > 0 ? head : 1)
        }
    }

    private func adjustAutoIsolation() {
        guard pageOffsetEnabled else { return }
        let autoIsolated = isolatedPages.subtracting(manuallyIsolatedPages)
        let newHead = firstToggleableHead()
        let desired: Set<Int> = newHead > 0 ? [newHead] : []
        guard autoIsolated != desired else { return }
        isolatedPages = manuallyIsolatedPages.union(desired)
    }
}

// MARK: - Reader Delegate
extension ReaderPagedViewController: ReaderReaderDelegate {
    func moveLeft() {
        guard !isTransitioning else { return }
        if
            let currentViewController = pageViewController.viewControllers?.first,
            let targetViewController = pageViewController(pageViewController, viewControllerBefore: currentViewController)
        {
            isTransitioning = true
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
        guard !isTransitioning else { return }
        if
            let currentViewController = pageViewController.viewControllers?.last,
            let targetViewController = pageViewController(pageViewController, viewControllerAfter: currentViewController)
        {
            isTransitioning = true
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
        let isChapterChange = self.chapter?.id != chapter.id
        self.chapter = chapter
        Task {
            await loadChapter(startPage: startPage, isChapterChange: isChapterChange)
        }
    }

    func loadChapter(startPage: Int, isChapterChange: Bool = true) async {
        guard let chapter else { return }
        await viewModel.loadPages(chapter: chapter)
        delegate?.setPages(viewModel.pages)
        if !viewModel.pages.isEmpty {
            await MainActor.run {
                if !isChapterChange, let key = splitPageCacheKey {
                    Self.splitStore[key] = nil
                }
                splitPages = [:]

                loadPageControllers(chapter: chapter)

                if isChapterChange {
                    resetIsolation()
                }

                let clampedStart = max(startPage, 1)
                let targetPage: Int
                if
                    splitWideImages,
                    let key = splitPageCacheKey,
                    let pos = savedSplitPosition(for: key),
                    pos.page == clampedStart,
                    splitPages[pos.page] != nil
                {
                    let first = firstDisplayPage(forActual: pos.page)
                    let last = lastDisplayPage(forActual: pos.page)
                    targetPage = min(first + pos.offset, last)
                } else {
                    targetPage = firstDisplayPage(forActual: clampedStart)
                }
                move(toPage: max(1, min(targetPage, displayPageCount)), animated: false)
            }
        }
    }

    func refreshChapter(startPage: Int) {
        guard let chapter else { return }

        loadPageControllers(chapter: chapter)
        move(toPage: max(1, min(startPage, displayPageCount)), animated: false)
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
        isTransitioning = false
        setLiveTextButtonHidden(delegate?.barsHidden ?? false)
        if completed {
            for viewController in previousViewControllers {
                if let pageController = viewController as? ReaderPageViewController {
                    pageController.pageView?.clearLiveTextSelection()
                } else if let doublePageController = viewController as? ReaderDoublePageViewController {
                    doublePageController.firstPageController.pageView?.clearLiveTextSelection()
                    doublePageController.secondPageController.pageView?.clearLiveTextSelection()
                }
            }
        }

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
                pendingSpreadRebuild = false
                // move previous
                loadPreviousChapter()

            case 0: // previous chapter transition page
                delegate?.setCurrentPage(0, position: nil)
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
                delegate?.setCurrentPage(displayPageCount + 1, position: nil)
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
                pendingSpreadRebuild = false
                // move next
                loadNextChapter()

            default:
                if !programmaticMove {
                    currentPage = page
                }
                programmaticMove = false

                let actualPage = actualPageIndex(from: currentPage)
                if let key = splitPageCacheKey {
                    saveSplitPosition(for: key, page: actualPage, offset: splitIndex(for: currentPage, actualPageIndex: actualPage))
                }
                if usesDoublePages {
                    delegate?.setCurrentPages(actualPage...min(actualPage + 1, viewModel.pages.count))
                } else {
                    delegate?.setCurrentPage(actualPage, position: nil)
                }
                // preload 1 before and pagesToPreload ahead
                loadPages(in: page - 1 - (usesDoublePages ? 1 : 0)...page + pagesToPreload + (usesDoublePages ? 1 : 0))

                if
                    usesDoublePages,
                    let doubleVC = pageViewController.viewControllers?.first as? ReaderDoublePageViewController
                {
                    let first = doubleVC.firstPageController
                    let second = doubleVC.secondPageController
                    if
                        !pageViewControllers.contains(first) || !pageViewControllers.contains(second),
                        let idx = pageViewControllers.firstIndex(of: first)
                            ?? pageViewControllers.firstIndex(of: second)
                    {
                        pendingSpreadRebuild = false
                        move(toPage: pageIndex(from: idx), animated: false, resetGesture: false)
                    } else if
                        !splitWideImages,
                        first.isWideImage || second.isWideImage
                    {
                        pendingSpreadRebuild = false
                        move(toPage: page, animated: false, resetGesture: true)
                    }
                }

                if pendingSpreadRebuild {
                    pendingSpreadRebuild = false
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.move(toPage: self.currentPage, animated: false, resetGesture: false)
                    }
                }
        }
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        isTransitioning = true
        setLiveTextButtonHidden(true)

        if UserDefaults.standard.bool(forKey: "Reader.hideBarsOnSwipe") {
            delegate?.hideBars()
        }

        for controller in pendingViewControllers {
            guard let idx = getIndex(of: controller, pos: .first) else { continue }
            let page = pageIndex(from: idx)
            if usesDoublePages {
                // include adjacent spreads so wide-image state is resolved for the next data source query
                loadPages(in: page - 2...page + 3)
            } else {
                loadPage(at: page)
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
            if usesDoublePages && currentIndex + 2 < pageViewControllers.count {
                let firstPage = pageViewControllers[currentIndex + 1]
                let secondPage = pageViewControllers[currentIndex + 2]
                if case .page = firstPage.type, case .page = secondPage.type {
                    let page = pageIndex(from: currentIndex + 1)
                    if
                        spreadStart(for: page) == page,
                        let double = createPageController(firstPage: firstPage, secondPage: secondPage, page: page)
                    {
                        return double
                    }
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
            if usesDoublePages && currentIndex - 2 >= 0 {
                let firstPage = pageViewControllers[currentIndex - 2]
                let secondPage = pageViewControllers[currentIndex - 1]
                if case .page = firstPage.type, case .page = secondPage.type {
                    let page = pageIndex(from: currentIndex - 2)
                    if
                        spreadStart(for: page) == page,
                        let double = createPageController(firstPage: firstPage, secondPage: secondPage, page: page)
                    {
                        return double
                    }
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
        // disable when live text highlighting is active
        if
            #available(iOS 16.0, *),
            let imageAnalaysisInteraction = pageView.interactions.first as? ImageAnalysisInteraction,
            imageAnalaysisInteraction.selectableItemsHighlighted
        {
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

            if self.usesDoublePages {
                for (index, pageViewController) in self.pageViewControllers.enumerated() {
                    guard
                        case .page = pageViewController.type,
                        let readerPageView = pageViewController.pageView,
                        readerPageView.imageView == pageView
                    else { continue }

                    let page = self.pageIndex(from: index)
                    let isManuallySet = self.manuallyIsolatedPages.contains(page)
                    if isManuallySet {
                        let unsetAction = UIAction(
                            title: NSLocalizedString("UNSET_AS_SINGLE_PAGE", comment: ""),
                            image: UIImage(systemName: "rectangle.portrait.slash")
                        ) { _ in
                            Task { @MainActor in
                                self.setManualIsolation(for: pageView, isolated: false)
                            }
                        }
                        actions.insert(unsetAction, at: 2)
                    } else if self.canDisplayAsDoublePage(page) {
                        let setAction = UIAction(
                            title: NSLocalizedString("SET_AS_SINGLE_PAGE", comment: ""),
                            image: UIImage(systemName: "rectangle.portrait")
                        ) { _ in
                            Task { @MainActor in
                                self.setManualIsolation(for: pageView, isolated: true)
                            }
                        }
                        actions.insert(setAction, at: 2)
                    }

                    break
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
    private func setManualIsolation(for imageView: UIImageView, isolated: Bool) {
        for (index, pageViewController) in pageViewControllers.enumerated() {
            if
                case .page = pageViewController.type,
                let readerPageView = pageViewController.pageView,
                readerPageView.imageView == imageView
            {
                let page = pageIndex(from: index)
                setPageIsolated(page, isolated: isolated, isManual: true)
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

// MARK: - Split Page Store
extension ReaderPagedViewController {
    private static var splitStore: [String: [Int: [Page]]] = [:]
    private static var splitPosition: [String: (page: Int, offset: Int)] = [:]

    private static func clearSplitPageCache() {
        splitStore.removeAll()
        splitPosition.removeAll()
    }

    private var splitPageCacheKey: String? {
        guard let chapterId = chapter?.id else { return nil }
        return "\(viewModel.manga.identifier)/\(chapterId)"
    }

    private func reverseSplitStoreEntries(for key: String) {
        guard let cached = Self.splitStore[key] else { return }
        Self.splitStore[key] = cached.mapValues { $0.reversed() }
    }

    private func hasCachedSplit(_ actualPage: Int) -> Bool {
        guard let key = splitPageCacheKey else { return false }
        return Self.splitStore[key]?[actualPage] != nil
    }

    private func cacheSplitPages(_ pages: [Page], at pageIndex: Int) {
        guard let key = splitPageCacheKey, pageIndex >= 1, pageIndex <= viewModel.pages.count else { return }
        Self.splitStore[key, default: [:]][pageIndex] = pages
    }

    private func restoreCachedSplitPages() {
        guard
            let key = splitPageCacheKey,
            let cached = Self.splitStore[key]
        else { return }
        for (pageIndex, pages) in cached where splitPages[pageIndex] == nil {
            guard pages.allSatisfy({ $0.image != nil }) else { continue }
            splitPages[pageIndex] = pages
        }
    }

    private func savedSplitPosition(for key: String) -> (page: Int, offset: Int)? {
        Self.splitPosition[key]
    }

    private func saveSplitPosition(for key: String, page: Int, offset: Int) {
        Self.splitPosition[key] = (page, offset)
    }
}
