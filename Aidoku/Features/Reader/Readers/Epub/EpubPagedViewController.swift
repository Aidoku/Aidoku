//
//  EpubPagedViewController.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/28/26.
//

import UIKit
import WebKit

// the paged reading style: a UIPageViewController turning one visual page per screen, the shape
// ReaderPagedTextViewController uses. a page's web view holds its whole spine document laid out in
// columns and scrolled to that page's column, with its touches disabled, so the page controller's
// own pan recognises over text: WebKit's deferring recognisers never see the gesture
@MainActor
final class EpubPagedViewController: UIViewController {
    /// What the pages are made of. The book's index is complete before this controller is built,
    /// so every book page resolves to a document and a page within it.
    struct Book {
        let spinePaths: [String]
        let total: () -> Int
        let position: (Int) -> (document: Int, page: Int)?
        let makeRenderer: () async throws -> EpubSpineRenderer
    }

    private let book: Book

    // around every page's web view, so each lays out at the same viewport and paginates the same
    // way the measurement pass did
    private let contentInsets: UIEdgeInsets

    private(set) var currentBookPage = 0

    /// The page being read changed, by gesture or by navigation.
    var onPageChanged: ((Int) -> Void)?

    /// A swipe is about to turn the page.
    var onWillTurn: (() -> Void)?

    private let pageViewController = UIPageViewController(
        // scroll, not pageCurl: it is what the paged text and image readers use, and the curl can
        // become an option later without the pages changing
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: nil
    )

    // MARK: - Renderer roster

    // more than the page controller retains, so prefetching the next page does not steal the web
    // view out of the one being read. anything above this is web content processes the system
    // jettisons on an iPad in two columns
    private static let rendererCapacity = 4

    private var renderers: [EpubSpineRenderer] = []

    // which spine document a renderer holds; a renderer mid-load holds its target, so a second
    // provision cannot grab it and load something else over it
    private var rendererDocuments: [ObjectIdentifier: Int] = [:]

    // which page's controller a renderer is leased to
    private var rendererLeases: [ObjectIdentifier: Int] = [:]

    // MARK: - Page controllers

    // the pages the book is currently near, so a turn lands on the same instance the data source
    // handed out and identity checks hold
    private var pageControllers: [Int: EpubPageViewController] = [:]

    private var provisionTasks: [Int: Task<Void, Never>] = [:]

    init(book: Book, contentInsets: UIEdgeInsets) {
        self.book = book
        self.contentInsets = contentInsets
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for task in provisionTasks.values {
            task.cancel()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        pageViewController.dataSource = self
        pageViewController.delegate = self
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageViewController.didMove(toParent: self)
    }

    // MARK: - The current page

    var currentPageController: EpubPageViewController? {
        pageViewController.viewControllers?.first as? EpubPageViewController
    }

    /// The renderer showing the page being read, for hit tests and fragment lookups.
    var currentRenderer: EpubSpineRenderer? {
        guard let controller = currentPageController else { return nil }
        return renderers.first { rendererLeases[ObjectIdentifier($0)] == controller.bookPage }
    }

    var currentWebView: WKWebView? {
        currentPageController?.webView
    }

    // MARK: - Navigation

    /// Shows a book page without an animation, building it first so nothing blank is revealed.
    func open(atBookPage bookPage: Int) async {
        await show(bookPage: bookPage, direction: .forward, animated: false)
    }

    func show(bookPage: Int, animated: Bool) async {
        let direction: UIPageViewController.NavigationDirection =
            bookPage >= currentBookPage ? .forward : .reverse
        await show(bookPage: bookPage, direction: direction, animated: animated)
    }

    /// One page forward or back, the same animation a swipe settles on.
    func turn(forward: Bool, animated: Bool) async {
        let target = currentBookPage + (forward ? 1 : -1)
        guard target >= 0, target < book.total() else { return }
        await show(bookPage: target, direction: forward ? .forward : .reverse, animated: animated)
    }

    private func show(
        bookPage: Int,
        direction: UIPageViewController.NavigationDirection,
        animated: Bool
    ) async {
        let total = book.total()
        guard total > 0 else { return }
        let target = min(max(bookPage, 0), total - 1)
        guard let controller = pageController(for: target) else { return }
        await provision(controller)
        // re-read after the await: a gesture may have turned the book meanwhile, and setting an
        // already current page again would stutter the scroll view
        guard currentPageController !== controller else {
            settle(on: target)
            return
        }
        currentBookPage = target
        await withCheckedContinuation { continuation in
            pageViewController.setViewControllers([controller], direction: direction, animated: animated) { _ in
                continuation.resume()
            }
        }
        settle(on: target)
    }

    private func settle(on bookPage: Int) {
        currentBookPage = bookPage
        onPageChanged?(bookPage)
        prunePageControllers()
        prefetchNeighbours()
    }

    // MARK: - Building pages

    private func pageController(for bookPage: Int) -> EpubPageViewController? {
        if let existing = pageControllers[bookPage] {
            return existing
        }
        guard let position = book.position(bookPage) else { return nil }
        let controller = EpubPageViewController(
            bookPage: bookPage,
            document: position.document,
            pageInDocument: position.page,
            insets: contentInsets
        )
        pageControllers[bookPage] = controller
        return controller
    }

    /// Loads the page's document into a leased renderer and puts its web view on the page.
    private func provision(_ controller: EpubPageViewController) async {
        guard !controller.isDisplaying else { return }
        let bookPage = controller.bookPage
        if let running = provisionTasks[bookPage] {
            return await running.value
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await runProvision(controller)
        }
        provisionTasks[bookPage] = task
        await task.value
        provisionTasks[bookPage] = nil
    }

    private func runProvision(_ controller: EpubPageViewController) async {
        guard let renderer = await lease(for: controller) else { return }
        let key = ObjectIdentifier(renderer)
        do {
            if rendererDocuments[key] != controller.document {
                rendererDocuments[key] = controller.document
                // sized and laid out before the load, as the measurement pass does: pagination
                // happens at whatever viewport the web view has when the document lands
                renderer.webView.frame = CGRect(origin: .zero, size: pageContentSize())
                renderer.webView.layoutIfNeeded()
                try await renderer.load(spinePath: book.spinePaths[controller.document])
            }
            // the lease can move under the load: a burst of turns re-plans the roster, and this
            // page may have lost the renderer to one closer to where the reader ended up
            guard rendererLeases[key] == controller.bookPage else { return }
            await renderer.showPage(controller.pageInDocument)
            // and under the scroll, which suspends the same way
            guard rendererLeases[key] == controller.bookPage else { return }
            controller.display(renderer.webView)
        } catch {
            rendererDocuments[key] = nil
            rendererLeases[key] = nil
            LogManager.logger.error(
                "EpubPagedViewController: could not lay out \(book.spinePaths[controller.document]): \(error)"
            )
        }
    }

    private func pageContentSize() -> CGSize {
        let bounds = view.bounds.inset(by: contentInsets)
        return CGSize(width: max(bounds.width, 0), height: max(bounds.height, 0))
    }

    /// A renderer for the page, taking one whose page has fallen out of reach if none is spare.
    private func lease(for controller: EpubPageViewController) async -> EpubSpineRenderer? {
        func reclaimable(_ renderer: EpubSpineRenderer) -> Bool {
            guard let leased = rendererLeases[ObjectIdentifier(renderer)] else { return true }
            // the page being read and its immediate pair keep theirs; everything further is a
            // page the reader has left behind
            return abs(leased - currentBookPage) > 1 && leased != controller.bookPage
        }

        let candidates = renderers.filter(reclaimable)
        // one already on the right document turns a reprovision into a scroll
        let chosen = candidates.first { rendererDocuments[ObjectIdentifier($0)] == controller.document }
            ?? candidates.max { leaseDistance($0) < leaseDistance($1) }

        if let chosen {
            take(chosen, for: controller)
            return chosen
        }
        guard renderers.count < Self.rendererCapacity else { return nil }
        do {
            let renderer = try await book.makeRenderer()
            // the roster may have filled while the renderer was built
            guard renderers.count < Self.rendererCapacity else { return nil }
            renderers.append(renderer)
            wire(renderer)
            take(renderer, for: controller)
            return renderer
        } catch {
            LogManager.logger.error("EpubPagedViewController: could not build a renderer: \(error)")
            return nil
        }
    }

    private func leaseDistance(_ renderer: EpubSpineRenderer) -> Int {
        guard let leased = rendererLeases[ObjectIdentifier(renderer)] else { return .max }
        return abs(leased - currentBookPage)
    }

    private func take(_ renderer: EpubSpineRenderer, for controller: EpubPageViewController) {
        let key = ObjectIdentifier(renderer)
        if let previous = rendererLeases[key], let holder = pageControllers[previous] {
            _ = holder.surrender()
        }
        rendererLeases[key] = controller.bookPage
    }

    private func wire(_ renderer: EpubSpineRenderer) {
        renderer.onContentProcessTerminated = { [weak self, weak renderer] in
            guard let self, let renderer else { return }
            let key = ObjectIdentifier(renderer)
            rendererDocuments[key] = nil
            let holder = rendererLeases[key].flatMap { self.pageControllers[$0] }
            rendererLeases[key] = nil
            if let holder {
                _ = holder.surrender()
                // the page being read cannot wait for a turn to be rebuilt
                if holder === currentPageController {
                    Task { [weak self] in await self?.provision(holder) }
                }
            }
        }
    }

    // MARK: - Selection

    /// Whether the page being read has its web view taking touches for a text selection.
    private(set) var isSelecting = false

    /// The selection collapsed, by a tap or a turn.
    var onSelectionEnded: (() -> Void)?

    private var selectionWatch: Task<Void, Never>?

    /// Selects the word under the point and hands the page's web view its touches, so WebKit's
    /// own handles and callout take over. While it holds them the page controller's pan cannot
    /// begin, which is what keeps a selection drag from turning the page.
    func beginSelection(at point: CGPoint) async {
        guard !isSelecting, let renderer = currentRenderer, let webView = currentWebView else { return }
        let local = view.convert(point, to: webView)
        guard webView.bounds.contains(local) else { return }
        let word = await renderer.selectWord(at: local)
        guard !word.isEmpty else { return }
        isSelecting = true
        webView.isUserInteractionEnabled = true
        renderer.lockPage()
        // a handle dragged to the screen edge autoscrolls the enclosing scroll view, which is the
        // page controller's; without a data source it has nowhere to go
        pageViewController.dataSource = nil
        webView.becomeFirstResponder()
        selectionWatch = Task { [weak self, weak renderer, weak webView] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, let renderer, let webView else { return }
                let text = await renderer.selectedText()
                if text.isEmpty || webView !== self.currentWebView {
                    self.endSelection(on: webView, renderer: renderer)
                    return
                }
            }
        }
    }

    private func endSelection(on webView: WKWebView, renderer: EpubSpineRenderer) {
        selectionWatch?.cancel()
        selectionWatch = nil
        isSelecting = false
        webView.isUserInteractionEnabled = false
        pageViewController.dataSource = self
        webView.resignFirstResponder()
        Task {
            await renderer.clearSelection()
            await renderer.unlockPage()
        }
        onSelectionEnded?()
    }

    // MARK: - Housekeeping

    private func prefetchNeighbours() {
        for neighbour in [currentBookPage + 1, currentBookPage - 1] {
            guard neighbour >= 0, neighbour < book.total() else { continue }
            guard let controller = pageController(for: neighbour), !controller.isDisplaying else { continue }
            Task { [weak self] in await self?.provision(controller) }
        }
    }

    private func prunePageControllers() {
        let retained = Set((pageViewController.viewControllers ?? []).compactMap {
            ($0 as? EpubPageViewController)?.bookPage
        })
        for (bookPage, controller) in pageControllers {
            guard abs(bookPage - currentBookPage) > 1, !retained.contains(bookPage) else { continue }
            if let webView = controller.surrender() {
                let key = renderers.first { $0.webView === webView }.map(ObjectIdentifier.init)
                if let key, rendererLeases[key] == bookPage {
                    rendererLeases[key] = nil
                }
            }
            provisionTasks[bookPage]?.cancel()
            provisionTasks[bookPage] = nil
            pageControllers[bookPage] = nil
        }
    }

    /// Gives back everything but the page being read and its immediate pair, for a memory warning.
    func releaseSpares() {
        prunePageControllers()
        renderers.removeAll { renderer in
            let key = ObjectIdentifier(renderer)
            guard rendererLeases[key] == nil else { return false }
            rendererDocuments[key] = nil
            return true
        }
    }
}

// MARK: - Data source

extension EpubPagedViewController: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? EpubPageViewController else { return nil }
        let next = page.bookPage + 1
        guard next < book.total() else { return nil }
        guard let controller = pageController(for: next) else { return nil }
        if !controller.isDisplaying {
            Task { [weak self] in await self?.provision(controller) }
        }
        return controller
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? EpubPageViewController else { return nil }
        let previous = page.bookPage - 1
        guard previous >= 0 else { return nil }
        guard let controller = pageController(for: previous) else { return nil }
        if !controller.isDisplaying {
            Task { [weak self] in await self?.provision(controller) }
        }
        return controller
    }
}

// MARK: - Delegate

extension EpubPagedViewController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        onWillTurn?()
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let page = currentPageController else { return }
        settle(on: page.bookPage)
    }
}
