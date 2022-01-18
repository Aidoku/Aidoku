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
        return self ? 1 : 0
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
    var pages: [Page] = []
    var preloadedPages: [Page] = []
    
    var imagesToPreload = 6
    
    var hasNextChapter = false
    var hasPreviousChapter = false
    
    var currentIndex: Int {
        Int(floor((self.scrollView.contentSize.width - scrollView.contentOffset.x) / self.scrollView.bounds.width) - CGFloat(hasPreviousChapter.intValue + 2))
    }
    
    var statusBarHidden = false
    
    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }
    
    init(manga: Manga?, chapter: Chapter, chapterList: [Chapter]) {
        self.manga = manga
        self.chapter = chapter
        self.startPage = 0
        self.chapterList = chapterList
        self.scrollView = UIScrollView()
        self.savedStandardAppearance = UINavigationBar.appearance().standardAppearance
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        modalPresentationCapturesStatusBarAppearance = true
        
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
            ),
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
        
        savedCompactAppearance = UINavigationBar.appearance().compactAppearance
        savedScrollEdgeAppearance = UINavigationBar.appearance().scrollEdgeAppearance
        
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        
//        self.navigationController?.isToolbarHidden = false
//        self.toolbarItems = [ UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil) ]
        
        view.backgroundColor = .systemBackground
        view.isUserInteractionEnabled = true
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(toggleBarVisibility))
        singleTap.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTap)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: nil)
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        
        singleTap.require(toFail: doubleTap)
        
        scrollView.frame = view.bounds
        scrollView.isPagingEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        
        view.addSubview(scrollView)
    
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.center = scrollView.center
        activityIndicator.startAnimating()
        items.append(activityIndicator)
        scrollView.addSubview(activityIndicator)
        
        Task {
            await loadChapter()
            self.scrollTo(page: startPage)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        UINavigationBar.appearance().prefersLargeTitles = true
        
        UINavigationBar.appearance().standardAppearance = savedStandardAppearance
        UINavigationBar.appearance().compactAppearance = savedCompactAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = savedScrollEdgeAppearance
    }
    
    func clearPages() {
        for view in self.items {
            view.removeFromSuperview()
        }
        self.items = []
    }
    
    func preload(chapter: Chapter) async {
        guard let manga = manga else { return }
        preloadedPages = (try? await SourceManager.shared.source(for: manga.provider)?.getPageList(chapter: chapter)) ?? []
    }
    
    func preloadImages(for range: Range<Int>) {
        guard pages.count > 0 else { return }
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
            if i < 0 {
                continue
            }
            let processor = DownsamplingImageProcessor(size: items[i].bounds.size)
            (items[i + 1 + hasPreviousChapter.intValue].subviews.last as? UIImageView)?.kf.setImage(
                with: URL(string: urls[i]),
                options: [
                    .processor(processor),
                    .scaleFactor(UIScreen.main.scale),
                    .transition(.fade(0.3))
                ]
            )
        }
    }
    
    func loadChapter() async {
        guard let manga = manga else { return }
        
        if chapterList.isEmpty {
            chapterList = (try? await SourceManager.shared.source(for: manga.provider)?.getChapterList(manga: manga)) ?? []
        }
        
        DataManager.shared.addReadHistory(manga: manga, chapter: chapter)
        startPage = DataManager.shared.currentPage(manga: manga, chapterId: chapter.id)
        
        DispatchQueue.main.async {
            self.navigationItem.setTitle(upper: self.chapter.volumeNum != nil ? "Volume \(self.chapter.volumeNum ?? 0)" : nil, lower: String(format: "Chapter %g", self.chapter.chapterNum))
        }
        
        if !preloadedPages.isEmpty {
            pages = preloadedPages
            preloadedPages = []
        } else {
            pages = (try? await SourceManager.shared.source(for: manga.provider)?.getPageList(chapter: chapter)) ?? []
        }
        
        if let chapterIndex = chapterList.firstIndex(of: chapter) {
            hasPreviousChapter = chapterIndex != 0
            hasNextChapter = chapterIndex != chapterList.count - 1
        } else {
            hasPreviousChapter = false
            hasNextChapter = false
        }
        
        DispatchQueue.main.async {
            self.clearPages()
            
            for _ in self.pages {
                let zoomableView = ZoomableScrollView(frame: self.view.bounds)
                let activityIndicator = UIActivityIndicatorView(style: .medium)
                activityIndicator.center = zoomableView.center
                activityIndicator.startAnimating()
                zoomableView.addSubview(activityIndicator)
                
                let imageView = UIImageView(frame: zoomableView.bounds)
                imageView.contentMode = .scaleAspectFit
                
                zoomableView.addSubview(imageView)
                self.items.append(zoomableView)
            }
            
            let firstPage = UIView()
            firstPage.backgroundColor = .white
            self.items.insert(firstPage, at: 0)
            
            let finalPage = UIView()
            finalPage.backgroundColor = .white
            self.items.append(finalPage)
            
            if self.hasPreviousChapter {
                let previousChapterPage = UIImageView()
                previousChapterPage.kf.indicatorType = .activity
                previousChapterPage.contentMode = .scaleAspectFit
                self.items.insert(previousChapterPage, at: 0)
            }
            
            if self.hasNextChapter {
                let nextChapterPage = UIImageView()
                nextChapterPage.kf.indicatorType = .activity
                nextChapterPage.contentMode = .scaleAspectFit
                self.items.append(nextChapterPage)
            }
            
            for (i, view) in self.items.reversed().enumerated() {
                view.frame = CGRect(x: CGFloat(i) * self.scrollView.bounds.width, y: 0, width: self.scrollView.bounds.width, height: self.scrollView.bounds.height)
                self.scrollView.addSubview(view)
            }
            self.scrollView.contentSize = CGSize(
                width: CGFloat(self.items.count) * self.scrollView.bounds.width,
                height: self.scrollView.bounds.height
            )
        }
    }
    
    func scrollTo(page: Int, animated: Bool = false) {
        self.setImages(for: (page - 2)..<(page + 3))
        self.scrollView.setContentOffset(
            CGPoint(
                x: self.scrollView.contentSize.width - self.scrollView.bounds.size.width * CGFloat(page + hasPreviousChapter.intValue + 2),
                y: 0
            ),
            animated: false
        )
    }
    
    @objc func close() {
        if let manga = manga {
            var index = currentIndex
            if index < 0 {
                index = 0
            } else if index >= items.count - (hasNextChapter.intValue + hasPreviousChapter.intValue + 2) {
                index = items.count - (hasNextChapter.intValue + hasPreviousChapter.intValue + 2) - 1
            }
            DataManager.shared.setCurrentPage(manga: manga, chapter: chapter, page: index)
        }
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
                NotificationCenter.default.post(name: Notification.Name("updateStatusBar"), object: nil)
                self.setNeedsStatusBarAppearanceUpdate()
            } completion: { _ in
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
                NotificationCenter.default.post(name: Notification.Name("updateStatusBar"), object: nil)
                self.setNeedsStatusBarAppearanceUpdate()
            } completion: { _ in
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    navigationController.navigationBar.alpha = 0
                    navigationController.toolbar.alpha = 0
                    self.view.backgroundColor = .black
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
            chapter = chapterList[chapterIndex - 1]
            Task {
                await loadChapter()
                self.scrollTo(page: items.count - (hasNextChapter.intValue + hasPreviousChapter.intValue + 2) - 1)
            }
        } else if hasPreviousChapter && currentIndex == -1 { // Preload previous chapter
            Task {
                let previousChapter = chapterList[chapterIndex - 1]
                await preload(chapter: previousChapter)
                
                let processor = DownsamplingImageProcessor(size: scrollView.bounds.size)
                (self.items.first as? UIImageView)?.kf.setImage(
                    with: URL(string: preloadedPages.last?.imageURL ?? ""),
                    options: [
                        .processor(processor),
                        .scaleFactor(UIScreen.main.scale),
                        .transition(.fade(0.3))
                    ]
                )
            }
        } else if hasNextChapter && currentIndex == items.count - (hasPreviousChapter.intValue + 3) { // Preload next chapter
            Task {
                let nextChapter = chapterList[chapterIndex + 1]
                await preload(chapter: nextChapter)
                
                let processor = DownsamplingImageProcessor(size: scrollView.bounds.size)
                (self.items.last as? UIImageView)?.kf.setImage(
                    with: URL(string: preloadedPages.first?.imageURL ?? ""),
                    options: [
                        .processor(processor),
                        .scaleFactor(UIScreen.main.scale),
                        .transition(.fade(0.3))
                    ]
                )
            }
        } else if hasNextChapter && currentIndex == items.count - (hasPreviousChapter.intValue + 2) { // Next chapter
            chapter = chapterList[chapterIndex + 1]
            Task {
                await loadChapter()
                self.scrollTo(page: 0)
            }
        } else {
            if let manga = manga {
                DataManager.shared.setCurrentPage(manga: manga, chapter: chapter, page: currentIndex)
            }
            self.preloadImages(for: currentIndex..<(currentIndex + imagesToPreload))
            self.setImages(for: (currentIndex - 1)..<(currentIndex + 4))
        }
    }
}

// MARK: - Popover Delegate
extension ReaderViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}
