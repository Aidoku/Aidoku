//
//  ReaderWebtoonViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import UIKit

class ReaderWebtoonViewController: BaseCollectionViewController {

    let viewModel = ReaderWebtoonViewModel()
    weak var delegate: ReaderHoldingDelegate?

    var chapter: Chapter?
    var readingMode: ReadingMode = .webtoon

    lazy var dataSource = makeDataSource()

    private var previousPage = 0
    private var isSliding = false

    private var targetPage = 0
    private var shouldMoveToTargetPage = true

    override func configure() {
        super.configure()
        collectionView.dataSource = dataSource
        collectionView.contentInset = .zero
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
    }

    /// Get the current center page of the view
    func getCurrentPage() -> Int {
        let currentPoint = CGPoint(x: 0, y: collectionView.contentOffset.y + collectionView.bounds.height / 2)
        if let path = collectionView.indexPathForItem(at: currentPoint) {
            return path.item
        } else {
            return 0
        }
    }

    // MARK: - Collection View Layout
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        CachedHeightCollectionViewLayout()
    }
}

// MARK: - Collection View Delegate
extension ReaderWebtoonViewController {

    func load(cell: ReaderWebtoonCollectionViewCell) async {
        if cell.page?.type == .prevInfoPage {
            cell.loadInfo(prevChapter: delegate?.getPreviousChapter(), nextChapter: chapter)
        } else if cell.page?.type == .nextInfoPage {
            cell.loadInfo(prevChapter: chapter, nextChapter: delegate?.getNextChapter())
        } else {
            await cell.loadPage(sourceId: chapter?.sourceId)
        }
    }

    func resize(cell: ReaderWebtoonCollectionViewCell, path: IndexPath) async {
        guard
            let layout = self.collectionView.collectionViewLayout as? CachedHeightCollectionViewLayout,
            let page = cell.page
        else { return }

        let oldHeight = layout.cachedHeights[path]
        let imageHeight = cell.pageView.imageView.image?.size.height ?? 0
        let newHeight = page.type == .imagePage ? imageHeight : 300
        layout.cachedHeights[path] = newHeight
        if oldHeight != newHeight {
            if #available(iOS 15.0, *) {
                var snapshot = self.dataSource.snapshot()
                snapshot.reconfigureItems([page])
                await self.dataSource.apply(snapshot, animatingDifferences: false)
            } else {
                layout.invalidateLayout()
            }
        }
    }

    // Load page before scrolled on screen
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? ReaderWebtoonCollectionViewCell else { return }

        Task {
            if cell.page?.type == .nextInfoPage {
                delegate?.setCompleted(true, page: nil)
            }
            await self.load(cell: cell)
            await self.resize(cell: cell, path: indexPath)
        }
    }

    // Update current page when scrolling
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSliding else { return }

        shouldMoveToTargetPage = false

        let page = getCurrentPage()
        if previousPage != page {
            previousPage = page
            delegate?.setCurrentPage(page)
        }
    }
}

// MARK: - Reader Delegate
extension ReaderWebtoonViewController: ReaderReaderDelegate {

    func sliderMoved(value: CGFloat) {
        isSliding = true

        collectionView.setContentOffset(
            CGPoint(x: 0, y: (collectionView.contentSize.height - collectionView.bounds.height) * value),
            animated: false
        )

        let page = getCurrentPage()
        delegate?.displayPage(page)
    }

    func sliderStopped(value: CGFloat) {
        isSliding = false
        scrollViewDidScroll(collectionView)
    }

    func setChapter(_ chapter: Chapter, startPage: Int) {
        self.chapter = chapter
        Task {
            await viewModel.loadPages(chapter: chapter)
            delegate?.setTotalPages(viewModel.pages.count)

            var startPage = startPage
            if startPage < 1 {
                startPage = 1
            } else if startPage > viewModel.pages.count {
                startPage = viewModel.pages.count
            }
            targetPage = startPage

            var snapshot = NSDiffableDataSourceSnapshot<Section, Page>()
            snapshot.appendSections([.current])
            snapshot.appendItems([
                Page(type: .prevInfoPage, index: -1)
            ], toSection: .current)
            snapshot.appendItems(viewModel.pages, toSection: .current)
            snapshot.appendItems([
                Page(type: .nextInfoPage, index: viewModel.pages.count)
            ], toSection: .current)
            dataSource.apply(snapshot)

            shouldMoveToTargetPage = true
            targetPage = startPage
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for i in 0...startPage {
                        group.addTask {
                            let path = IndexPath(row: i, section: 0)
                            guard let cell = await self.dataSource.collectionView(
                                self.collectionView,
                                cellForItemAt: path
                            ) as? ReaderWebtoonCollectionViewCell else { return }
                            await self.load(cell: cell)
                            await self.resize(cell: cell, path: path)
                        }
                    }
                }
                if self.shouldMoveToTargetPage {
                    self.shouldMoveToTargetPage = false
                    self.collectionView.scrollToItem(at: IndexPath(row: self.targetPage, section: 0), at: .top, animated: false)
                    self.targetPage = 0
                }
            }
        }
    }
}

// MARK: - Data Source
extension ReaderWebtoonViewController {

    enum Section: Int, CaseIterable {
        case previous
        case current
        case next
    }

    // MARK: - Cell Registration
    typealias CellRegistration = UICollectionView.CellRegistration<ReaderWebtoonCollectionViewCell, Page>

    private func makeCellRegistration() -> CellRegistration {
        CellRegistration { cell, _, page in
            cell.setPage(page: page)
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Page> {
        UICollectionViewDiffableDataSource(
            collectionView: collectionView,
            cellProvider: makeCellRegistration().cellProvider
        )
    }

    // Refresh a specified cell
    func reload(cell: ReaderWebtoonCollectionViewCell) {
        guard
            let page = cell.page,
            let path = self.collectionView.indexPath(for: cell),
            let layout = self.collectionView.collectionViewLayout as? CachedHeightCollectionViewLayout
        else { return }

        let oldHeight = layout.cachedHeights[path]
        let newHeight = cell.pageView.imageView.bounds.height
        layout.cachedHeights[path] = newHeight
        if oldHeight != newHeight {
            if #available(iOS 15.0, *) {
                var snapshot = self.dataSource.snapshot()
                snapshot.reconfigureItems([page])
                dataSource.apply(snapshot, animatingDifferences: false)
            } else {
                layout.invalidateLayout()
            }
        }
    }
}

// MARK: - Page Preloading
// Note: this doesn't work since estimatedItemSize is set, so it'll need to be implemented manually
extension ReaderWebtoonViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for path in indexPaths {
                    guard
                        let cell = dataSource.collectionView(
                            collectionView,
                            cellForItemAt: path
                        ) as? ReaderWebtoonCollectionViewCell
                    else {
                        continue
                    }
                    group.addTask {
                        await cell.loadPage(sourceId: self.chapter?.sourceId)
                    }
                }
            }
        }
    }
}
