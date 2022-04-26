//
//  ReaderScrollPageManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/15/22.
//

import UIKit
import Kingfisher

extension UIImage {
    func sizeToFit(_ pageSize: CGSize) -> CGSize {
        guard size.height * size.width * pageSize.width * pageSize.height > 0 else { return .zero }

        let scaledHeight = size.height * (pageSize.width / size.width)
        return CGSize(width: pageSize.width, height: scaledHeight)
    }
}

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

    var preloadedChapter: Chapter?
    var preloadedPages: [Page] = []

    var collectionView: UICollectionView!

    var sizeCache: [String: CGSize] = [:]
    var lastSize: CGSize?

    var chapterList: [Chapter] = []
    var chapterIndex: Int {
        guard let chapter = chapter else { return 0 }
        return chapterList.firstIndex(of: chapter) ?? 0
    }

    var hasNextChapter = false
    var hasPreviousChapter = false

    var targetPage: Int?
    var shouldMoveToTargetPage = true
    var transitioningChapter = false

    var previousPageIndex = 0

    var currentIndex: Int {
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

    func attach(toParent parent: UIViewController) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets.zero

        layout.scrollDirection = .vertical

        collectionView = UICollectionView(frame: parent.view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView?.register(ReaderPageCollectionViewCell.self, forCellWithReuseIdentifier: "ReaderPageCollectionViewCell")
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

        NotificationCenter.default.addObserver(forName: NSNotification.Name("Reader.verticalInfiniteScroll"), object: nil, queue: nil) { _ in
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
        }
    }

    func remove() {
        guard collectionView != nil else { return }
        pages.removeAll()
        sizeCache.removeAll()
        collectionView.removeFromSuperview()
        collectionView = nil
    }

    func setChapter(chapter: Chapter, startPage: Int) {
        guard collectionView != nil else { return }

        self.chapter = chapter
        targetPage = startPage

        if transitioningChapter {
            transitioningChapter = false
        } else {
            shouldMoveToTargetPage = true
        }

        Task { @MainActor in
            await loadPages()
            setImages(for: 0..<startPage+1)
            if collectionView != nil {
                collectionView.reloadData()
                // Move to the first page immidiately
                if targetPage == 0 && shouldMoveToTargetPage {
                    shouldMoveToTargetPage = false
                    move(toPage: 0)
                }
            }
        }
    }

    func move(toPage page: Int) {
        collectionView.scrollToItem(at: IndexPath(item: page + 1, section: 1), at: .top, animated: false)
        delegate?.didMove(toPage: page)
    }

    func willTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: nil) { _ in
            for (key, value) in self.sizeCache {
                let newValue = CGSize(
                    width: self.collectionView.bounds.size.width,
                    height: value.height * (self.collectionView.bounds.size.width / value.width)
                )
                self.sizeCache[key] = newValue
            }
            self.collectionView?.collectionViewLayout.invalidateLayout()
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
            hasPreviousChapter = chapterIndex != chapterList.count - 1
            hasNextChapter = chapterIndex != 0
        } else {
            hasPreviousChapter = false
            hasNextChapter = false
        }
    }

    func preload(chapter: Chapter) async {
        preloadedPages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
        preloadedChapter = chapter
    }

    func setImages(for range: Range<Int>) {
        for i in range {
            guard i < pages.count else { break }
            if i < 0 {
                continue
            }
            let path = IndexPath(item: i + 1, section: 1)
            if let cell = collectionView(collectionView, cellForItemAt: path) as? ReaderPageCollectionViewCell {
                if let url = pages[i].imageURL {
                    cell.setPageImage(url: url)
                } else if let base64 = pages[i].base64 {
                    cell.setPageImage(base64: base64)
                } else if let text = pages[i].text {
                    cell.setPageText(text: text)
                }
            }
        }
    }

    @MainActor
    func append(chapter: Chapter, toFront: Bool = false) async {
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
                self.collectionView.setContentOffset(
                    CGPoint(x: 0, y: self.collectionView.contentSize.height - bottomOffset),
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
        var extraHeight: CGFloat = 0
        if previousChapter != nil {
            extraHeight = previousPages.map { sizeCache[$0.imageURL ?? ""]?.height ?? 100 }.reduce(0, +)
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
                key = previousPages[indexPath.item].imageURL
            }
        } else if indexPath.section == 2 {
            if indexPath.item < nextPages.count {
                key = nextPages[indexPath.item].imageURL
            }
        } else if indexPath.item == 0 || indexPath.item >= pages.count + 1 {
            return CGSize(width: collectionView.frame.size.width, height: 300)
        } else {
            if indexPath.item - 1 < pages.count {
                key = pages[indexPath.item - 1].imageURL
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

        if bottomCellIndex == pages.count && hasNextChapter { // preload next chapter
            Task {
                await preload(chapter: chapterList[chapterIndex - 1])
            }
        } else if bottomCellIndex >= pages.count + 1 && hasNextChapter { // append next chapter
            let nextChapter = chapterList[chapterIndex - 1]
            if self.nextChapter != nextChapter {
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
                }
                cell.infoView?.nextChapter = hasNextChapter ? chapterList[chapterIndex - 1] : nil
                cell.infoView?.previousChapter = nil
            } else {
                page = pages[indexPath.item - 1]
            }
            if let url = page?.imageURL {
                cell.setPageImage(url: url)
            } else if let base64 = page?.base64 {
                cell.setPageImage(base64: base64)
            } else if let text = page?.text {
                cell.setPageText(text: text)
            }
        }
    }
}

// MARK: - Collection View Data Source
extension ReaderScrollPageManager: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        3
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
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
                let item = indexPath.item
                if item == 0 {
                    cell.convertToInfo(type: .previous, currentChapter: chapter)
                    if hasPreviousChapter {
                        cell.infoView?.previousChapter = chapterList[chapterIndex + 1]
                        cell.infoView?.nextChapter = nil
                    }
                } else if item == pages.count + 1 {
                    cell.convertToInfo(type: .next, currentChapter: chapter)
                    if hasNextChapter {
                        cell.infoView?.nextChapter = chapterList[chapterIndex - 1]
                        cell.infoView?.previousChapter = nil
                    }
                } else {
                    cell.convertToPage()
                    cell.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                    cell.pageView?.delegate = self
                }
            }
        }

        return cell
    }
}

// MARK: - Collection View Prefetching
extension ReaderScrollPageManager: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.compactMap { path -> URL? in
            guard path.item > 0 && path.item < self.pages.count + 1 else { return nil }
            return URL(string: self.pages[path.item - 1].imageURL ?? "")
        }
        ImagePrefetcher(urls: urls).start()
    }
}

// MARK: - Reader Page Delegate
extension ReaderScrollPageManager: ReaderPageViewDelegate {
    func imageLoaded(result: Result<RetrieveImageResult, KingfisherError>) {
        switch result {
        case .success(let imageResult):
            let key = imageResult.source.cacheKey
            if sizeCache[key] == nil {
                sizeCache[key] = imageResult.image.sizeToFit(collectionView.frame.size)
                collectionView.collectionViewLayout.invalidateLayout()
                if let targetPage = targetPage, shouldMoveToTargetPage, sizeCache.count >= targetPage {
                    move(toPage: targetPage)
                    shouldMoveToTargetPage = false
                }
            }
        case .failure:
            break
        }
    }
}

// MARK: - Context Menu Delegate
extension ReaderScrollPageManager: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            let saveToPhotosAction = UIAction(title: NSLocalizedString("SAVE_TO_PHOTOS", comment: ""),
                                              image: UIImage(systemName: "square.and.arrow.down")) { _ in
                if let pageView = interaction.view as? UIImageView,
                   let image = pageView.image {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
            return UIMenu(title: "", children: [saveToPhotosAction])
        })
    }
}

// MARK: - Reader Page Collection Cell
class ReaderPageCollectionViewCell: UICollectionViewCell {

    var sourceId: String?

    var pageView: ReaderPageView?
    var infoView: ReaderInfoPageView?

    func convertToPage() {
        guard pageView == nil else { return }

        infoView?.removeFromSuperview()
        infoView = nil

        pageView = ReaderPageView(sourceId: sourceId ?? "")
        pageView?.zoomEnabled = false
        pageView?.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageView!)

        pageView?.topAnchor.constraint(equalTo: topAnchor).isActive = true
        pageView?.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        pageView?.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        pageView?.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    func convertToInfo(type: ReaderInfoPageType, currentChapter: Chapter) {
        guard infoView == nil else { return }

        pageView?.removeFromSuperview()
        pageView = nil

        infoView = ReaderInfoPageView(type: type, currentChapter: currentChapter)
        infoView?.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoView!)

        infoView?.topAnchor.constraint(equalTo: topAnchor).isActive = true
        infoView?.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        infoView?.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        infoView?.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    func setPageImage(url: String) {
        guard pageView?.currentUrl ?? "" != url || pageView?.imageView.image == nil else { return }
        Task {
            await pageView?.setPageImage(url: url)
        }
    }

    func setPageImage(base64: String) {
        pageView?.setPageImage(base64: base64)
    }

    func setPageText(text: String) {
        pageView?.setPageText(text: text)
    }
}
