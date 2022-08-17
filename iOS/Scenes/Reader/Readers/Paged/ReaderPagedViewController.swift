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

        pageViewControllers = []

        let previousInfoController = ReaderPageViewController(type: .info(.previous))
        previousInfoController.currentChapter = chapter
        previousInfoController.previousChapter = delegate?.getPreviousChapter()
        pageViewControllers.append(previousInfoController)

        for _ in 0..<viewModel.pages.count {
            pageViewControllers.append(ReaderPageViewController(type: .page))
        }

        let nextInfoController = ReaderPageViewController(type: .info(.next))
        nextInfoController.currentChapter = chapter
        nextInfoController.nextChapter = delegate?.getNextChapter()
        pageViewControllers.append(nextInfoController)
    }

    func move(toPage page: Int, animated: Bool) {
        guard page - 1 < viewModel.pages.count && page > 0 else {
            return
        }

        let targetViewController = pageViewControllers[page]
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

    func loadPages(in range: Range<Int>) {
        for i in range {
            guard i > 0 else { continue }
            guard i <= viewModel.pages.count else { break }
            pageViewControllers[i].setPage(viewModel.pages[i - 1], sourceId: chapter?.sourceId ?? "")
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
            await viewModel.loadPages(chapter: chapter)
            delegate?.setTotalPages(viewModel.pages.count)
            await MainActor.run {
                self.loadPageControllers(chapter: chapter)
                self.move(toPage: startPage < 1 ? 1 : startPage, animated: false)
            }
        }
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
        delegate?.setCurrentPage(currentIndex)
        let nextPage = currentIndex + 1
        loadPages(in: currentIndex - 1..<nextPage + pagesToPreload) // preload 1 before and pagesToPreload ahead
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
