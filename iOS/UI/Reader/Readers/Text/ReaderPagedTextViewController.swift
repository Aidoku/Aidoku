//
//  ReaderPagedTextViewController.swift
//  Aidoku
//
//  Kindle-style paginated text reader with horizontal page flipping.
//  Supports single page and two-page spread layouts.
//

import AidokuRunner
import SwiftUI
import UIKit
import ZIPFoundation

class ReaderPagedTextViewController: BaseObservingViewController {
    // MARK: - Properties
    let viewModel: ReaderTextViewModel
    weak var delegate: ReaderHoldingDelegate?

    var chapter: AidokuRunner.Chapter?
    var readingMode: ReadingMode = .ltr {
        didSet {
            // For text content, always use LTR regardless of manga setting
            // (Western text reads left-to-right)
            if readingMode == .rtl {
                // Don't recursively trigger didSet
                return
            }
            guard readingMode != oldValue else { return }
            refreshPages()
        }
    }

    // Override to always return LTR for text
    private var effectiveReadingMode: ReadingMode {
        .ltr  // Text always reads left-to-right
    }

    private let paginator = TextPaginator()
    private var pages: [TextPage] = []
    private var currentPageIndex = 0
    private var currentCharacterOffset = 0  // Character offset for position restoration after repagination
    private var isLoadingChapter = false  // Prevent race conditions
    private var lastPaginationSize: CGSize = .zero  // Track size to avoid repagination loops

    /// Fixed text insets used by child page view controllers.
    /// Computed once during pagination and kept constant so text doesn't shift
    /// when bars hide/show.
    private(set) var textInsets: UIEdgeInsets = .zero

    /// Indicates whether pagination has been performed for the current chapter.
    /// Used to distinguish between the pre-pagination placeholder and actual paginated content.
    private(set) var hasPaginated = false
    /// Tracks the requested start page (from reading history) so `repaginate()` can
    /// restore the correct position after the initial pagination completes.
    private var pendingStartPage: Int?

    // MARK: - Persistent Character Offset

    /// Save character offset for the current chapter so position survives font/size changes
    /// and cross-session restores.
    private func saveCharacterOffset() {
        guard let chapterKey = chapter?.key else { return }
        UserDefaults.standard.set(currentCharacterOffset, forKey: "TextReader.offset.\(chapterKey)")

        // Also save normalized progress (0.0–1.0) so scroll reader can restore position
        let totalPages = max(1, pages.count)
        let currentIndex = pages.lastIndex(where: { $0.range.location <= currentCharacterOffset }) ?? 0
        let progress = Double(currentIndex) / Double(max(1, totalPages - 1))
        UserDefaults.standard.set(progress, forKey: "TextReader.progress.\(chapterKey)")
    }

    /// Load a previously saved character offset for a chapter. Returns nil if none stored.
    private func loadCharacterOffset(for chapterKey: String) -> Int? {
        let value = UserDefaults.standard.object(forKey: "TextReader.offset.\(chapterKey)")
        return value as? Int
    }

    // Double page support
    private var usesDoublePages = false
    private var usesAutoPageLayout = false

    // Page view controller
    private lazy var pageViewController: UIPageViewController = {
        // Scroll is more reliable than pageCurl
        UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
    }()

    // Chapter navigation
    private var previousChapter: AidokuRunner.Chapter?
    private var nextChapter: AidokuRunner.Chapter?

    // MARK: - Initialization

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
        self.viewModel = ReaderTextViewModel(source: source, manga: manga)
        super.init()
    }

    // MARK: - Lifecycle

    override func configure() {
        pageViewController.delegate = self
        pageViewController.dataSource = self

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

        updatePageLayout()
        updateTextConfig()  // Apply saved text settings
    }

    override func observe() {
        addObserver(forName: "Reader.pagedPageLayout") { [weak self] _ in
            self?.updatePageLayout()
            self?.refreshPages()
        }

        // Text reader settings
        let textSettingChanged: (Notification) -> Void = { [weak self] _ in
            self?.updateTextConfig()
        }
        for key in ["Reader.textFontSize", "Reader.textLineSpacing", "Reader.textHorizontalPadding", "Reader.textFontFamily"] {
            addObserver(forName: key, using: textSettingChanged)
        }
    }

    private func updateTextConfig() {
        var config = PaginationConfig()

        // Load settings - PaginationConfig provides the defaults
        if let fontSize = UserDefaults.standard.object(forKey: "Reader.textFontSize") as? CGFloat {
            config.fontSize = fontSize
        }
        if let lineSpacing = UserDefaults.standard.object(forKey: "Reader.textLineSpacing") as? CGFloat {
            config.lineSpacing = lineSpacing
        }
        if let horizontalPadding = UserDefaults.standard.object(forKey: "Reader.textHorizontalPadding") as? CGFloat {
            config.horizontalPadding = horizontalPadding
        }
        if let fontFamily = UserDefaults.standard.string(forKey: "Reader.textFontFamily") {
            config.fontName = fontFamily
        }

        paginator.updateConfig(config)

        // Repaginate with new settings
        if !pages.isEmpty {
            repaginate()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Repaginate if view size changed significantly (e.g., rotation)
        let newSize = view.bounds.size
        if !pages.isEmpty && lastPaginationSize != .zero {
            if abs(lastPaginationSize.width - newSize.width) > 10 ||
               abs(lastPaginationSize.height - newSize.height) > 10 {
                repaginate()
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }

            if self.usesAutoPageLayout {
                let newUsesDouble = size.width > size.height
                if newUsesDouble != self.usesDoublePages {
                    self.usesDoublePages = newUsesDouble
                }
            }

            self.repaginate()
        }
    }

    // Safe area changes from bar toggles are intentionally ignored.
    // We use the window's safe area (constant physical insets) for pagination.
    // Rotation is handled by viewWillTransition(to:with:) and viewDidLayoutSubviews.

    // MARK: - Layout

    private func updatePageLayout() {
        usesAutoPageLayout = false
        switch UserDefaults.standard.string(forKey: "Reader.pagedPageLayout") {
            case "single":
                usesDoublePages = false
            case "double":
                usesDoublePages = true
            case "auto":
                usesAutoPageLayout = true
                usesDoublePages = view.bounds.width > view.bounds.height
            default:
                usesDoublePages = false
        }
    }

    // MARK: - Pagination

    private func repaginate() {
        guard let text = getCurrentText(), !text.isEmpty else {
            return
        }

        // Wait for valid bounds — viewDidLayoutSubviews will trigger repagination
        guard view.bounds.width > 0 && view.bounds.height > 0 else {
            return
        }

        // Use the window's safe area (physical notch/home indicator) which stays
        // constant regardless of bar visibility. This prevents text from shifting
        // when bars are toggled.
        let windowSafeArea = view.window?.safeAreaInsets ?? view.safeAreaInsets
        let toolbarBuffer: CGFloat = 100  // Fixed space reserved for nav bar + toolbar
        let safeWidth = view.bounds.width - windowSafeArea.left - windowSafeArea.right
        let safeHeight = view.bounds.height - windowSafeArea.top - windowSafeArea.bottom - toolbarBuffer

        // Compute fixed text insets for child page VCs (must match pagination geometry)
        let config = paginator.currentConfig
        textInsets = UIEdgeInsets(
            top: windowSafeArea.top + toolbarBuffer / 2 + config.verticalPadding,
            left: windowSafeArea.left + config.horizontalPadding,
            bottom: windowSafeArea.bottom + toolbarBuffer / 2 + config.verticalPadding,
            right: windowSafeArea.right + config.horizontalPadding
        )

        let pageSize: CGSize
        if usesDoublePages {
            // For double page, each page is half width
            pageSize = CGSize(width: safeWidth / 2, height: safeHeight)
        } else {
            pageSize = CGSize(width: safeWidth, height: safeHeight)
        }

        // Track size to prevent repagination loops
        lastPaginationSize = view.bounds.size

        pages = paginator.paginate(markdown: text, pageSize: pageSize)
        hasPaginated = true

        // Update toolbar with our paginated page count
        // ReaderViewController now knows to not switch away when we're already
        // in the paginated text reader with text pages
        if !pages.isEmpty {
            let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
            let chapterId = chapter?.key ?? ""
            // Check if any source page has a description
            let sourceHasDescription = viewModel.pages.contains { $0.hasDescription }
            let placeholderPages: [Page] = pages.map { textPage in
                var page = Page(sourceId: sourceId, chapterId: chapterId)
                page.index = textPage.id
                page.text = "page"  // Mark as text page
                // Carry description info so the info button appears on every page
                if sourceHasDescription {
                    page.hasDescription = true
                    // Copy the actual description from source pages if available
                    if let desc = viewModel.pages.compactMap({ $0.description }).first {
                        page.description = desc
                    }
                }
                return page
            }
            delegate?.setPages(placeholderPages)
        }

        // Determine which page to show
        let targetIndex: Int
        if let pending = pendingStartPage {
            pendingStartPage = nil  // Clear after using

            // If pending <= 0, this chapter is completed or has no history - start from beginning
            if pending <= 0 {
                targetIndex = 0
                currentCharacterOffset = 0
            } else if pending == Int.max {
                // Coming from next chapter (swiping back) — always go to last page
                targetIndex = pages.count - 1
                currentCharacterOffset = pages[targetIndex].range.location
            } else if let chapterKey = chapter?.key,
               let storedOffset = loadCharacterOffset(for: chapterKey) {
                // First try to restore from our stored character offset (survives font changes)
                currentCharacterOffset = storedOffset
                targetIndex = pages.lastIndex(where: { $0.range.location <= storedOffset }) ?? 0
            } else if let chapterKey = chapter?.key,
                      let progress = UserDefaults.standard.object(forKey: "TextReader.progress.\(chapterKey)") as? Double {
                // Fall back to shared progress (e.g. from scroll reader)
                let idx = Int(progress * Double(max(1, pages.count - 1)))
                targetIndex = min(max(0, idx), pages.count - 1)
                currentCharacterOffset = pages[targetIndex].range.location
            } else {
                // Fall back to page number from History (first open, no stored offset)
                targetIndex = min(pending - 1, pages.count - 1)
                currentCharacterOffset = pages[targetIndex].range.location
            }
        } else {
            // In-session repagination (font/size change) – use current character offset
            targetIndex = pages.lastIndex(where: { $0.range.location <= currentCharacterOffset }) ?? 0
        }

        move(toPage: min(targetIndex, max(0, pages.count - 1)), animated: false)
    }

    private func getCurrentText() -> String? {
        guard let page = viewModel.pages.first else {
            return nil
        }

        // Direct text content
        if let text = page.text {
            return text
        }

        // Load text from ZIP archive (for downloaded chapters)
        guard
            let zipURLString = page.zipURL,
            let zipURL = URL(string: zipURLString),
            let filePath = page.imageURL
        else {
            return nil
        }

        do {
            var data = Data()
            let archive = try Archive(url: zipURL, accessMode: .read)
            guard let entry = archive[filePath] else {
                return nil
            }
            _ = try archive.extract(
                entry,
                consumer: { readData in
                    data.append(readData)
                }
            )
            let text = String(data: data, encoding: .utf8)
            return text
        } catch {
            return nil
        }
    }

    private func refreshPages() {
        repaginate()
    }

    // MARK: - Navigation

    func move(toPage index: Int, animated: Bool) {
        guard !pages.isEmpty else {
            return
        }

        let targetIndex = min(max(0, index), pages.count - 1)

        let oldIndex = currentPageIndex
        currentPageIndex = targetIndex

        // Track character offset for position restoration after repagination
        if targetIndex < pages.count {
            currentCharacterOffset = pages[targetIndex].range.location
            saveCharacterOffset()
        }

        let viewController = createPageViewController(for: targetIndex)

        let direction: UIPageViewController.NavigationDirection
        if effectiveReadingMode == .rtl {
            direction = targetIndex < oldIndex ? .forward : .reverse
        } else {
            direction = targetIndex > oldIndex ? .forward : .reverse
        }

        pageViewController.setViewControllers(
            [viewController],
            direction: direction,
            animated: animated
        ) { [weak self] completed in
            if completed {
                self?.updateSliderPosition()
            }
        }

        // Update current page display (1-indexed for UI)
        delegate?.setCurrentPage(targetIndex + 1)
        updateSliderPosition()
    }

    private func createPageViewController(for index: Int) -> UIViewController {

        guard index >= 0 && index < pages.count else {
            // Return empty view controller as fallback
            let vc = UIViewController()
            vc.view.backgroundColor = .systemRed
            return vc
        }

        if usesDoublePages && index + 1 < pages.count {
            // Double page spread
            return TextDoublePageViewController(
                leftPage: pages[index],
                rightPage: pages[index + 1],
                direction: effectiveReadingMode == .rtl ? .rtl : .ltr,
                parentReader: self
            )
        } else {
            // Single page - pass parent reference so it can get live safe area updates
            return TextSinglePageViewController(page: pages[index], parentReader: self)
        }
    }

    private func updateSliderPosition() {
        guard !pages.isEmpty else { return }
        let offset = CGFloat(currentPageIndex) / CGFloat(max(1, pages.count - 1))
        delegate?.setSliderOffset(offset)
    }

    // MARK: - Chapter Loading

    func loadChapter(_ chapter: AidokuRunner.Chapter, startPage: Int = 0) async {

        isLoadingChapter = true
        hasPaginated = false
        self.chapter = chapter

        await viewModel.loadPages(chapter: chapter)

        guard !viewModel.pages.isEmpty else {
            isLoadingChapter = false
            return
        }

        // Don't paginate non-text chapters — the reading mode would need to
        // switch. Inform the delegate about the pages and let the parent
        // controller handle the mode change.
        guard viewModel.pages.allSatisfy({ $0.isTextPage }) else {
            await MainActor.run {
                delegate?.setPages(viewModel.pages)
                isLoadingChapter = false
            }
            return
        }

        await MainActor.run {
            previousChapter = delegate?.getPreviousChapter()
            nextChapter = delegate?.getNextChapter()

            // Ensure view is laid out before paginating
            view.layoutIfNeeded()

            // Set pending start page before repaginate
            // startPage <= 0 means no history exists - start from beginning
            pendingStartPage = startPage

            repaginate()

            isLoadingChapter = false
        }
    }
}

// MARK: - Reader Delegate
extension ReaderPagedTextViewController: ReaderReaderDelegate {
    func moveLeft() {
        let targetIndex: Int
        switch effectiveReadingMode {
            case .rtl:
                targetIndex = currentPageIndex + (usesDoublePages ? 2 : 1)
            default:
                targetIndex = currentPageIndex - (usesDoublePages ? 2 : 1)
        }

        if targetIndex >= 0 && targetIndex < pages.count {
            move(toPage: targetIndex, animated: UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions"))
        } else if targetIndex < 0 {
            // Load previous chapter
            loadPreviousChapter()
        }
    }

    func moveRight() {
        let targetIndex: Int
        switch effectiveReadingMode {
            case .rtl:
                targetIndex = currentPageIndex - (usesDoublePages ? 2 : 1)
            default:
                targetIndex = currentPageIndex + (usesDoublePages ? 2 : 1)
        }

        if targetIndex >= 0 && targetIndex < pages.count {
            move(toPage: targetIndex, animated: UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions"))
        } else if targetIndex >= pages.count {
            // Load next chapter
            loadNextChapter()
        }
    }

    func sliderMoved(value: CGFloat) {
        let targetPage = Int(value * CGFloat(pages.count - 1))
        delegate?.displayPage(targetPage + 1)
    }

    func sliderStopped(value: CGFloat) {
        let targetPage = Int(value * CGFloat(pages.count - 1))
        move(toPage: targetPage, animated: false)
    }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {

        // Prevent reloading if we're already loading
        if isLoadingChapter {
            return
        }

        // Prevent reloading the same chapter if we already have paginated pages
        if self.chapter?.key == chapter.key && !pages.isEmpty {
            if startPage > 0 && startPage <= pages.count {
                move(toPage: startPage - 1, animated: false)
            }
            return
        }

        // Check if viewModel already has the page loaded (from ReaderViewController's initial load)
        // This prevents double-fetching the chapter
        if !viewModel.pages.isEmpty {
            self.chapter = chapter
            isLoadingChapter = true
            hasPaginated = false
            // Store the requested start page - repaginate will use this
            // startPage <= 0 means no history exists - start from beginning
            pendingStartPage = startPage
            view.layoutIfNeeded()
            repaginate()
            isLoadingChapter = false
            return
        }

        Task {
            await loadChapter(chapter, startPage: startPage)
        }
    }

    func loadPreviousChapter() {
        guard let previousChapter else { return }
        Task {
            // Preload and verify the chapter has text pages before switching.
            // Non-text chapters would require a reading-mode change that the
            // paged text reader can't handle — snap back to the transition page.
            await viewModel.preload(chapter: previousChapter)
            let preloaded = viewModel.preloadedPages
            guard !preloaded.isEmpty, preloaded.allSatisfy({ $0.isTextPage }) else {
                await MainActor.run { snapBackToTransitionPage() }
                return
            }
            delegate?.setChapter(previousChapter)
            await loadChapter(previousChapter, startPage: Int.max)
        }
    }

    func loadNextChapter() {
        guard let nextChapter else { return }
        Task {
            await viewModel.preload(chapter: nextChapter)
            let preloaded = viewModel.preloadedPages
            guard !preloaded.isEmpty, preloaded.allSatisfy({ $0.isTextPage }) else {
                await MainActor.run { snapBackToTransitionPage() }
                return
            }
            delegate?.setChapter(nextChapter)
            await loadChapter(nextChapter, startPage: 0)
        }
    }

    /// Navigate back from the blank trigger page to the visible transition page.
    private func snapBackToTransitionPage() {
        guard let currentVC = pageViewController.viewControllers?.first,
              let triggerVC = currentVC as? ChapterLoadTriggerViewController else { return }
        pageViewController.setViewControllers(
            [triggerVC.transitionVC],
            direction: .reverse,
            animated: true
        )
    }
}

// MARK: - Page View Controller Delegate
extension ReaderPagedTextViewController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let currentVC = pageViewController.viewControllers?.first else {
            return
        }

        // When user swipes past the transition page onto the trigger page, load the chapter
        if let triggerVC = currentVC as? ChapterLoadTriggerViewController {
            triggerVC.transitionVC.performTransition()
            return
        }

        // Transition info page itself — just display, no auto-navigation
        if currentVC is ChapterTransitionViewController {
            return
        }

        if let singlePage = currentVC as? TextSinglePageViewController {
            currentPageIndex = singlePage.page.id
            currentCharacterOffset = singlePage.page.range.location
        } else if let doublePage = currentVC as? TextDoublePageViewController {
            currentPageIndex = doublePage.leftPage.id
            currentCharacterOffset = doublePage.leftPage.range.location
        }
        saveCharacterOffset()

        delegate?.setCurrentPage(currentPageIndex + 1)
        updateSliderPosition()
    }
}

// MARK: - Page View Controller Data Source
extension ReaderPagedTextViewController: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        // Past the trigger page — nothing further
        if viewController is ChapterLoadTriggerViewController {
            return nil
        }

        // Transition info page
        if let transitionVC = viewController as? ChapterTransitionViewController {
            if transitionVC.direction == .next {
                // "Next chapter" transition: swiping forward = trigger load
                guard transitionVC.chapter != nil else { return nil }
                return ChapterLoadTriggerViewController(transitionVC: transitionVC)
            } else {
                // "Previous chapter" transition: swiping forward = back to first text page
                guard !pages.isEmpty else { return nil }
                return createPageViewController(for: 0)
            }
        }

        let currentIndex = getCurrentIndex(from: viewController)

        let nextIndex: Int
        switch effectiveReadingMode {
            case .rtl:
                nextIndex = currentIndex - (usesDoublePages ? 2 : 1)
            default:
                nextIndex = currentIndex + (usesDoublePages ? 2 : 1)
        }

        if nextIndex >= 0 && nextIndex < pages.count {
            return createPageViewController(for: nextIndex)
        } else if nextIndex >= pages.count {
            // Show chapter transition page (matching image reader style)
            let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
            return ChapterTransitionViewController(
                direction: .next,
                chapter: nextChapter,
                currentChapter: chapter,
                sourceId: sourceId,
                mangaId: viewModel.manga.key,
                parentReader: self
            )
        }
        return nil
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        // Past the trigger page — nothing further
        if viewController is ChapterLoadTriggerViewController {
            return nil
        }

        // Transition info page
        if let transitionVC = viewController as? ChapterTransitionViewController {
            if transitionVC.direction == .previous {
                // "Previous chapter" transition: swiping backward = trigger load
                guard transitionVC.chapter != nil else { return nil }
                return ChapterLoadTriggerViewController(transitionVC: transitionVC)
            } else {
                // "Next chapter" transition: swiping backward = back to last text page
                guard !pages.isEmpty else { return nil }
                return createPageViewController(for: pages.count - 1)
            }
        }

        let currentIndex = getCurrentIndex(from: viewController)

        let prevIndex: Int
        switch effectiveReadingMode {
            case .rtl:
                prevIndex = currentIndex + (usesDoublePages ? 2 : 1)
            default:
                prevIndex = currentIndex - (usesDoublePages ? 2 : 1)
        }

        if prevIndex >= 0 && prevIndex < pages.count {
            return createPageViewController(for: prevIndex)
        } else if prevIndex < 0 {
            // Show chapter transition page (matching image reader style)
            let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
            return ChapterTransitionViewController(
                direction: .previous,
                chapter: previousChapter,
                currentChapter: chapter,
                sourceId: sourceId,
                mangaId: viewModel.manga.key,
                parentReader: self
            )
        }
        return nil
    }

    private func getCurrentIndex(from viewController: UIViewController) -> Int {
        if let singlePage = viewController as? TextSinglePageViewController {
            return singlePage.page.id
        } else if let doublePage = viewController as? TextDoublePageViewController {
            return doublePage.leftPage.id
        }
        return currentPageIndex
    }
}
