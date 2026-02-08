//
//  ReaderPagedTextViewController.swift
//  Aidoku
//
//  Created by Minirob on 2/2/26.
//
//  Kindle-style paginated text reader with horizontal page flipping.
//  Supports single page and two-page spread layouts.
//

import AidokuRunner
import UIKit
import SwiftUI
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
        return .ltr  // Text always reads left-to-right
    }
    
    private let paginator = TextPaginator()
    private var pages: [TextPage] = []
    private var currentPageIndex = 0
    private var isLoadingChapter = false  // Prevent race conditions
    private var lastPaginationSize: CGSize = .zero  // Track size to avoid repagination loops
    private var pendingStartPage: Int?  // Track requested start page for after pagination
    
    // Double page support - DISABLED FOR NOW until single page works
    private var usesDoublePages = false  // TODO: Re-enable after fixing
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
        addObserver(forName: "Reader.textFontSize") { [weak self] _ in
            self?.updateTextConfig()
        }
        addObserver(forName: "Reader.textLineSpacing") { [weak self] _ in
            self?.updateTextConfig()
        }
        addObserver(forName: "Reader.textHorizontalPadding") { [weak self] _ in
            self?.updateTextConfig()
        }
        addObserver(forName: "Reader.textFontFamily") { [weak self] _ in
            self?.updateTextConfig()
        }
    }
    
    private func updateTextConfig() {
        var config = PaginationConfig()
        
        // Load settings with defaults
        let fontSize = UserDefaults.standard.object(forKey: "Reader.textFontSize") as? CGFloat ?? 18
        let lineSpacing = UserDefaults.standard.object(forKey: "Reader.textLineSpacing") as? CGFloat ?? 8
        let horizontalPadding = UserDefaults.standard.object(forKey: "Reader.textHorizontalPadding") as? CGFloat ?? 24
        let fontFamily = UserDefaults.standard.string(forKey: "Reader.textFontFamily") ?? "Georgia"
        
        config.fontSize = fontSize
        config.lineSpacing = lineSpacing
        config.horizontalPadding = horizontalPadding
        config.fontName = fontFamily
        
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
    
    private var lastSafeAreaInsets: UIEdgeInsets = .zero
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        
        // Only repaginate on significant safe area changes (rotation, not menu toggle)
        // Menu changes typically only affect top/bottom by small amounts
        let newInsets = view.safeAreaInsets
        let leftRightChange = abs(newInsets.left - lastSafeAreaInsets.left) + abs(newInsets.right - lastSafeAreaInsets.right)
        
        // Significant change = rotation (left/right insets change significantly)
        if leftRightChange > 20 && !pages.isEmpty {
            lastSafeAreaInsets = newInsets
            repaginate()
        } else if lastSafeAreaInsets == .zero {
            lastSafeAreaInsets = newInsets
        }
    }
    
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
        
        // Make sure we have valid bounds
        guard view.bounds.width > 0 && view.bounds.height > 0 else {
            // Defer pagination until layout is complete
            DispatchQueue.main.async { [weak self] in
                self?.repaginate()
            }
            return
        }
        
        // Calculate page size accounting for safe area (notch, home indicator)
        // Reserve extra space for toolbar (~100pt) so pagination is consistent
        // whether toolbar is visible or hidden
        let safeArea = view.safeAreaInsets
        let toolbarBuffer: CGFloat = 100  // Space for nav bar + toolbar when visible
        let safeWidth = view.bounds.width - safeArea.left - safeArea.right
        let safeHeight = view.bounds.height - safeArea.top - safeArea.bottom - toolbarBuffer
        
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
        
        
        // Update toolbar with our paginated page count
        // ReaderViewController now knows to not switch away when we're already
        // in the paginated text reader with text pages
        if !pages.isEmpty {
            let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
            let chapterId = chapter?.key ?? ""
            let placeholderPages: [Page] = pages.map { textPage in
                var page = Page(sourceId: sourceId, chapterId: chapterId)
                page.index = textPage.id
                page.text = "page"  // Mark as text page
                return page
            }
            delegate?.setPages(placeholderPages)
        }
        
        // Determine which page to show
        let targetIndex: Int
        if let pending = pendingStartPage, pending > 0 {
            // Use the requested start page (1-indexed from History)
            targetIndex = min(pending - 1, pages.count - 1)
            pendingStartPage = nil  // Clear after using
        } else {
            // Restore approximate position (for resize/rotation)
            let progress = CGFloat(currentPageIndex) / CGFloat(max(1, pages.count))
            targetIndex = Int(progress * CGFloat(pages.count))
        }
        
        move(toPage: min(targetIndex, max(0, pages.count - 1)), animated: false)
    }
    
    private func getCurrentText() -> String? {
        guard let page = viewModel.pages.first else {
            return nil
        }
        
        
        // Direct text content
        if let text = page.text {
            let preview = String(text.prefix(200))
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
        self.chapter = chapter
        
        await viewModel.loadPages(chapter: chapter)
        
        guard !viewModel.pages.isEmpty else {
            isLoadingChapter = false
            return
        }
        
        
        await MainActor.run {
            previousChapter = delegate?.getPreviousChapter()
            nextChapter = delegate?.getNextChapter()
            
            // Ensure view is laid out before paginating
            view.layoutIfNeeded()
            
            // Set pending start page before repaginate
            pendingStartPage = startPage > 0 ? startPage : 1
            
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
            // Store the requested start page - repaginate will use this
            pendingStartPage = startPage > 0 ? startPage : 1
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
        delegate?.setChapter(previousChapter)
        Task {
            await loadChapter(previousChapter, startPage: Int.max)
        }
    }
    
    func loadNextChapter() {
        guard let nextChapter else { return }
        delegate?.setChapter(nextChapter)
        Task {
            await loadChapter(nextChapter, startPage: 0)
        }
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
        
        // Don't update page position when showing chapter transition screen
        // This prevents marking the wrong chapter as completed
        if currentVC is ChapterTransitionViewController {
            return
        }
        
        if let singlePage = currentVC as? TextSinglePageViewController {
            currentPageIndex = singlePage.page.id
        } else if let doublePage = currentVC as? TextDoublePageViewController {
            currentPageIndex = doublePage.leftPage.id
        }
        
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
        // If we're showing a chapter transition, no more pages after
        if viewController is ChapterTransitionViewController {
            return nil
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
            // Show chapter transition page
            return ChapterTransitionViewController(
                direction: .next,
                chapter: nextChapter,
                parentReader: self
            )
        }
        return nil
    }
    
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        // If we're showing a chapter transition, no more pages before
        if viewController is ChapterTransitionViewController {
            return nil
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
            // Show chapter transition page
            return ChapterTransitionViewController(
                direction: .previous,
                chapter: previousChapter,
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

// MARK: - Single Page View Controller
class TextSinglePageViewController: UIViewController {
    
    let page: TextPage
    weak var parentReader: ReaderPagedTextViewController?
    
    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .systemBackground
        tv.font = .systemFont(ofSize: 18)
        // Content padding (matches TextPaginator)
        tv.textContainerInset = UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24)
        return tv
    }()
    
    // Dynamic constraints for safe area
    private var topConstraint: NSLayoutConstraint?
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    
    init(page: TextPage, parentReader: ReaderPagedTextViewController? = nil) {
        self.page = page
        self.parentReader = parentReader
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        view.addSubview(textView)
        
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create constraints that we can update later
        topConstraint = textView.topAnchor.constraint(equalTo: view.topAnchor)
        leadingConstraint = textView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        trailingConstraint = textView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        bottomConstraint = textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([topConstraint!, leadingConstraint!, trailingConstraint!, bottomConstraint!])
        
        // Set the text content
        if page.attributedContent.length > 0 {
            textView.attributedText = page.attributedContent
        } else {
            textView.text = page.markdownContent
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        // Get safe area from parent reader (more reliable than child's safe area)
        let safeArea = parentReader?.view.safeAreaInsets ?? view.safeAreaInsets
        
        topConstraint?.constant = safeArea.top
        leadingConstraint?.constant = safeArea.left
        trailingConstraint?.constant = -safeArea.right
        bottomConstraint?.constant = -safeArea.bottom
        
    }
}

// MARK: - Double Page View Controller
class TextDoublePageViewController: UIViewController {
    
    enum Direction {
        case ltr
        case rtl
    }
    
    let leftPage: TextPage
    let rightPage: TextPage
    let direction: Direction
    weak var parentReader: ReaderPagedTextViewController?
    
    private lazy var stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = 1
        return sv
    }()
    
    private lazy var leftTextView: UITextView = createTextView()
    private lazy var rightTextView: UITextView = createTextView()
    private lazy var dividerView: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        return v
    }()
    
    // Dynamic constraints for safe area
    private var topConstraint: NSLayoutConstraint?
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    
    init(leftPage: TextPage, rightPage: TextPage, direction: Direction, parentReader: ReaderPagedTextViewController? = nil) {
        self.leftPage = leftPage
        self.rightPage = rightPage
        self.direction = direction
        self.parentReader = parentReader
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        view.addSubview(dividerView)
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        if direction == .rtl {
            stackView.addArrangedSubview(rightTextView)
            stackView.addArrangedSubview(leftTextView)
            rightTextView.attributedText = rightPage.attributedContent
            leftTextView.attributedText = leftPage.attributedContent
        } else {
            stackView.addArrangedSubview(leftTextView)
            stackView.addArrangedSubview(rightTextView)
            leftTextView.attributedText = leftPage.attributedContent
            rightTextView.attributedText = rightPage.attributedContent
        }
        
        // Create dynamic constraints
        topConstraint = stackView.topAnchor.constraint(equalTo: view.topAnchor)
        leadingConstraint = stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        trailingConstraint = stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        bottomConstraint = stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            topConstraint!, leadingConstraint!, trailingConstraint!, bottomConstraint!,
            dividerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dividerView.topAnchor.constraint(equalTo: stackView.topAnchor, constant: 20),
            dividerView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: -20),
            dividerView.widthAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let safeArea = parentReader?.view.safeAreaInsets ?? view.safeAreaInsets
        
        topConstraint?.constant = safeArea.top
        leadingConstraint?.constant = safeArea.left
        trailingConstraint?.constant = -safeArea.right
        bottomConstraint?.constant = -safeArea.bottom
        
    }
    
    private func createTextView() -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .systemBackground
        // Must match TextPaginator's padding: horizontalPadding=24, verticalPadding=32
        tv.textContainerInset = UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24)
        return tv
    }
}


// MARK: - Chapter Transition View Controller
class ChapterTransitionViewController: UIViewController {
    
    enum Direction {
        case next
        case previous
    }
    
    let direction: Direction
    let chapter: AidokuRunner.Chapter?
    weak var parentReader: ReaderPagedTextViewController?
    
    private lazy var stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 16
        return sv
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private lazy var chapterLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        return label
    }()
    
    init(direction: Direction, chapter: AidokuRunner.Chapter?, parentReader: ReaderPagedTextViewController?) {
        self.direction = direction
        self.chapter = chapter
        self.parentReader = parentReader
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
        
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(chapterLabel)
        stackView.addArrangedSubview(instructionLabel)
        
        if let chapter {
            titleLabel.text = direction == .next 
                ? NSLocalizedString("NEXT_CHAPTER", value: "Next Chapter", comment: "")
                : NSLocalizedString("PREVIOUS_CHAPTER", value: "Previous Chapter", comment: "")
            
            if let chapterNum = chapter.chapterNumber {
                chapterLabel.text = String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
            } else {
                chapterLabel.text = chapter.title ?? ""
            }
            
            instructionLabel.text = direction == .next
                ? NSLocalizedString("SWIPE_TO_CONTINUE", value: "Swipe to continue", comment: "")
                : NSLocalizedString("SWIPE_TO_GO_BACK", value: "Swipe to go back", comment: "")
        } else {
            titleLabel.text = direction == .next
                ? NSLocalizedString("NO_NEXT_CHAPTER", value: "No Next Chapter", comment: "")
                : NSLocalizedString("NO_PREVIOUS_CHAPTER", value: "No Previous Chapter", comment: "")
            chapterLabel.text = direction == .next
                ? NSLocalizedString("END_OF_MANGA", value: "You've reached the end", comment: "")
                : NSLocalizedString("START_OF_MANGA", value: "This is the first chapter", comment: "")
            instructionLabel.isHidden = true
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Load the chapter when this view appears (user swiped to it)
        if let chapter {
            if direction == .next {
                parentReader?.loadNextChapter()
            } else {
                parentReader?.loadPreviousChapter()
            }
        }
    }
}
