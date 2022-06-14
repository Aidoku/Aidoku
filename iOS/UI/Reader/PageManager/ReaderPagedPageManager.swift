//
//  ReaderPagedPageManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/15/22.
//

import UIKit
import Kingfisher

struct PageInfo {
    var vc: UIViewController
    var pageIndex: Int
    var numPages: Int
}

class ReaderPagedPageManager: NSObject, ReaderPageManager {

    weak var delegate: ReaderPageManagerDelegate?

    var chapter: Chapter?
    var readingMode: MangaViewer? {
        didSet(oldValue) {
            if (readingMode == .vertical && oldValue != .vertical) || oldValue == .vertical {
                remove()
                createPageViewController()
            }
            if let chapter = chapter {
                setChapter(chapter: chapter, startPage: items[currentIndex].pageIndex + 1)
            }
        }
    }
    var pages: [Page] = []

    var pagesPerView: Int = 1 // initial value set in createPageViewController()
    var pagesToPreload: Int = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
    var usesAutoPageLayout = false

    var preloadedChapter: Chapter?
    var preloadedPages: [Page] = []

    weak var parentViewController: UIViewController!
    var pageViewController: UIPageViewController!
    var items: [PageInfo] = []

    var chapterList: [Chapter] = []
    var chapterIndex: Int {
        guard let chapter = chapter else { return 0 }
        return chapterList.firstIndex(of: chapter) ?? 0
    }

    var hasNextChapter = false
    var hasPreviousChapter = false

    var nextChapter: Chapter?

    var currentIndex: Int = 0

    var widePages: [Int] = []

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: Notification.Name("Reader.pagedPageLayout"), object: nil, queue: nil) { _ in
            self.pagesPerView = {
                self.usesAutoPageLayout = false
                switch UserDefaults.standard.string(forKey: "Reader.pagedPageLayout") {
                case "single": return 1
                case "double": return 2
                case "auto":
                    guard self.parentViewController != nil else { return 1 }
                    self.usesAutoPageLayout = true
                    return self.parentViewController.view.bounds.width > self.parentViewController.view.bounds.height ? 2 : 1
                default: return 1
                }
            }()
            if let chapter = self.chapter {
                self.setChapter(chapter: chapter, startPage: self.items[self.currentIndex].pageIndex + 1)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: Notification.Name("Reader.pagesToPreload"), object: nil, queue: nil) { _ in
            self.pagesToPreload = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
        })
    }

    func createPageViewController() {
        guard parentViewController != nil else { return }

        pagesPerView = {
            switch UserDefaults.standard.string(forKey: "Reader.pagedPageLayout") {
            case "single": return 1
            case "double": return 2
            case "auto":
                usesAutoPageLayout = true
                return parentViewController.view.bounds.width > parentViewController.view.bounds.height ? 2 : 1
            default: return 1
            }
        }()

        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: readingMode == .vertical ? .vertical : .horizontal,
            options: nil
        )

        pageViewController.delegate = self
        pageViewController.dataSource = self
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        parentViewController.addChild(pageViewController)
        parentViewController.view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: parentViewController)

        pageViewController.view.topAnchor.constraint(equalTo: parentViewController.view.topAnchor).isActive = true
        pageViewController.view.leadingAnchor.constraint(equalTo: parentViewController.view.leadingAnchor).isActive = true
        pageViewController.view.trailingAnchor.constraint(equalTo: parentViewController.view.trailingAnchor).isActive = true
        pageViewController.view.bottomAnchor.constraint(equalTo: parentViewController.view.bottomAnchor).isActive = true
    }

    func attach(toParent parent: UIViewController) {
        parentViewController = parent
        createPageViewController()
    }

    func remove() {
        guard pageViewController != nil else { return }
        pageViewController.willMove(toParent: nil)
        pageViewController.view.removeFromSuperview()
        pageViewController.removeFromParent()
        pageViewController = nil
    }

    func setChapter(chapter: Chapter, startPage: Int) {
        guard pageViewController != nil else { return }
        self.chapter = chapter
        Task {
            pages = []
            await loadPages()
            await loadViewControllers(startPage: startPage)
        }
    }

    func move(toPage page: Int, animated: Bool = false, reversed: Bool = false) {
        guard pageViewController != nil else { return }

        let targetIndex: Int?
        if page == -1 { // first
            targetIndex = nil
        } else if page == -2 { // last
            targetIndex = nil
        } else {
            targetIndex = items.firstIndex(where: { $0.pageIndex <= page && $0.pageIndex + $0.numPages > page })
        }
        guard let targetIndex = targetIndex else { return }

        Task {
            await setImages(for: (targetIndex - pagesToPreload)..<(targetIndex + pagesToPreload + 1))
        }

        if targetIndex >= 0 && targetIndex < items.count {
            pageViewController.setViewControllers(
                [items[targetIndex].vc],
                direction: (reversed == (readingMode == .rtl)) ? .forward : .reverse,
                animated: animated
            ) { completed in
                self.pageViewController(
                    self.pageViewController,
                    didFinishAnimating: true,
                    previousViewControllers: [],
                    transitionCompleted: completed
                )
                self.currentIndex = targetIndex
                self.delegate?.didMove(toPage: page)
            }
        }
    }

    func nextPage() {
        // TODO: support transition between chapters
        let next = getPageIndex(for: currentIndex + 1)
        move(toPage: next, animated: true, reversed: false)
    }

    func previousPage() {
        let prev = currentIndex <= 1 ? -1 : getPageIndex(for: currentIndex - 1)
        move(toPage: prev, animated: true, reversed: true)
    }

    func willTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        if usesAutoPageLayout {
            pagesPerView = size.width > size.height ? 2 : 1
            if let chapter = chapter {
                setChapter(chapter: chapter, startPage: items[currentIndex].pageIndex + 1)
            }
        }
        coordinator.animate(alongsideTransition: nil) { _ in
            for info in self.items {
                info.vc.view.frame = self.pageViewController.view.bounds
                if let page = info.vc.view as? ReaderPageView {
                    page.zoomableView.frame = page.bounds
                    page.multiView.frame = page.bounds
                    page.updateZoomBounds()
                }
            }
        }
    }
}

extension ReaderPagedPageManager {

    // find next non-duplicate chapter
    func getNextChapter() -> Chapter? {
        guard !chapterList.isEmpty && chapterIndex != 0 else { return nil }

        var i = chapterIndex
        while true {
            i -= 1
            if i < 0 { return nil }
            let newChapter = chapterList[i]
            if newChapter.chapterNum != chapter?.chapterNum || newChapter.volumeNum != chapter?.volumeNum {
                return newChapter
            }
        }
    }

    func loadPages() async {
        guard pageViewController != nil, let chapter = chapter else { return }

        if chapterList.isEmpty {
            if let chapters = delegate?.chapterList, !chapters.isEmpty {
                chapterList = chapters
            } else {
                chapterList = await DataManager.shared.getChapters(from: chapter.sourceId, for: chapter.mangaId)
            }
        }
        if let chapterIndex = chapterList.firstIndex(of: chapter) {
            nextChapter = getNextChapter()
            hasPreviousChapter = chapterIndex != chapterList.count - 1
            hasNextChapter = nextChapter != nil
        } else {
            hasPreviousChapter = false
            hasNextChapter = false
        }

        if preloadedChapter == chapter && !preloadedPages.isEmpty {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
        } else {
            pages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
            delegate?.pagesLoaded()
        }
    }

    enum ChapterLoadDirection {
        case none // from nothing
        case backward // going to previous
        case forward // going to next
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    func loadViewControllers(from direction: ChapterLoadDirection = .none, startPage: Int = 1) {
        guard pageViewController != nil, let chapter = chapter else { return }

        var pages = pages
        var startPage = startPage <= 0 ? 1 : startPage

        var storedPage: PageInfo?

        if direction == .forward, let preview = items.last { // keep first page (last in items)
            items = [preview]
            items[0].pageIndex = 0
            let pageView = preview.vc.view as? ReaderPageView
            let subpages = pages[0..<preview.numPages]
            for (i, page) in subpages.enumerated() {
                pageView?.setPage(page: page, index: i)
            }
            pages.removeFirst(subpages.count)
        } else if direction == .backward, let preview = items.first { // keep last page (first in items)
            items = []
            storedPage = preview
            let pageView = preview.vc.view as? ReaderPageView
            let subpages = pages[(pages.count - preview.numPages)..<pages.count]
            for (i, page) in subpages.enumerated() {
                pageView?.setPage(page: page, index: i)
            }
            pages.removeLast(subpages.count)
        } else {
            items = []
        }

        @MainActor
        func insertPage(at index: Int, pageIndex: Int, numPages: Int) {
            guard numPages > 0 else { return }
            let chapterPageController = UIViewController()
            let page = ReaderPageView(sourceId: chapter.sourceId, pages: numPages, mode: readingMode ?? .defaultViewer)
            page.frame = pageViewController.view.bounds
            page.imageViews.forEach { $0.addInteraction(UIContextMenuInteraction(delegate: self)) }
            chapterPageController.view = page
            items.insert(PageInfo(vc: chapterPageController, pageIndex: pageIndex, numPages: numPages), at: index)
        }

        let offset = items.isEmpty ? 0 : items[0].numPages
        var i = 0
        while i < pages.count {
            var wideIndex = -1
            for j in 0..<pagesPerView {
                if widePages.contains(i + j) { wideIndex = j }
            }
            if wideIndex != -1 {
                insertPage(at: items.endIndex, pageIndex: i + offset, numPages: min(wideIndex, pages.count - i))
                insertPage(at: items.endIndex, pageIndex: i + offset + wideIndex, numPages: 1)
                i += wideIndex + 1
            } else {
                insertPage(at: items.endIndex, pageIndex: i + offset, numPages: min(pagesPerView, pages.count - i))
                i += pagesPerView
            }
        }

        if let page = storedPage {
            items.append(page)
            items[items.count - 1].pageIndex = items.count > 1 ? items[items.count - 2].pageIndex + items[items.count - 2].numPages : 0
            startPage = items[items.count - 1].pageIndex + 1
        }

        let firstPageController = UIViewController()
        let firstPage = ReaderInfoPageView(type: .previous, currentChapter: chapter)
        if hasPreviousChapter {
            firstPage.previousChapter = chapterList[chapterIndex + 1]
        }
        firstPage.frame = pageViewController.view.bounds
        firstPageController.view.addSubview(firstPage)
        items.insert(PageInfo(vc: firstPageController, pageIndex: -1, numPages: -1), at: 0)

        let finalPageController = UIViewController()
        let finalPage = ReaderInfoPageView(type: .next, currentChapter: chapter)
        if hasNextChapter {
            finalPage.nextChapter = nextChapter
        }
        finalPage.frame = pageViewController.view.bounds
        finalPageController.view = finalPage
        items.append(PageInfo(vc: finalPageController, pageIndex: pages.count + offset, numPages: -1))

        if hasNextChapter {
            insertPage(at: items.endIndex, pageIndex: -1, numPages: 1)
        }

        if hasPreviousChapter {
            insertPage(at: 0, pageIndex: -1, numPages: 1)
        }

        move(toPage: startPage - 1)
    }

    func preload(chapter: Chapter) async {
        preloadedPages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
        preloadedChapter = chapter
    }

    func preloadImages(for range: Range<Int>) {
        guard !pages.isEmpty else { return }
        var lower = range.lowerBound
        var upper = range.upperBound
        if lower < 0 {
            lower = 0
        }
        if upper >= pages.count {
            upper = pages.count - 1
        }
        guard lower <= upper else { return }
        let newRange = lower..<upper
        let pages = pages[newRange]
        let urls = pages.compactMap { URL(string: $0.imageURL ?? "") }
        ImagePrefetcher(urls: urls).start()
    }

    func setImages(for range: Range<Int>) async {
        for i in range {
            guard i < items.count - (hasNextChapter ? 2 : 1) else { break }
            if i < (hasPreviousChapter ? 2 : 1) { continue }
            for j in 0..<items[i].numPages {
                guard items[i].pageIndex + j < pages.count else { continue }
                await (items[i].vc.view as? ReaderPageView)?.setPage(page: pages[items[i].pageIndex + j], index: j)
            }
        }
    }

    func getPageIndex(for vcIndex: Int) -> Int {
        guard vcIndex > 0, vcIndex < items.count else { return -1 }
        return items[vcIndex].pageIndex
    }
}

// MARK: - Page View Controller Delegate
extension ReaderPagedPageManager: UIPageViewControllerDelegate {

    // swiftlint:disable:next cyclomatic_complexity
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let vc = pageViewController.viewControllers?.first,
              let index = items.firstIndex(where: { $0.vc == vc }) else {
            return
        }

        if hasPreviousChapter && index < 2 {
            if index == 0 { // switch to previous chapter
                chapter = chapterList[chapterIndex + 1]
                Task {
                    await loadPages()
                    if let chapter = chapter {
                        delegate?.move(toChapter: chapter)
                    }
                    loadViewControllers(from: .backward)
                }
                return
            } else if index == 1 { // preload previous chapter
                Task {
                    let previousChapter = chapterList[chapterIndex + 1]
                    await preload(chapter: previousChapter)
                    let pageCount = preloadedPages.count < pagesPerView ? preloadedPages.count : (preloadedPages.count - 1) % pagesPerView + 1
                    let subpages = preloadedPages[(preloadedPages.count - pageCount)..<preloadedPages.count]
                    if let first = items.first, first.numPages != pageCount, let pageView = first.vc.view as? ReaderPageView {
                        items[0].numPages = pageCount
                        pageView.numPages = pageCount
                        pageView.imageViews.forEach { $0.addInteraction(UIContextMenuInteraction(delegate: self)) }
                    }
                    for (i, page) in subpages.enumerated() {
                        (items.first?.vc.view as? ReaderPageView)?.setPage(page: page, index: i)
                    }
                }
            }
        } else if let nextChapter = nextChapter {
            if index == items.count - 2 { // preload next chapter
                Task {
                    await preload(chapter: nextChapter)
                    let pageCount = min(pagesPerView, preloadedPages.count)
                    let subpages = preloadedPages[0..<pageCount]
                    if let last = items.last, last.numPages != pageCount, let pageView = last.vc.view as? ReaderPageView {
                        items[items.count - 1].numPages = pageCount
                        pageView.numPages = pageCount
                        pageView.imageViews.forEach { $0.addInteraction(UIContextMenuInteraction(delegate: self)) }
                    }
                    for (i, page) in subpages.enumerated() {
                        (items.last?.vc.view as? ReaderPageView)?.setPage(page: page, index: i)
                    }
                }
            } else if index == items.count - 1 { // switch to next chapter
                chapter = nextChapter
                Task {
                    await loadPages()
                    if let chapter = chapter {
                        delegate?.move(toChapter: chapter)
                    }
                    loadViewControllers(from: .forward)
                }
                return
            }
        }
        currentIndex = index
        delegate?.didMove(toPage: items[currentIndex].pageIndex)
        Task {
            await setImages(for: (index - pagesToPreload)..<(index + pagesToPreload + 1))
            preloadImages(for: index..<(index + 3))
        }
    }
}

// MARK: - Page View Controller Data Source
extension ReaderPagedPageManager: UIPageViewControllerDataSource {

    func pageViewController(_: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = items.firstIndex(where: { $0.vc == viewController }) else { return nil }

        if readingMode == .ltr || readingMode == .vertical {
            let nextIndex = viewControllerIndex + 1
            guard items.count > nextIndex else { return nil }
            return items[nextIndex].vc
        } else {
            let previousIndex = viewControllerIndex - 1
            guard previousIndex >= 0, items.count > previousIndex else { return nil }
            return items[previousIndex].vc
        }
    }

    func pageViewController(_: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = items.firstIndex(where: { $0.vc == viewController }) else { return nil }

        if readingMode == .ltr || readingMode == .vertical {
            let previousIndex = viewControllerIndex - 1
            guard previousIndex >= 0, items.count > previousIndex else { return nil }
            return items[previousIndex].vc
        } else {
            let nextIndex = viewControllerIndex + 1
            guard items.count > nextIndex else { return nil }
            return items[nextIndex].vc
        }
    }
}

// MARK: - Context Menu Delegate
extension ReaderPagedPageManager: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            let saveToPhotosAction = UIAction(
                title: NSLocalizedString("SAVE_TO_PHOTOS", comment: ""),
                image: UIImage(systemName: "photo")
            ) { _ in
                if let pageView = interaction.view as? UIImageView,
                   let image = pageView.image {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }

            let shareAction = UIAction(
                title: NSLocalizedString("SHARE", comment: ""),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                if let pageView = interaction.view as? UIImageView, let image = pageView.image {
                    let items = [image]
                    let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)
                    self.pageViewController.present(activityController, animated: true)
                }
            }

            let pageIndex: Int = {
                if let imageView = interaction.view as? UIImageView {
                    for info in self.items {
                        if let pageView = info.vc.view as? ReaderPageView {
                            for (i, subview) in pageView.imageViews.enumerated() where subview == imageView {
                                return self.readingMode == .rtl ? info.pageIndex + info.numPages - i - 1 : info.pageIndex + i
                            }
                        }
                    }
                }
                return -1
            }()

            let setAsWidePageAction = UIAction(
                title: NSLocalizedString("SET_AS_WIDE_PAGE", comment: ""),
                image: UIImage(systemName: "rectangle.portrait.arrowtriangle.2.outward")
            ) { _ in
                self.widePages.append(pageIndex)
                if let chapter = self.chapter {
                    self.setChapter(chapter: chapter, startPage: pageIndex + 1)
                }
            }

            let setAsNormalPageAction = UIAction(
                title: NSLocalizedString("SET_AS_NORMAL_PAGE", comment: ""),
                image: UIImage(systemName: "rectangle.portrait.arrowtriangle.2.inward")
            ) { _ in
                self.widePages.removeAll(where: { $0 == pageIndex })
                if let chapter = self.chapter {
                    self.setChapter(chapter: chapter, startPage: pageIndex + 1)
                }
            }

            var actions: [UIAction] = []

            if UserDefaults.standard.bool(forKey: "Reader.saveImageOption") {
                actions.append(contentsOf: [saveToPhotosAction, shareAction])
            }

            if pageIndex != -1 && self.pagesPerView != 1 {
                if self.widePages.contains(where: { $0 == pageIndex }) {
                    actions.append(setAsNormalPageAction)
                } else {
                    actions.append(setAsWidePageAction)
                }
            }

            return UIMenu(title: "", children: actions)
        })
    }
}
