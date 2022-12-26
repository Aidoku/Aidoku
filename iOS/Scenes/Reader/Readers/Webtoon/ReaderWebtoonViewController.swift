//
//  ReaderWebtoonViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import UIKit
import Nuke

class ReaderWebtoonViewController: ZoomableCollectionViewController {

    let viewModel = ReaderWebtoonViewModel()
    weak var delegate: ReaderHoldingDelegate?

    var chapter: Chapter?
    var readingMode: ReadingMode = .webtoon

    lazy var dataSource = makeDataSource()
    private let prefetcher = ImagePrefetcher()

    // Indicates if infinite scroll is enabled
    private lazy var infinite = UserDefaults.standard.bool(forKey: "Reader.verticalInfiniteScroll")
    private var loadingPrevious = false
    private var loadingNext = false

    // The chapters currently shown in the reader view
    private var chapters: [Chapter] = []
    // The pages corresponding to the `chapters` variable
    private var pages: [[Page]] = []

    // Next unique index to use for an info page
    private var pageInfoIndex: Int = -1
    // Indicates if the page slider is currently in use
    private var isSliding = false
    // Indicates if an info refresh should be done if info pages are off screen
    private var needsInfoRefresh = false

    // Stores the last calculated page number
    private var previousPage = 0
    // Start page to move to when opening reader
    private var shouldMoveToStartPage = true

    override func configure() {
        super.configure()

        collectionView.dataSource = dataSource
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true

        collectionView.contentInset = .zero
        collectionView.contentInsetAdjustmentBehavior = .never

        scrollView.contentInset = .zero
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bounces = false // bouncing can cause issues with page appending
        scrollView.scrollsToTop = false // dont want status bar tap to work

        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 2
    }

    override func observe() {
        addObserver(forName: "Reader.verticalInfiniteScroll") { [weak self] notification in
            self?.infinite = notification.object as? Bool
            ?? UserDefaults.standard.bool(forKey: "Reader.verticalInfiniteScroll")
        }
    }

    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        CachedHeightCollectionViewLayout()
    }

    enum ScreenPosition {
        case top
        case middle
        case bottom
    }

    /// Get the current row of the page view at `pos`
    func getCurrentPageRow(pos: ScreenPosition = .middle) -> Int? {
        let additional: CGFloat
        switch pos {
        case .top: additional = 0
        case .middle: additional = collectionView.bounds.height / 2
        case .bottom: additional = collectionView.bounds.height
        }
        let currentPoint = CGPoint(x: collectionView.contentOffset.x, y: collectionView.contentOffset.y + additional)
        return collectionView.indexPathForItem(at: currentPoint)?.row
    }

    func showLoadFailAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("FAILED_CHAPTER_LOAD", comment: ""),
            message: NSLocalizedString("FAILED_CHAPTER_LOAD_INFO", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - Scroll View Delegate
extension ReaderWebtoonViewController {

    // Update current page when scrolling
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)

        // ignore if page slider is being used
        guard !isSliding else { return }

        // cancel moving to start page if user scrolls
        shouldMoveToStartPage = false

        guard let chapter = chapter else { return }

        let chapterIndex = chapters.firstIndex(of: chapter) ?? 0
        let pageRow = getCurrentPageRow() ?? 0
        // number of pages in previous chapters
        let pageCountAbove = pages[0..<chapterIndex].reduce(0, { result, pages in
            result + pages.count + 1
        })

        if infinite {
            // check if we need to switch chapters
            if (chapterIndex == 1 && pageRow <= pages[0].count) || (chapterIndex == 2 && pageRow < pageCountAbove) {
                movePreviousChapter()
                needsInfoRefresh = true
            } else if chapterIndex != chapters.count - 1 {
                if
                    chapters.count == 3 && pageRow > pages[0].count + 1 && chapterIndex == 0 ||
                    pageRow > pageCountAbove + pages[chapterIndex].count + 1
                {
                    moveNextChapter()
                    needsInfoRefresh = true
                }
            }
        }

        // get page offset if we have previous chapter(s)
        let offset: Int
        if chapterIndex != 0 {
            offset = pageCountAbove
        } else {
            offset = 0
        }
        // update page number
        let page = pageRow - offset
        if previousPage != page {
            previousPage = page
            delegate?.setCurrentPage(page)
        }
    }

    // disable slider movement while zooming
    // zooming sometimes causes page count to jitter between two pages
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        isSliding = true
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        isSliding = false
        scrollViewDidScroll(scrollView)
    }
}

// MARK: - Collection View Delegate
extension ReaderWebtoonViewController {

    /// Load a cell's page image or info
    func load(cell: ReaderWebtoonCollectionViewCell, path: IndexPath) async {
        guard let chapter = chapter else { return }
        if cell.page?.type == .imagePage {
            await cell.loadPage(sourceId: chapter.sourceId)
        } else {
            let chapterIndex = chapters.firstIndex(of: chapter) ?? 0

            func loadPrevious() {
                cell.page?.type = .prevInfoPage
                cell.loadInfo(prevChapter: delegate?.getPreviousChapter(), nextChapter: chapter)
            }
            func loadNext() {
                cell.page?.type = .nextInfoPage
                cell.loadInfo(prevChapter: chapter, nextChapter: delegate?.getNextChapter())
            }

            switch chapterIndex {
            case 0:
                if path.row == 0 {
                    loadPrevious()
                } else {
                    loadNext()
                }
            case 1:
                if path.row == pages[0].count + 1 {
                    loadPrevious()
                } else {
                    loadNext()
                }
            case 2:
                if path.row == pages[0].count + pages[1].count + 2 {
                    loadPrevious()
                } else {
                    loadNext()
                }
            default:
                break
            }
        }
    }

    /// Resize a specified cell
    func resize(cell: ReaderWebtoonCollectionViewCell, path: IndexPath) async {
        guard
            let layout = self.collectionView.collectionViewLayout as? CachedHeightCollectionViewLayout,
            let page = cell.page
        else { return }

        let oldAttr = layout.layoutAttributesForItem(at: path)
        let newAttr = cell.preferredLayoutAttributesFitting(UICollectionViewLayoutAttributes())
        let oldHeight = oldAttr?.size.height
        let newHeight = newAttr.size.height
        layout.cachedHeights[path] = newHeight

        if oldHeight != newHeight {
            if #available(iOS 15.0, *) {
                var snapshot = self.dataSource.snapshot()
                if snapshot.indexOfItem(page) != nil {
                    snapshot.reconfigureItems([page])
                    await MainActor.run {
                        self.dataSource.apply(snapshot, animatingDifferences: false)
                        zoomView.adjustContentSize()
                    }
                }
            } else {
                layout.invalidateLayout()
                zoomView.adjustContentSize()
            }
        }
    }

    // Load page before scrolled on screen
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? ReaderWebtoonCollectionViewCell else { return }

        Task {
            await self.load(cell: cell, path: indexPath)
            await self.resize(cell: cell, path: indexPath)
        }
    }

    // Refresh info pages after they move off screen
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard needsInfoRefresh, let cell = cell as? ReaderWebtoonCollectionViewCell else { return }
        if cell.page?.type != .imagePage {
            needsInfoRefresh = false
            refreshInfoPages()
        }
    }

    // Save image force touch menu
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let path = indexPaths.first,
            let cell = collectionView.cellForItem(at: path) as? ReaderWebtoonCollectionViewCell,
            cell.page?.type == .imagePage,
            cell.pageView.imageView.image != nil,
            UserDefaults.standard.bool(forKey: "Reader.saveImageOption")
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            let saveToPhotosAction = UIAction(
                title: NSLocalizedString("SAVE_TO_PHOTOS", comment: ""),
                image: UIImage(systemName: "photo")
            ) { _ in
                if let image = cell.pageView.imageView.image {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
            let shareAction = UIAction(
                title: NSLocalizedString("SHARE", comment: ""),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                if let image = cell.pageView.imageView.image {
                    let items = [image]
                    let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)
                    self.present(activityController, animated: true)
                }
            }
            return UIMenu(title: "", children: [saveToPhotosAction, shareAction])
        })
    }
}

// MARK: - Infinite Scroll
extension ReaderWebtoonViewController {

    // check for infinite load when deceleration stops
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard infinite else { return }
        if decelerate {
            return
        }
        checkInfiniteLoad(decelerated: !decelerate)
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard infinite else { return }
        checkInfiniteLoad(decelerated: true)
    }

    // check if at the top or bottom to append the next/prev chapter
    func checkInfiniteLoad(decelerated: Bool = false) {
        let top = getCurrentPageRow(pos: .top) ?? 0
        // prepend previous chapter
        if !loadingPrevious && top == 0 {
            loadingPrevious = true
            Task {
                await prependPreviousChapter()
                loadingPrevious = false
            }
        }
        if !loadingNext {
            let pagesCount = pages.reduce(0, { result, pages in
                result + pages.count + 1
            })
            let bottom = getCurrentPageRow(pos: .bottom) ?? pagesCount
            // append next chapter
            if bottom == pagesCount {
                loadingNext = true
                Task {
                    await appendNextChapter()
                    loadingNext = false
                }
            }
        }
    }

    /// Prepend the previous chapter's pages
    func prependPreviousChapter() async {
        guard let prevChapter = delegate?.getPreviousChapter() else { return }
        await viewModel.preload(chapter: prevChapter)

        // check if pages failed to load
        if viewModel.preloadedPages.isEmpty {
            return
        }

        var snapshot = dataSource.snapshot()

        if chapters.count >= 3 {
            // adjust cachedHeights
            // row snapshot.itemIdentifiers.count - (pages.last!.count + 1)..<snapshot.itemIdentifiers.count
            // cells are removed from the end and the previous are shifted back
            // TODO: this causes some extra stuttering that I need to diagnose
//            if let layout = self.collectionView.collectionViewLayout as? CachedHeightCollectionViewLayout {
//                let lastRow = snapshot.itemIdentifiers.count - (pages.last!.count + 1)
//                var newHeights: [IndexPath: CGFloat] = [:]
//                for key in layout.cachedHeights.keys where key.row < lastRow {
//                    let newPath = IndexPath(row: key.row + lastRow, section: 0)
//                    newHeights[newPath] = layout.cachedHeights[key]
//                }
//                layout.cachedHeights = newHeights
//            }
            snapshot.deleteItems(pages.last! + [snapshot.itemIdentifiers.last!])
            chapters.removeLast()
            pages.removeLast()
        }

        snapshot.insertItems(
            [Page(type: .prevInfoPage, chapterId: prevChapter.id, index: pageInfoIndex)] + viewModel.preloadedPages,
            beforeItem: snapshot.itemIdentifiers.first!
        )
        pageInfoIndex -= 1

        chapters.insert(prevChapter, at: 0)
        pages.insert(viewModel.preloadedPages, at: 0)

        let previousOffset = collectionView.contentOffset.y
        func setOffset() {
            collectionView.scrollToItem(
                at: IndexPath(row: viewModel.preloadedPages.count + 1, section: 0),
                at: .top,
                animated: false
            )
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: collectionView.contentOffset.y + previousOffset),
                animated: false
            )
            zoomView.scrollView.contentOffset = collectionView.contentOffset
            zoomView.adjustContentSize()
            CATransaction.commit()
        }

        // disable animations and adjust offset before re-enabling
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        await MainActor.run {
            if #available(iOS 15.0, *) {
                dataSource.applySnapshotUsingReloadData(snapshot) {
                    setOffset()
                }
            } else {
                dataSource.apply(snapshot, animatingDifferences: false)
                setOffset()
            }
        }
    }

    /// Append the next chapter's pages
    func appendNextChapter() async {
        guard let nextChapter = delegate?.getNextChapter() else { return }
        await viewModel.preload(chapter: nextChapter)

        // check if pages failed to load
        if viewModel.preloadedPages.isEmpty {
            return
        }

        var snapshot = dataSource.snapshot()
        snapshot.appendItems(viewModel.preloadedPages + [Page(type: .nextInfoPage, chapterId: nextChapter.id, index: pageInfoIndex)])
        pageInfoIndex -= 1

        let removeChapter = chapters.count >= 3

        if removeChapter {
            // adjust cachedHeights
            // row 0..<pages.first!.count + 1 cells are removed from the front
            // and the remaining are shifted forwards
            if let layout = self.collectionView.collectionViewLayout as? CachedHeightCollectionViewLayout {
                let lastRow = pages.first!.count + 1
                var newHeights: [IndexPath: CGFloat] = [:]
                for key in layout.cachedHeights.keys where key.row >= lastRow {
                    let newPath = IndexPath(row: key.row - lastRow, section: 0)
                    newHeights[newPath] = layout.cachedHeights[key]
                }
                layout.cachedHeights = newHeights
            }
            snapshot.deleteItems(pages.first! + [snapshot.itemIdentifiers.first!])
            chapters.removeFirst()
            pages.removeFirst()
        }
        chapters.append(nextChapter)
        pages.append(viewModel.preloadedPages)

        // offset from the bottom
        let previousOffset = collectionView.contentSize.height - collectionView.contentOffset.y - collectionView.bounds.height

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        await MainActor.run {
            dataSource.apply(snapshot, animatingDifferences: false)

            if removeChapter {
                let pageCountAbove = pages[0..<2].reduce(0, { result, pages in
                    result + pages.count + 1
                })
                collectionView.scrollToItem(
                    at: IndexPath(row: pageCountAbove, section: 0),
                    at: .bottom,
                    animated: false
                )
                collectionView.setContentOffset(
                    CGPoint(x: collectionView.contentOffset.x, y: collectionView.contentOffset.y - previousOffset),
                    animated: false
                )
                zoomView.scrollView.contentOffset = collectionView.contentOffset
            }

            zoomView.adjustContentSize()
            CATransaction.commit()
        }
    }

    /// Switch current chapter to previous
    func movePreviousChapter() {
        guard
            let currChapter = chapter,
            let chapterIndex = chapters.firstIndex(of: currChapter),
            chapterIndex > 0
        else { return }
        let chapter = chapters[chapterIndex - 1]
        let pages = pages[chapterIndex - 1]
        self.chapter = chapter
        delegate?.setChapter(chapter)
        delegate?.setTotalPages(pages.count)
        viewModel.setPages(chapter: chapter, pages: pages)
    }

    /// Switch current chapter to next
    func moveNextChapter() {
        guard
            let currChapter = chapter,
            let chapterIndex = chapters.firstIndex(of: currChapter),
            chapters.count > chapterIndex
        else { return }
        let chapter = chapters[chapterIndex + 1]
        let pages = pages[chapterIndex + 1]
        self.chapter = chapter
        delegate?.setChapter(chapter)
        delegate?.setTotalPages(pages.count)
        viewModel.setPages(chapter: chapter, pages: pages)
    }

    /// Refresh info page chapter info
    func refreshInfoPages() {
        var snapshot = dataSource.snapshot()
        var items = [snapshot.itemIdentifiers.first!, snapshot.itemIdentifiers.last!]
        if chapters.count >= 2 {
            items += [snapshot.itemIdentifiers[pages[0].count + 1]]
        }
        if chapters.count >= 3 { // max of 3 chapters
            items += [snapshot.itemIdentifiers[pages[0].count + pages[1].count + 2]]
        }
        snapshot.reloadItems(items)
        Task { @MainActor in
            dataSource.apply(snapshot, animatingDifferences: false)
            zoomView.adjustContentSize()
        }
    }
}

// MARK: - Reader Delegate
extension ReaderWebtoonViewController: ReaderReaderDelegate {

    func sliderMoved(value: CGFloat) {
        isSliding = true

        // get slider area
        guard
            let chapter = chapter,
            let chapterIndex = chapters.firstIndex(of: chapter),
            pages.count > chapterIndex,
            let layout = self.collectionView.collectionViewLayout as? CachedHeightCollectionViewLayout
        else { return }

        let pageCountAbove = pages[0..<chapterIndex].reduce(0, { result, pages in
            result + pages.count + 1
        })
        let offset = layout.getHeightFor(section: 0, range: 0..<pageCountAbove + 1)
        let height = layout.getHeightFor(
            section: 0,
            range: pageCountAbove..<pageCountAbove + pages[chapterIndex].count + 1
        ) - collectionView.bounds.height - ReaderWebtoonCollectionViewCell.estimatedHeight

        zoomView.scrollView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: offset + height * value),
            animated: false
        )

        let page = (getCurrentPageRow() ?? 0) - (chapterIndex != 0 ? pageCountAbove : 0)
        delegate?.displayPage(page)
    }

    func sliderStopped(value: CGFloat) {
        isSliding = false
        scrollViewDidScroll(collectionView)
    }

    func setChapter(_ chapter: Chapter, startPage: Int) {
        self.chapter = chapter
        chapters = [chapter]

        Task {
            await viewModel.loadPages(chapter: chapter)
            delegate?.setTotalPages(viewModel.pages.count)
            pages = [viewModel.pages]
            if viewModel.pages.isEmpty {
                showLoadFailAlert()
                var snapshot = NSDiffableDataSourceSnapshot<Int, Page>()
                snapshot.appendSections([0])
                await MainActor.run {
                    dataSource.apply(snapshot)
                    zoomView.adjustContentSize()
                }
                return
            }

            var startPage = startPage
            if startPage < 1 {
                startPage = 1
            } else if startPage > viewModel.pages.count {
                startPage = viewModel.pages.count
            }

            var snapshot = NSDiffableDataSourceSnapshot<Int, Page>()
            snapshot.appendSections([0])
            snapshot.appendItems([
                Page(type: .prevInfoPage, chapterId: chapter.id, index: pageInfoIndex)
            ])
            snapshot.appendItems(viewModel.pages)
            snapshot.appendItems([
                Page(type: .nextInfoPage, chapterId: chapter.id, index: pageInfoIndex - 1)
            ])
            pageInfoIndex -= 2
            await MainActor.run {
                dataSource.apply(snapshot)
                zoomView.adjustContentSize()
            }

            shouldMoveToStartPage = true
            // load pages up to startPage
            await withTaskGroup(of: Void.self) { group in
                for i in 0...startPage {
                    group.addTask {
                        let path = IndexPath(row: i, section: 0)
                        guard let cell = await self.dataSource.collectionView(
                            self.collectionView,
                            cellForItemAt: path
                        ) as? ReaderWebtoonCollectionViewCell else { return }
                        await self.load(cell: cell, path: path)
                        await self.resize(cell: cell, path: path)
                    }
                }
            }
            // if it hasn't been canceled, move to targetPage
            if shouldMoveToStartPage {
                shouldMoveToStartPage = false
                collectionView.scrollToItem(
                    at: IndexPath(row: startPage, section: 0),
                    at: .top,
                    animated: false
                )
                zoomView.scrollView.contentOffset = collectionView.contentOffset
            }
        }
    }
}

// MARK: - Data Source
extension ReaderWebtoonViewController {

    // MARK: - Cell Registration
    typealias CellRegistration = UICollectionView.CellRegistration<ReaderWebtoonCollectionViewCell, Page>

    private func makeCellRegistration() -> CellRegistration {
        CellRegistration { cell, path, page in
            cell.setPage(page: page)
            Task {
                await self.load(cell: cell, path: path)
            }
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Int, Page> {
        UICollectionViewDiffableDataSource(
            collectionView: collectionView,
            cellProvider: makeCellRegistration().cellProvider
        )
    }
}

// MARK: - Page Preloading
extension ReaderWebtoonViewController: UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.compactMap {
            if let url = dataSource.itemIdentifier(for: $0)?.imageURL {
                return URL(string: url)
            }
            return nil
        }
        prefetcher.startPrefetching(with: urls)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.compactMap {
            if let url = dataSource.itemIdentifier(for: $0)?.imageURL {
                return URL(string: url)
            }
            return nil
        }
        prefetcher.stopPrefetching(with: urls)
    }
}
