//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/22/21.
//

import UIKit
import Kingfisher

extension Bool {
    var intValue: Int {
        self ? 1 : 0
    }
}

extension UINavigationItem {
    func setTitle(upper: String?, lower: String) {
        if let upper = upper {
            let upperLabel = UILabel()
            upperLabel.text = upper
            upperLabel.font = UIFont.systemFont(ofSize: 11)
            upperLabel.textColor = .secondaryLabel

            let lowerLabel = UILabel()
            lowerLabel.text = lower
            lowerLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            lowerLabel.textAlignment = .center

            let stackView = UIStackView(arrangedSubviews: [upperLabel, lowerLabel])
            stackView.distribution = .equalCentering
            stackView.axis = .vertical
            stackView.alignment = .center

            let width = max(upperLabel.frame.size.width, lowerLabel.frame.size.width)
            stackView.frame = CGRect(x: 0, y: 0, width: width, height: 35)

            upperLabel.sizeToFit()
            lowerLabel.sizeToFit()

            self.titleView = stackView
        } else {
            self.titleView = nil
            self.title = lower
        }
    }
}

extension UIToolbar {
    var contentView: UIView? {
        subviews.first { view in
            let viewDescription = String(describing: type(of: view))
            return viewDescription.contains("ContentView")
        }
    }

    var stackView: UIView? {
        contentView?.subviews.first { view -> Bool in
            let viewDescription = String(describing: type(of: view))
            return viewDescription.contains("ButtonBarStackView")
        }
    }

   func fitContentViewToToolbar() {
        guard let stackView = stackView, let contentView = contentView else { return }
        stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
        stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
        stackView.widthAnchor.constraint(equalTo: contentView.widthAnchor).isActive = true
    }
}

class ReaderViewController: UIViewController {

    let manga: Manga?
    var chapter: Chapter
    var startPage: Int
    var chapterList: [Chapter]

    var chapterIndex: Int {
        chapterList.firstIndex(of: chapter) ?? 0
    }

    var savedStandardAppearance: UINavigationBarAppearance
    var savedCompactAppearance: UINavigationBarAppearance?
    var savedScrollEdgeAppearance: UINavigationBarAppearance?

    var scrollView: UIScrollView

    var items: [UIView] = []
    var leadingConstraints: [NSLayoutConstraint] = []
    var pages: [Page] = []
    var preloadedPages: [Page] = []

    var imagesToPreload = 6

    var hasNextChapter = false
    var hasPreviousChapter = false

    lazy var singleTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleBarVisibility))
        tap.numberOfTapsRequired = 1

        let doubleTap = UITapGestureRecognizer(target: self, action: nil)
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        tap.require(toFail: doubleTap)

        return tap
    }()

    let transitionView = UIView()

    let toolbarView = UIView()
    let sliderView = ReaderSliderView()
    let currentPageLabel = UILabel()
    let pagesLeftLabel = UILabel()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))

    var toolbarSliderWidthConstraint: NSLayoutConstraint?

    var currentIndex: Int {
        let offset = floor(
            (self.scrollView.contentSize.width - scrollView.contentOffset.x) / self.scrollView.bounds.width
        ) - CGFloat(hasPreviousChapter.intValue + 2)
        guard !offset.isNaN && !offset.isInfinite else { return 0 }
        return Int(offset)
    }

    var statusBarHidden = false

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        UIStatusBarAnimation.fade
    }

    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        statusBarHidden
    }

    init(manga: Manga?, chapter: Chapter, chapterList: [Chapter]) {
        self.manga = manga
        self.chapter = chapter
        self.startPage = 0
        self.chapterList = chapterList
        self.scrollView = UIScrollView(frame: UIScreen.main.bounds)
        self.savedStandardAppearance = UINavigationBar.appearance().standardAppearance
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        modalPresentationCapturesStatusBarAppearance = true

        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(close)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "list.bullet"),
                style: .plain,
                target: self,
                action: #selector(openChapterSelectionPopover(_:))
            )
        ]

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis"),
                style: .plain,
                target: nil,
                action: nil
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "textformat.size"),
                style: .plain,
                target: nil,
                action: nil
            )
        ]
        navigationItem.rightBarButtonItems?.forEach {
            $0.isEnabled = false
        }

        UINavigationBar.appearance().prefersLargeTitles = false

        // Fixes navbar being clear
        savedCompactAppearance = UINavigationBar.appearance().compactAppearance
        savedScrollEdgeAppearance = UINavigationBar.appearance().scrollEdgeAppearance

        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance

        currentPageLabel.font = .systemFont(ofSize: 10)
        currentPageLabel.textAlignment = .center
        currentPageLabel.sizeToFit()
        currentPageLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(currentPageLabel)

        pagesLeftLabel.font = .systemFont(ofSize: 10)
        pagesLeftLabel.textColor = .secondaryLabel
        pagesLeftLabel.textAlignment = .right
        pagesLeftLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(pagesLeftLabel)

        sliderView.addTarget(self, action: #selector(sliderMoved(_:)), for: .valueChanged)
        sliderView.addTarget(self, action: #selector(sliderDone(_:)), for: .editingDidEnd)
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(sliderView)

        toolbarView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 24)
        toolbarView.translatesAutoresizingMaskIntoConstraints = false

        let toolbarSlider = UIBarButtonItem(customView: toolbarView)
        toolbarSliderWidthConstraint = toolbarSlider.customView?.widthAnchor.constraint(equalToConstant: view.bounds.width)
        toolbarSlider.customView?.heightAnchor.constraint(equalToConstant: 30).isActive = true

        navigationController?.isToolbarHidden = false
        toolbarItems = [toolbarSlider]

        navigationController?.toolbar.fitContentViewToToolbar()

        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Shows when orientation changing in order to cover up the jerky scrolling happening
        transitionView.isHidden = true
        transitionView.backgroundColor = .black
        transitionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transitionView)

        // TODO: Maybe make this an indefinite progress view
        progressView.center = scrollView.center
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = scrollView.tintColor
        items.append(progressView)
        scrollView.addSubview(progressView)

        view.addGestureRecognizer(singleTap)

        activateConstraints()

        Task {
            await loadChapter()
            self.scrollTo(page: startPage)
        }
    }

    func activateConstraints() {
        currentPageLabel.centerXAnchor.constraint(equalTo: toolbarView.centerXAnchor).isActive = true
        currentPageLabel.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor).isActive = true

        pagesLeftLabel.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -16).isActive = true
        pagesLeftLabel.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor).isActive = true

        sliderView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        sliderView.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 12).isActive = true
        sliderView.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -12).isActive = true

        toolbarSliderWidthConstraint?.isActive = true

        scrollView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        scrollView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        scrollView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

        transitionView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        transitionView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let currentPage = currentIndex

        transitionView.isHidden = false

        toolbarSliderWidthConstraint?.constant = size.width

        scrollView.contentSize = CGSize(
            width: CGFloat(self.items.count) * size.width,
            height: size.height
        )

        scrollView.setContentOffset(
            CGPoint(
                x: scrollView.contentSize.width - size.width * CGFloat(currentPage + hasPreviousChapter.intValue + 2),
                y: 0
            ),
            animated: false
        )

        for (i, item) in items.reversed().enumerated() {
            if let item = item as? ReaderPageView {
                item.zoomableView.frame = CGRect(origin: .zero, size: size)
                item.imageView.frame = item.zoomableView.bounds
                item.updateZoomBounds()
            }
            leadingConstraints[i].constant = CGFloat(i) * size.width
        }

        coordinator.animate(alongsideTransition: nil) { _ in
            self.transitionView.isHidden = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        UINavigationBar.appearance().prefersLargeTitles = true

        UINavigationBar.appearance().standardAppearance = savedStandardAppearance
        UINavigationBar.appearance().compactAppearance = savedCompactAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = savedScrollEdgeAppearance
    }
}

extension ReaderViewController {

    @objc func sliderMoved(_ sender: ReaderSliderView) {
        let page = Int(round(sender.currentValue * CGFloat(pages.count - 1)))
        currentPageLabel.text = "\(page + 1) of \(pages.count)"
    }

    @objc func sliderDone(_ sender: ReaderSliderView) {
        let page = Int(round(sender.currentValue * CGFloat(pages.count - 1)))
        scrollTo(page: page)
    }

    func updateLabels() {
        var currentPage = currentIndex + 1
        let pageCount = pages.count
        if currentPage > pageCount {
            currentPage = pageCount
        } else if currentPage < 1 {
            currentPage = 1
        }
        let pagesLeft = pageCount - currentPage
        currentPageLabel.text = "\(currentPage) of \(pageCount)"
        if pagesLeft < 1 {
            pagesLeftLabel.text = nil
        } else {
            pagesLeftLabel.text = "\(pagesLeft) page\(pagesLeft == 1 ? "" : "s") left"
        }
        sliderView.currentValue = CGFloat(currentPage - 1) / CGFloat(pageCount - 1)
    }

    func clearPageViews() {
        for view in items {
            view.removeFromSuperview()
        }
        items = []
    }

    func preload(chapter: Chapter) async {
        preloadedPages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
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

    func setImages(for range: Range<Int>) {
        let urls = pages.map { $0.imageURL ?? "" }
        for i in range {
            guard i < urls.count else { return }
            if i < -1 {
                continue
            }

            Task {
                await (items[i + 1 + hasPreviousChapter.intValue] as? ReaderPageView)?.setPageImage(url: urls[i])
            }
        }
    }

    @MainActor
    func loadChapter() async {
        guard let manga = manga else { return }

        if chapterList.isEmpty {
            chapterList = await DataManager.shared.getChapters(for: manga, fromSource: true)
        }

        DataManager.shared.addHistory(for: self.chapter)
        self.startPage = DataManager.shared.currentPage(for: self.chapter)

        self.navigationItem.setTitle(
            upper: self.chapter.volumeNum != nil ? String(format: "Volume %g", self.chapter.volumeNum ?? 0) : nil,
            lower: String(format: "Chapter %g", self.chapter.chapterNum ?? 0)
        )

        if !preloadedPages.isEmpty {
            pages = preloadedPages
            preloadedPages = []
        } else {
            pages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
        }

        if let chapterIndex = chapterList.firstIndex(of: chapter) {
            hasPreviousChapter = chapterIndex != chapterList.count - 1
            hasNextChapter = chapterIndex != 0
        } else {
            hasPreviousChapter = false
            hasNextChapter = false
        }

        self.clearPageViews()

        for _ in self.pages {
            let pageView = ReaderPageView()
            pageView.translatesAutoresizingMaskIntoConstraints = false

            // Append context menu interaction for each page in the chapter
            let interaction = UIContextMenuInteraction(delegate: self)
            pageView.imageView.addInteraction(interaction)

            self.items.append(pageView)
        }

        let firstPage = ReaderInfoPageView(type: .previous, currentChapter: self.chapter)
        if self.hasPreviousChapter {
            firstPage.previousChapter = self.chapterList[self.chapterIndex + 1]
        }
        firstPage.translatesAutoresizingMaskIntoConstraints = false
        self.items.insert(firstPage, at: 0)

        let finalPage = ReaderInfoPageView(type: .next, currentChapter: self.chapter)
        if self.hasNextChapter {
            finalPage.nextChapter = self.chapterList[self.chapterIndex - 1]
        }
        finalPage.translatesAutoresizingMaskIntoConstraints = false
        self.items.append(finalPage)

        if self.hasPreviousChapter {
            let previousChapterPage = ReaderPageView()
            previousChapterPage.translatesAutoresizingMaskIntoConstraints = false
            self.items.insert(previousChapterPage, at: 0)
        }

        if self.hasNextChapter {
            let nextChapterPage = ReaderPageView()
            nextChapterPage.translatesAutoresizingMaskIntoConstraints = false
            self.items.append(nextChapterPage)
        }

        self.leadingConstraints = []
        for (i, view) in self.items.reversed().enumerated() {
            self.scrollView.addSubview(view)

            self.leadingConstraints.append(
                view.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor,
                                              constant: CGFloat(i) * self.scrollView.bounds.width)
            )
            self.leadingConstraints[i].isActive = true
            view.topAnchor.constraint(equalTo: self.scrollView.topAnchor).isActive = true
            view.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor).isActive = true
            view.heightAnchor.constraint(equalTo: self.scrollView.heightAnchor).isActive = true
        }
        self.scrollView.contentSize = CGSize(
            width: CGFloat(self.items.count) * self.scrollView.bounds.width,
            height: self.scrollView.bounds.height
        )
    }

    func scrollTo(page: Int, animated: Bool = false) {
        guard page >= 0, page < pages.count else { return }
        self.setImages(for: (page - 2)..<(page + 3))

        let multiplier = CGFloat(page + hasPreviousChapter.intValue + 2)
        self.scrollView.setContentOffset(
            CGPoint(
                x: self.scrollView.contentSize.width - self.scrollView.bounds.size.width * multiplier,
                y: 0
            ),
            animated: false
        )
        updateLabels()
    }

    @objc func close() {
        var index = currentIndex
        if index < 0 {
            index = 0
        } else if index >= items.count - (hasNextChapter.intValue + hasPreviousChapter.intValue + 2) {
            index = items.count - (hasNextChapter.intValue + hasPreviousChapter.intValue + 2) - 1
        }
        DataManager.shared.setCurrentPage(index, for: chapter)
        self.dismiss(animated: true)
    }

    @objc func openChapterSelectionPopover(_ sender: UIBarButtonItem) {
        let vc = ChapterListPopoverContentController(chapterList: chapterList, selectedIndex: chapterList.firstIndex(of: chapter) ?? 0)
        vc.delegate = self
        vc.preferredContentSize = CGSize(width: 250, height: 200)
        vc.modalPresentationStyle = .popover
        vc.presentationController?.delegate = self
        vc.popoverPresentationController?.permittedArrowDirections = .up
        vc.popoverPresentationController?.barButtonItem = sender
        present(vc, animated: true)
    }

    @objc func toggleBarVisibility() {
        if let navigationController = navigationController {
            if navigationController.navigationBar.alpha > 0 {
                hideBars()
            } else {
                showBars()
            }
        }
    }

    func showBars() {
        if let navigationController = navigationController {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.statusBarHidden = false
                self.setNeedsStatusBarAppearanceUpdate()
                self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            } completion: { _ in
                if navigationController.toolbar.isHidden {
                    navigationController.toolbar.alpha = 0
                    navigationController.toolbar.isHidden = false
                }
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    navigationController.navigationBar.alpha = 1
                    navigationController.toolbar.alpha = 1
                    self.view.backgroundColor = .systemBackground
                }
            }
        }
    }

    func hideBars() {
        if let navigationController = navigationController {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.statusBarHidden = true
                self.setNeedsStatusBarAppearanceUpdate()
                self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            } completion: { _ in
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    navigationController.navigationBar.alpha = 0
                    navigationController.toolbar.alpha = 0
                    self.view.backgroundColor = .black
                } completion: { _ in
                    navigationController.toolbar.isHidden = true
                }
            }
        }
    }
}

// MARK: - Chapter List Delegate
extension ReaderViewController: ChapterListPopoverDelegate {
    func chapterSelected(_ chapter: Chapter) {
        self.chapter = chapter
        Task {
            await loadChapter()
            self.scrollTo(page: startPage)
        }
    }
}

// MARK: - Scroll View Delegate
extension ReaderViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if hasPreviousChapter && currentIndex == -2 { // Previous chapter
            chapter = chapterList[chapterIndex + 1]
            Task {
                await loadChapter()
                self.scrollTo(page: items.count - (hasNextChapter.intValue + hasPreviousChapter.intValue + 2) - 1)
            }
        } else if hasPreviousChapter && currentIndex == -1 { // Preload previous chapter
            Task {
                let previousChapter = chapterList[chapterIndex + 1]
                await preload(chapter: previousChapter)
                await (self.items.first as? ReaderPageView)?.setPageImage(url: preloadedPages.last?.imageURL ?? "")
            }
        } else if hasNextChapter && currentIndex == items.count - (hasPreviousChapter.intValue + 3) { // Preload next chapter
            DataManager.shared.setCompleted(chapter: chapter)
            Task {
                let nextChapter = chapterList[chapterIndex - 1]
                await preload(chapter: nextChapter)
                await (self.items.last as? ReaderPageView)?.setPageImage(url: preloadedPages.first?.imageURL ?? "")
            }
        } else if hasNextChapter && currentIndex == items.count - (hasPreviousChapter.intValue + 2) { // Next chapter
            chapter = chapterList[chapterIndex - 1]
            Task {
                await loadChapter()
                self.scrollTo(page: 0)
            }
        } else {
            DataManager.shared.setCurrentPage(currentIndex, for: chapter)
            self.preloadImages(for: currentIndex..<(currentIndex + imagesToPreload))
            self.setImages(for: (currentIndex - 1)..<(currentIndex + 4))
        }
        updateLabels()
    }
}

// MARK: - Popover Delegate
extension ReaderViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}

// MARK: - Context menu Delegate
extension ReaderViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            let saveToPhotosAction = UIAction(title: "Save to Photos", image: UIImage(systemName: "square.and.arrow.down")) { [self] _ in
                if let currentPage: ReaderPageView = items[currentIndex + 1 + hasPreviousChapter.intValue] as? ReaderPageView {
                    if let image = currentPage.imageView.image {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                }
            }

            return UIMenu(title: "", children: [saveToPhotosAction])
        })
    }
}
