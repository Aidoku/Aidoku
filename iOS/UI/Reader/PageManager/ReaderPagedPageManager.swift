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
    var readingMode: MangaViewer?
    var pages: [Page] = []

    var preloadedChapter: Chapter?
    var preloadedPages: [Page] = []

    var pageViewController: UIPageViewController!
    var items: [UIViewController] = []

    var chapterList: [Chapter] = []
    var chapterIndex: Int {
        guard let chapter = chapter else { return 0 }
        return chapterList.firstIndex(of: chapter) ?? 0
    }

    var hasNextChapter = false
    var hasPreviousChapter = false

    var currentIndex: Int = 0
    var currentPageIndex: Int {
        currentIndex - 1 - (hasPreviousChapter ? 1 : 0)
    }

    func attach(toParent parent: UIViewController) {
        pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)

        pageViewController.delegate = self
        pageViewController.dataSource = self
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        parent.addChild(pageViewController)
        parent.view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: parent)

        pageViewController.view.topAnchor.constraint(equalTo: parent.view.topAnchor).isActive = true
        pageViewController.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor).isActive = true
        pageViewController.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor).isActive = true
        pageViewController.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor).isActive = true
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
            delegate?.didMove(toPage: page)
        }
    }
}

extension ReaderPagedPageManager {
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
            hasPreviousChapter = chapterIndex != chapterList.count - 1
            hasNextChapter = chapterIndex != 0
        } else {
            hasPreviousChapter = false
            hasNextChapter = false
        }

        if preloadedChapter == chapter && !preloadedPages.isEmpty {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
        } else if pages.isEmpty {
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

        var urls = pages.map { $0.imageURL ?? "" }
//        let urls = urlStrings.map { str -> URL in
//            URL(string: str)!
//        }
//        self.preloadImages(for: self.urls)

        var storedPage: UIViewController?

        var startIndex = startPage

        if direction == .forward, let preview = items.last { // keep first page (last in items)
            items = [preview]
            if let url = urls.first {
                Task {
                    await (preview.view as? ReaderPageView)?.setPageImage(url: url)
                }
                urls.removeFirst(1)
            }
        } else if direction == .backward, let preview = items.first { // keep last page (first in items)
            items = []
            storedPage = preview
            if let url = urls.last {
                Task {
                    await (preview.view as? ReaderPageView)?.setPageImage(url: url)
                }
                urls.removeLast(1)
            }
        } else {
            items = []
        }

        for _ in urls {
            let c = UIViewController()
            let page = ReaderPageView()
            c.view = page
            items.append(c)
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
        firstPage.frame = pageViewController.view.frame
        firstPageController.view.addSubview(firstPage)
        items.insert(firstPageController, at: 0)

        let finalPageController = UIViewController()
        let finalPage = ReaderInfoPageView(type: .next, currentChapter: chapter)
        if hasNextChapter {
            finalPage.nextChapter = chapterList[chapterIndex - 1]
        }
        finalPage.frame = pageViewController.view.frame
        finalPageController.view = finalPage
        items.append(finalPageController)

        if hasPreviousChapter {
            let previousChapterPageController = UIViewController()
            previousChapterPageController.view  = ReaderPageView()
            items.insert(previousChapterPageController, at: 0)
        }

        if hasNextChapter {
            let nextChapterPageController = UIViewController()
            nextChapterPageController.view  = ReaderPageView()
            items.append(nextChapterPageController)
        }

        Task {
            await setImages(for: (startPage - 2)..<(startPage + 3))
        }

        let targetIndex = startIndex + 1 + (hasPreviousChapter ? 1 : 0)
        let pageIndex = startIndex

        if targetIndex >= 0 && targetIndex < items.count {
            // this main dispatch seems redundant but it's needed to set the proper page
            // if it's not used, the page will set to the one after or before the target index (depending on scroll direction)
            DispatchQueue.main.async {
                self.pageViewController.setViewControllers([self.items[targetIndex]], direction: .forward, animated: false, completion: nil)
                self.delegate?.didMove(toPage: pageIndex)
            }
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
        let prefetcher = ImagePrefetcher(urls: urls)
        prefetcher.start()
    }

    func setImages(for range: Range<Int>) async {
        let urls = pages.map { $0.imageURL ?? "" }
        for i in range {
            guard i < urls.count else { break }
            if i < 0 {
                continue
            }
            await (items[i + 1 + (hasPreviousChapter ? 1 : 0)].view as? ReaderPageView)?.setPageImage(url: urls[i])
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
                    await (items.first?.view as? ReaderPageView)?.setPageImage(url: preloadedPages.last?.imageURL ?? "")
                }
            }
        } else if hasNextChapter {
            let itemCount = items.count
            if index == itemCount - 2 { // preload next chapter
                Task {
                    let nextChapter = chapterList[chapterIndex - 1]
                    await preload(chapter: nextChapter)
                    await (items.last?.view as? ReaderPageView)?.setPageImage(url: preloadedPages.first?.imageURL ?? "")
                }
            } else if index == itemCount - 1 { // switch to next chapter
                chapter = chapterList[chapterIndex - 1]
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
        guard let viewControllerIndex = items.firstIndex(of: viewController) else {
            return nil
        }

        if readingMode == .ltr {
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
        guard let viewControllerIndex = items.firstIndex(of: viewController) else {
            return nil
        }

        if readingMode == .ltr {
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
