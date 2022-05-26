//
//  ReaderPagedPageManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/15/22.
//

import UIKit
import Kingfisher

class ReaderPagedPageManager: NSObject, ReaderPageManager {

    weak var delegate: ReaderPageManagerDelegate?

    var chapter: Chapter?
    var readingMode: MangaViewer? {
        didSet(oldValue) {
            if (readingMode == .vertical && oldValue != .vertical) || oldValue == .vertical {
                remove()
                createPageViewController()
                if let chapter = chapter {
                    setChapter(chapter: chapter, startPage: currentPageIndex)
                }
            }
        }
    }
    var pages: [Page] = []

    var preloadedChapter: Chapter?
    var preloadedPages: [Page] = []

    var parentViewController: UIViewController!
    var pageViewController: UIPageViewController!
    var items: [UIViewController] = []

    var chapterList: [Chapter] = []
    var chapterIndex: Int {
        guard let chapter = chapter else { return 0 }
        return chapterList.firstIndex(of: chapter) ?? 0
    }

    var hasNextChapter = false
    var hasPreviousChapter = false

    var nextChapter: Chapter?

    var currentIndex: Int = 0
    var currentPageIndex: Int {
        currentIndex - 1 - (hasPreviousChapter ? 1 : 0)
    }

    func createPageViewController() {
        guard parentViewController != nil else { return }
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

    func move(toPage page: Int) {
        guard pageViewController != nil else { return }

        Task {
            await setImages(for: (page - 2)..<(page + 3))
        }

        let targetIndex = page + 1 + (hasPreviousChapter ? 1 : 0)

        if targetIndex >= 0 && targetIndex < items.count {
            pageViewController.setViewControllers([items[targetIndex]], direction: .forward, animated: false, completion: nil)
            currentIndex = targetIndex
            delegate?.didMove(toPage: page)
        }
    }

    func willTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: nil) { _ in
            for vc in self.items {
                vc.view.frame = self.pageViewController.view.bounds
                if let page = vc.view as? ReaderPageView {
                    page.zoomableView.frame = page.bounds
                    page.imageView.frame = page.bounds
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
    func loadViewControllers(from direction: ChapterLoadDirection = .none, startPage: Int = 0) {
        guard pageViewController != nil, let chapter = chapter else { return }

        var pages = pages

        var storedPage: UIViewController?

        var startIndex = startPage

        if direction == .forward, let preview = items.last { // keep first page (last in items)
            items = [preview]
            if let page = pages.first {
                let pageView = preview.view as? ReaderPageView
                pageView?.setPage(page: page)
                pages.removeFirst(1)
            }
        } else if direction == .backward, let preview = items.first { // keep last page (first in items)
            items = []
            storedPage = preview
            if let page = pages.last {
                let pageView = preview.view as? ReaderPageView
                pageView?.setPage(page: page)
                pages.removeLast(1)
            }
        } else {
            items = []
        }

        func addChapter(_ index: Int) {
            let chapterPageController = UIViewController()
            let page = ReaderPageView(sourceId: chapter.sourceId)
            page.frame = pageViewController.view.bounds
            page.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
            chapterPageController.view = page
            items.insert(chapterPageController, at: index)
        }

        for _ in pages {
            addChapter(items.endIndex)
        }

        if let page = storedPage {
            items.append(page)
            startIndex = items.count - 1
        }

        let firstPageController = UIViewController()
        let firstPage = ReaderInfoPageView(type: .previous, currentChapter: chapter)
        if hasPreviousChapter {
            firstPage.previousChapter = chapterList[chapterIndex + 1]
        }
        firstPage.frame = pageViewController.view.bounds
        firstPageController.view.addSubview(firstPage)
        items.insert(firstPageController, at: 0)

        let finalPageController = UIViewController()
        let finalPage = ReaderInfoPageView(type: .next, currentChapter: chapter)
        if hasNextChapter {
            finalPage.nextChapter = nextChapter
        }
        finalPage.frame = pageViewController.view.bounds
        finalPageController.view = finalPage
        items.append(finalPageController)

        if hasNextChapter {
            addChapter(items.endIndex)
        }

        if hasPreviousChapter {
            addChapter(0)
        }

        Task {
            await setImages(for: (startPage - 2)..<(startPage + 3))
        }

        let targetIndex = startIndex + 1 + (hasPreviousChapter ? 1 : 0)

        if targetIndex >= 0 && targetIndex < items.count {
            pageViewController.setViewControllers([items[targetIndex]], direction: .forward, animated: false, completion: nil)
            delegate?.didMove(toPage: startIndex)
        }
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
            guard i < pages.count else { break }
            if i < 0 {
                continue
            }
            if let pageView = await items[i + 1 + (hasPreviousChapter ? 1 : 0)].view as? ReaderPageView {
                await pageView.setPage(page: pages[i])
            }
        }
    }
}

// MARK: - Page View Controller Delegate
extension ReaderPagedPageManager: UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let vc = pageViewController.viewControllers?.first,
              let index = items.firstIndex(of: vc) else {
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
                    currentIndex = items.firstIndex(of: vc) ?? 0
                }
                return
            } else if index == 1 { // preload previous chapter
                Task {
                    let previousChapter = chapterList[chapterIndex + 1]
                    await preload(chapter: previousChapter)
                    if let page = preloadedPages.last {
                        (items.first?.view as? ReaderPageView)?.setPage(page: page)
                    }
                }
            }
        } else if let nextChapter = nextChapter {
            let itemCount = items.count
            if index == itemCount - 2 { // preload next chapter
                Task {
                    await preload(chapter: nextChapter)
                    if let page = preloadedPages.first {
                        (items.last?.view as? ReaderPageView)?.setPage(page: page)
                    }
                }
            } else if index == itemCount - 1 { // switch to next chapter
                chapter = nextChapter
                Task {
                    await loadPages()
                    if let chapter = chapter {
                        delegate?.move(toChapter: chapter)
                    }
                    loadViewControllers(from: .forward)
                    currentIndex = items.firstIndex(of: vc) ?? 0
                }
                return
            }
        }
        currentIndex = index
        delegate?.didMove(toPage: currentPageIndex)
        Task {
            await setImages(for: (index - 2)..<(index + 3))
        }
    }
}

// MARK: - Page View Controller Data Source
extension ReaderPagedPageManager: UIPageViewControllerDataSource {

    func pageViewController(_: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = items.firstIndex(of: viewController) else { return nil }

        if readingMode == .ltr || readingMode == .vertical {
            let nextIndex = viewControllerIndex + 1
            guard items.count > nextIndex else { return nil }
            return items[nextIndex]
        } else {
            let previousIndex = viewControllerIndex - 1
            guard previousIndex >= 0, items.count > previousIndex else { return nil }
            return items[previousIndex]
        }
    }

    func pageViewController(_: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = items.firstIndex(of: viewController) else { return nil }

        if readingMode == .ltr || readingMode == .vertical {
            let previousIndex = viewControllerIndex - 1
            guard previousIndex >= 0, items.count > previousIndex else { return nil }
            return items[previousIndex]
        } else {
            let nextIndex = viewControllerIndex + 1
            guard items.count > nextIndex else { return nil }
            return items[nextIndex]
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
                image: UIImage(systemName: "square.and.arrow.down")
            ) { _ in
                if let pageView = interaction.view as? UIImageView,
                   let image = pageView.image {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
            return UIMenu(title: "", children: [saveToPhotosAction])
        })
    }
}
