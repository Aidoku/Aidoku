//
//  ReaderScrollPageManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/15/22.
//

import UIKit
import Kingfisher
import Nuke

class ReaderScrollPageManager: NSObject, ReaderPageManager {

    weak var delegate: ReaderPageManagerDelegate?

    var chapter: Chapter? {
        didSet {
            getChapterInfo()
        }
    }
    var readingMode: MangaViewer?
    var pages: [Page] = []

    var infiniteScroll = false

    var previousChapter: Chapter?
    var previousPages: [Page] = []
    var nextChapter: Chapter?
    var nextPages: [Page] = []

    var targetNextChapter: Chapter?

    var preloadedChapter: Chapter?
    var preloadedPages: [Page] = []

    var collectionView: UICollectionView?

    var sizeCache: [String: CGSize] = [:]
    var dataCache: [String: Bool] = [:]
    var lastSize: CGSize?

    var chapterList: [Chapter] = []
    var chapterIndex: Int {
        guard let chapter = chapter else { return 0 }
        return chapterList.firstIndex(of: chapter) ?? 0
    }

    var hasNextChapter = false
    var hasPreviousChapter = false

    var pagesToPreload: Int = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")

    var targetPage: Int?
    var shouldMoveToTargetPage = true
    var transitioningChapter = false

    var previousPageIndex = 0

    var currentIndex: Int {
        guard let collectionView = collectionView else { return 0 }
        let offset = CGPoint(x: 0, y: collectionView.contentOffset.y + 100)
        if let path = collectionView.indexPathForItem(at: offset) {
            if path.section == 1 {
                return path.item
            } else {
                return path.item + 1
            }
        } else {
            return 0
        }
    }

    var topCellIndex: Int {
        guard let collectionView = collectionView else { return 0 }
        if collectionView.contentOffset.y < 100 {
            return 0
        } else if collectionView.contentOffset.y + collectionView.bounds.height > collectionView.contentSize.height - 100 {
            return pages.count
        } else if let topPath = collectionView.indexPathForItem(at: collectionView.contentOffset) {
            switch topPath.section {
            case 1: return topPath.item
            case 2: return pages.count + 1
            default: return 0
            }
        } else {
            return 0
        }
    }

    var bottomCellIndex: Int {
        guard let collectionView = collectionView else { return 0 }
        if collectionView.contentOffset.y < 100 {
            return 1
        } else if collectionView.contentOffset.y + collectionView.bounds.height > collectionView.contentSize.height - 100 {
            return pages.count + 1
        } else if let bottomPath = collectionView.indexPathForItem(
            at: CGPoint(x: collectionView.contentOffset.x,
                        y: collectionView.contentOffset.y + collectionView.bounds.size.height)
        ) {
            switch bottomPath.section {
            case 1: return bottomPath.item
            case 2: return pages.count + 1
            default: return 0
            }
        } else {
            return 0
        }
    }

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("Reader.verticalInfiniteScroll"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.infiniteScroll = UserDefaults.standard.bool(forKey: "Reader.verticalInfiniteScroll")
            if !self.infiniteScroll {
                self.previousPages = []
                self.previousChapter = nil
                self.nextPages = []
                self.nextChapter = nil
            }
            Task { @MainActor in
                self.collectionView?.reloadData()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: Notification.Name("Reader.pagesToPreload"), object: nil, queue: nil) { _ in
            self.pagesToPreload = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
        })
    }

    func attach(toParent parent: UIViewController) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets.zero

        layout.scrollDirection = .vertical

        collectionView = UICollectionView(frame: parent.view.bounds, collectionViewLayout: layout)
        guard let collectionView = collectionView else { return }
        collectionView.backgroundColor = .clear
        collectionView.register(ReaderPageCollectionViewCell.self, forCellWithReuseIdentifier: "ReaderPageCollectionViewCell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(collectionView)

        collectionView.topAnchor.constraint(equalTo: parent.view.topAnchor).isActive = true
        collectionView.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor).isActive = true
        collectionView.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor).isActive = true
        collectionView.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor).isActive = true

        infiniteScroll = UserDefaults.standard.bool(forKey: "Reader.verticalInfiniteScroll")
    }

    func remove() {
        pages.removeAll()
        sizeCache.removeAll()
        dataCache.removeAll()
        collectionView?.removeFromSuperview()
        collectionView = nil
    }

    func setChapter(chapter: Chapter, startPage: Int) {
        guard collectionView != nil else { return }

        let startPage = startPage <= 0 ? 1 : startPage

        self.chapter = chapter
        targetPage = startPage - 1

        if transitioningChapter {
            transitioningChapter = false
            shouldMoveToTargetPage = false
        } else {
            shouldMoveToTargetPage = true
        }

        Task { @MainActor in
            await loadPages()
            setImages(for: 0..<startPage)
            if let collectionView = collectionView {
                collectionView.reloadData()
                // Move to the first page immediately
                if targetPage == 0 && shouldMoveToTargetPage {
                    shouldMoveToTargetPage = false
                    move(toPage: 0)
                }
            }
        }
    }

    func move(toPage page: Int, animated: Bool = false, reversed: Bool = false) {
        guard let collectionView = collectionView else { return }
        collectionView.reloadData()
        guard collectionView.numberOfSections > 1 && collectionView.numberOfItems(inSection: 1) >= page + 1 else { return }
        collectionView.scrollToItem(at: IndexPath(item: page + 1, section: 1), at: .top, animated: animated)
        delegate?.didMove(toPage: page)
    }

    func nextPage() {
        guard let collectionView = collectionView else { return }
        let insets = collectionView.safeAreaInsets.top + collectionView.safeAreaInsets.bottom + 50
        var offset = collectionView.contentOffset.y + (UIScreen.main.bounds.height - insets)
        if offset > collectionView.contentSize.height - collectionView.bounds.height {
            offset = collectionView.contentSize.height - collectionView.bounds.height
        }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: offset),
            animated: true
        )
        scrollViewDidEndDragging(collectionView, willDecelerate: false)
    }

    func previousPage() {
        guard let collectionView = collectionView else { return }
        let insets = collectionView.safeAreaInsets.top + collectionView.safeAreaInsets.bottom + 50
        var offset = collectionView.contentOffset.y - (UIScreen.main.bounds.height - insets)
        if offset < 0 {
            offset = 0
        }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: offset),
            animated: true
        )
        scrollViewDidEndDragging(collectionView, willDecelerate: false)
    }

    func willTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: nil) { _ in
            guard let collectionView = self.collectionView else { return }
            for (key, value) in self.sizeCache {
                let newValue = CGSize(
                    width: collectionView.bounds.size.width,
                    height: value.height * (collectionView.bounds.size.width / value.width)
                )
                self.sizeCache[key] = newValue
            }
            self.collectionView?.collectionViewLayout.invalidateLayout()
        }
    }

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
        guard let chapter = chapter else { return }
        if preloadedChapter == chapter && !preloadedPages.isEmpty {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
        } else {
            pages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
        }
        sizeCache = [:]
        dataCache = [:]
        delegate?.pagesLoaded()

        if chapterList.isEmpty {
            if let chapters = delegate?.chapterList, !chapters.isEmpty {
                chapterList = chapters
            } else {
                chapterList = await DataManager.shared.getChapters(from: chapter.sourceId, for: chapter.mangaId)
            }
        }
        getChapterInfo()
    }

    func getChapterInfo() {
        if let chapter = chapter, let chapterIndex = chapterList.firstIndex(of: chapter) {
            targetNextChapter = getNextChapter()
            hasPreviousChapter = chapterIndex != chapterList.count - 1
            hasNextChapter = targetNextChapter != nil
        } else {
            hasPreviousChapter = false
            hasNextChapter = false
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

    func setImages(for range: Range<Int>) {
        guard let collectionView = collectionView else { return }
        for i in range {
            guard i < pages.count else { break }
            if i < 0 {
                continue
            }
            let path = IndexPath(item: i + 1, section: 1)
            if !(dataCache[pages[i].key] ?? false) {
                // fetching the cell will automatically trigger it to fetch the image
                _ = self.collectionView(collectionView, cellForItemAt: path)
            }
        }
    }

    @MainActor
    func append(chapter: Chapter, toFront: Bool = false) async {
        guard let collectionView = collectionView else { return }

        if toFront {
            guard previousChapter != chapter else { return }

            previousChapter = chapter

            if preloadedChapter == previousChapter {
                previousPages = preloadedPages
                preloadedPages = []
                preloadedChapter = nil
            } else {
                previousPages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
            }

            let bottomOffset = collectionView.contentSize.height - collectionView.contentOffset.y
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            collectionView.performBatchUpdates {
                collectionView.reloadSections([0])
            } completion: { _ in
                collectionView.setContentOffset(
                    CGPoint(x: 0, y: collectionView.contentSize.height - bottomOffset),
                    animated: false
                )
                CATransaction.commit()
            }
        } else {
            guard nextChapter != chapter else { return }

            nextChapter = chapter

            if preloadedChapter == nextChapter {
                nextPages = preloadedPages
                preloadedPages = []
                preloadedChapter = nil
            } else {
                nextPages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
            }

            collectionView.performBatchUpdates {
                collectionView.reloadSections([2])
            }
        }
    }

    func switchToNextChapter() {
        guard let collectionView = collectionView else { return }

        var extraHeight: CGFloat = 0
        if previousChapter != nil {
            extraHeight = previousPages.map { sizeCache[$0.key]?.height ?? 100 }.reduce(0, +)
        }

        previousChapter = chapter
        previousPages = pages
        chapter = nextChapter
        pages = nextPages
        nextChapter = nil
        nextPages = []

        collectionView.setContentOffset(CGPoint(x: 0, y: collectionView.contentOffset.y - 300 - extraHeight), animated: false)
        collectionView.reloadData()

        if let chapter = chapter, delegate?.chapter != chapter {
            transitioningChapter = true
            delegate?.move(toChapter: chapter)
        }
    }

    func switchToPreviousChapter() {
        guard let collectionView = collectionView else { return }

        nextChapter = chapter
        nextPages = pages
        chapter = previousChapter
        pages = previousPages
        previousChapter = nil
        previousPages = []

        collectionView.setContentOffset(CGPoint(x: 0, y: collectionView.contentOffset.y + 300), animated: false)
        collectionView.reloadData()

        if let chapter = chapter, delegate?.chapter != chapter {
            transitioningChapter = true
            delegate?.move(toChapter: chapter)
        }
    }
}

// MARK: - Collection View Delegate
extension ReaderScrollPageManager: UICollectionViewDelegateFlowLayout {

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        var key: String?

        if indexPath.section == 0 {
            if indexPath.item < previousPages.count {
                key = previousPages[indexPath.item].key
            }
        } else if indexPath.section == 2 {
            if indexPath.item < nextPages.count {
                key = nextPages[indexPath.item].key
            }
        } else if indexPath.item == 0 || indexPath.item >= pages.count + 1 {
            return CGSize(width: collectionView.frame.size.width, height: 300)
        } else {
            if indexPath.item - 1 < pages.count {
                key = pages[indexPath.item - 1].key
            }
        }

        if let key = key, let size = sizeCache[key] {
            lastSize = size
            return size
        } else if let size = lastSize {
            return size
        }

        return CGSize(width: collectionView.frame.size.width, height: 100)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let index = currentIndex

        shouldMoveToTargetPage = false

        let newPageIndex = index - 1
        if previousPageIndex != newPageIndex {
            previousPageIndex = newPageIndex
            delegate?.didMove(toPage: newPageIndex)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        calculateIndexes()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            calculateIndexes()
        }
    }

    func calculateIndexes() {
        guard infiniteScroll else { return }

        let topCellIndex = topCellIndex
        let bottomCellIndex = bottomCellIndex

        if topCellIndex >= pages.count + 1 && hasNextChapter && !nextPages.isEmpty { // move to next chapter
            switchToNextChapter()
            return
        } else if topCellIndex <= 0 && hasPreviousChapter { // append previous chapter
            let previousChapter = chapterList[chapterIndex + 1]
            if self.previousChapter != previousChapter {
                Task {
                    await append(chapter: previousChapter, toFront: true)
                }
            }
        }

        if bottomCellIndex == pages.count, let nextChapter = targetNextChapter { // preload next chapter
            Task {
                await preload(chapter: nextChapter)
            }
        } else if bottomCellIndex >= pages.count + 1 && hasNextChapter { // append next chapter
            if nextChapter != targetNextChapter, let nextChapter = targetNextChapter {
                Task {
                    await append(chapter: nextChapter)
                }
            }
        } else if bottomCellIndex <= 0 && hasPreviousChapter && !previousPages.isEmpty { // move to previous chaptrer
            switchToPreviousChapter()
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? ReaderPageCollectionViewCell {
            var page: Page?
            if indexPath.section == 0 {
                if indexPath.item < previousPages.count {
                    page = previousPages[indexPath.item]
                }
            } else if indexPath.section == 2 {
                if indexPath.item < nextPages.count {
                    page = nextPages[indexPath.item]
                }
            } else if indexPath.item == 0 {
                if let chapter = chapter {
                    cell.infoView?.currentChapter = chapter
                }
                cell.infoView?.previousChapter = hasPreviousChapter ? chapterList[chapterIndex + 1] : nil
                cell.infoView?.nextChapter = nil
            } else if indexPath.item >= pages.count + 1 {
                if let chapter = chapter {
                    cell.infoView?.currentChapter = chapter

                    // mark chapter read if next chapter info page is displayed
                    if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
                        DataManager.shared.setCompleted(chapter: chapter, context: DataManager.shared.backgroundContext)
                    }
                }
                cell.infoView?.nextChapter = targetNextChapter
                cell.infoView?.previousChapter = nil
            } else {
                setImages(for: (indexPath.item)..<(indexPath.item + pagesToPreload)) // preload next set pages amount
            }
            if let page = page {
                if dataCache[page.key] ?? false {
                    cell.setPage(cacheKey: page.key)
                } else {
                    cell.setPage(page: page)
                }
            }
        }
    }
}

// MARK: - Collection View Data Source
extension ReaderScrollPageManager: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        3
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        switch section {
        case 0: return previousPages.count
        case 1: return pages.isEmpty ? 0 : pages.count + 2
        case 2: return nextPages.count
        default: return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "ReaderPageCollectionViewCell",
            for: indexPath
        )

        if let chapter = chapter, let cell = cell as? ReaderPageCollectionViewCell {
            cell.sourceId = chapter.sourceId

            if indexPath.section == 0 || indexPath.section == 2 {
                cell.convertToPage()
                cell.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                cell.pageView?.delegate = self
            } else {
                if indexPath.item == 0 {
                    cell.convertToInfo(type: .previous, currentChapter: chapter)
                    if hasPreviousChapter {
                        cell.infoView?.previousChapter = chapterList[chapterIndex + 1]
                        cell.infoView?.nextChapter = nil
                    }
                } else if indexPath.item == pages.count + 1 {
                    cell.convertToInfo(type: .next, currentChapter: chapter)
                    if hasNextChapter {
                        cell.infoView?.nextChapter = targetNextChapter
                        cell.infoView?.previousChapter = nil
                    }
                } else {
                    cell.convertToPage()
                    cell.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                    cell.pageView?.delegate = self
                    if dataCache[pages[indexPath.item - 1].key] ?? false {
                        cell.setPage(cacheKey: pages[indexPath.item - 1].key)
                    } else {
                        cell.setPage(page: pages[indexPath.item - 1])
                    }
                }
            }
        }

        return cell
    }
}

// MARK: - Collection View Prefetching
extension ReaderScrollPageManager: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
//        let urls = indexPaths.compactMap { path -> URL? in
//            guard path.item > 0 && path.item < self.pages.count + 1 else { return nil }
//            return URL(string: self.pages[path.item - 1].imageURL ?? "")
//        }
//        ImagePrefetcher(urls: urls).start()
    }
}

// MARK: - Reader Page Delegate
extension ReaderScrollPageManager: ReaderPageViewDelegate {
    func imageLoaded(key: String, image: UIImage) {
        guard let collectionView = collectionView else { return }
        if sizeCache[key] == nil {
            sizeCache[key] = image.sizeToFit(collectionView.frame.size)
            collectionView.collectionViewLayout.invalidateLayout()
            Task.detached {
                let request = ImageRequest(url: URL(string: "https://" + key))
                if !ImagePipeline.shared.cache.containsCachedImage(for: request) {
                    ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: image), for: request)
                }
                Task { @MainActor in
                    self.dataCache[key] = true
                    if let targetPage = self.targetPage, self.shouldMoveToTargetPage, self.sizeCache.count >= targetPage {
                        self.shouldMoveToTargetPage = false
                        self.move(toPage: targetPage)
                    }
                }
            }
        }
    }
}

// MARK: - Context Menu Delegate
extension ReaderScrollPageManager: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard UserDefaults.standard.bool(forKey: "Reader.saveImageOption") else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
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
                    let activityController = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                    self.collectionView?.parentViewController?.present(activityController, animated: true)
                }
            }
            return UIMenu(title: "", children: [saveToPhotosAction, shareAction])
        })
    }
}
