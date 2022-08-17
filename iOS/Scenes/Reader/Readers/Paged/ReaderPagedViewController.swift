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
    var pageViewControllers: [ReaderPageViewController] = []

    var pagesPerView = 1
    var usesAutoPageLayout = false
    lazy var pagesToPreload = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")

    private var previousChapter: Chapter?
    private var nextChapter: Chapter?

    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: nil
    )

    override func configure() {
        pageViewController.delegate = self
        pageViewController.dataSource = self
        add(child: pageViewController)
    }

    override func observe() {
        addObserver(forName: "Reader.pagedPageLayout") { [weak self] _ in
            guard let self = self else { return }
            self.pagesPerView = {
                self.usesAutoPageLayout = false
                switch UserDefaults.standard.string(forKey: "Reader.pagedPageLayout") {
                case "single": return 1
                case "double": return 2
                case "auto":
                    self.usesAutoPageLayout = true
                    return self.view.bounds.width > self.view.bounds.height ? 2 : 1
                default: return 1
                }
            }()
        }
        addObserver(forName: "Reader.pagesToPreload") { [weak self] notification in
            self?.pagesToPreload = notification.object as? Int
                ?? UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
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

        // previous chapter pages
        if let previousChapter = delegate?.getPreviousChapter() {
            self.previousChapter = previousChapter

            // last page of previous chapter
            if let previousChapterPreviewController = previousChapterPreviewController {
                pageViewControllers.append(previousChapterPreviewController)
            } else {
                pageViewControllers.append(ReaderPageViewController(type: .page))
            }

            // previous chapter transition page
            let previousInfoController = ReaderPageViewController(type: .info(.previous))
            previousInfoController.currentChapter = chapter
            previousInfoController.previousChapter = previousChapter
            pageViewControllers.append(previousInfoController)
        } else {
            previousChapter = nil
        }

        // chapter pages
        let startPos = firstPageController != nil ? 1 : 0
        let endPos = viewModel.pages.count - (lastPageController != nil ? 1 : 0)

        if let firstPageController = firstPageController {
            pageViewControllers.append(firstPageController)
        }

        for _ in startPos..<endPos {
            pageViewControllers.append(ReaderPageViewController(type: .page))
        }

        if let lastPageController = lastPageController {
            pageViewControllers.append(lastPageController)
        }

        // next chapter pages
        if let nextChapter = delegate?.getNextChapter() {
            self.nextChapter = nextChapter

            // next chapter transition page
            let nextInfoController = ReaderPageViewController(type: .info(.next))
            nextInfoController.currentChapter = chapter
            nextInfoController.nextChapter = nextChapter
            pageViewControllers.append(nextInfoController)

            // first page of next chapter
            if let nextChapterPreviewController = nextChapterPreviewController {
                pageViewControllers.append(nextChapterPreviewController)
            } else {
                pageViewControllers.append(ReaderPageViewController(type: .page))
            }
        } else {
            nextChapter = nil
        }
    }

    func move(toPage page: Int, animated: Bool) {
        guard page - 1 < viewModel.pages.count && page > 0 else {
            return
        }

        let targetViewController = pageViewControllers[page + (previousChapter != nil ? 1 : -1)]
        targetViewController.setPage(viewModel.pages[page - 1], sourceId: chapter?.sourceId ?? "")

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

    func loadPages(in range: ClosedRange<Int>) {
        for i in range {
            guard i > 0 else { continue }
            guard i <= viewModel.pages.count else { break }
            let vcIndex = i + (previousChapter != nil ? 1 : -1)
            pageViewControllers[vcIndex].setPage(viewModel.pages[i - 1], sourceId: chapter?.sourceId ?? "")
        }
    }
}

// MARK: - Reader Delegate
extension ReaderPagedViewController: ReaderReaderDelegate {

    // TODO: settings

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
            let viewController = pageViewController.viewControllers?.first as? ReaderPageViewController,
            let currentIndex = pageViewControllers.firstIndex(of: viewController),
            pagesToPreload > 0
        else {
            return
        }
        let page = currentIndex + (previousChapter == nil ? 1 : -1)
        switch page {
        case -1: // previous chapter last page
            // move previous
            loadPreviousChapter()

        case 0: // previous chapter transition page
            // preload previous
            if let previousChapter = previousChapter {
                Task {
                    await viewModel.preload(chapter: previousChapter)
                    if let lastPage = viewModel.preloadedPages.last {
                        pageViewControllers[currentIndex - 1].setPage(lastPage, sourceId: previousChapter.sourceId)
                    }
                }
            }

        case viewModel.pages.count + 1: // next chapter transition page
            // preload next
            if let nextChapter = nextChapter {
                Task {
                    await viewModel.preload(chapter: nextChapter)
                    if let firstPage = viewModel.preloadedPages.first {
                        pageViewControllers[currentIndex + 1].setPage(firstPage, sourceId: nextChapter.sourceId)
                    }
                }
            }

        case viewModel.pages.count + 2: // next chapter first page
            // move next
            loadNextChapter()

        default:
            delegate?.setCurrentPage(page)
            loadPages(in: page - 1...page + pagesToPreload) // preload 1 before and pagesToPreload ahead
        }
    }
}

// MARK: - Page Controller Data Source
extension ReaderPagedViewController: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard
            let viewController = viewController as? ReaderPageViewController,
            let currentIndex = pageViewControllers.firstIndex(of: viewController)
        else {
            return nil
        }
        if currentIndex + 1 < pageViewControllers.count {
            if pagesPerView > 1 && currentIndex + pagesPerView < pageViewControllers.count {
                // TODO: use double layout, ReaderDoublePageViewController
            }
            return pageViewControllers[currentIndex + 1]
        }
        return nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard
            let viewController = viewController as? ReaderPageViewController,
            let currentIndex = pageViewControllers.firstIndex(of: viewController)
        else {
            return nil
        }
        if currentIndex - 1 >= 0 {
            return pageViewControllers[currentIndex - 1]
        }
        return nil
    }
}
