//
//  ReaderWebtoonViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import UIKit
import Nuke
import AsyncDisplayKit

class ReaderWebtoonViewController: ZoomableCollectionViewController {

    let viewModel = ReaderWebtoonViewModel()
    weak var delegate: ReaderHoldingDelegate?

    var chapter: Chapter?
    var readingMode: ReadingMode = .webtoon

    private let prefetcher = ImagePrefetcher()

    // Indicates if infinite scroll is enabled
    private lazy var infinite = UserDefaults.standard.bool(forKey: "Reader.verticalInfiniteScroll")
    private var loadingPrevious = false
    private var loadingNext = false

    // The chapters currently shown in the reader view
    private var chapters: [Chapter] = []
    // The pages corresponding to the `chapters` variable
    private var pages: [[Page]] = []

    // Indicates if the page slider is currently in use
    private var isSliding = false
    // Indicates if an info refresh should be done if info pages are off screen
    private var needsInfoRefresh = false

    // Stores the last calculated page number
    private var previousPage = 0

    convenience init() {
        self.init(layout: VerticalContentOffsetPreservingLayout())
    }

    override func configure() {
        super.configure()

        collectionNode.delegate = self
        collectionNode.dataSource = self
//        collectionNode.view.prefetchDataSource = self
//        collectionNode.isPrefetchingEnabled = true

        scrollView.contentInset = .zero
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bounces = false // bouncing can cause issues with page appending
        scrollView.scrollsToTop = false // dont want status bar tap to work
        scrollNode.insetsLayoutMarginsFromSafeArea = false

        collectionNode.contentInset = .zero
        collectionNode.showsVerticalScrollIndicator = false
        collectionNode.showsHorizontalScrollIndicator = false
        collectionNode.view.contentInsetAdjustmentBehavior = .never
        collectionNode.view.bounces = false
        collectionNode.view.scrollsToTop = false

        collectionNode.automaticallyManagesSubnodes = true
        collectionNode.shouldAnimateSizeChanges = false
        collectionNode.insetsLayoutMarginsFromSafeArea = false

        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 2
    }

    override func observe() {
        addObserver(forName: "Reader.verticalInfiniteScroll") { [weak self] notification in
            self?.infinite = notification.object as? Bool
            ?? UserDefaults.standard.bool(forKey: "Reader.verticalInfiniteScroll")
        }
    }

    enum ScreenPosition {
        case top
        case middle
        case bottom
    }

    /// Get the current row of the page view at `pos`
    func getCurrentPagePath(pos: ScreenPosition = .middle) -> IndexPath? {
        let additional: CGFloat
        switch pos {
        case .top: additional = 0
        case .middle: additional = collectionNode.bounds.height / 2
        case .bottom: additional = collectionNode.bounds.height
        }
        let currentPoint = CGPoint(x: collectionNode.contentOffset.x, y: collectionNode.contentOffset.y + additional)
        return collectionNode.indexPathForItem(at: currentPoint)
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

    func getCurrentPage() -> Int {
        guard let chapter = chapter else { return 0 }
        let chapterIndex = chapters.firstIndex(of: chapter) ?? 0
        let pageRow = getCurrentPagePath()?.row ?? 0
        let hasStartInfo = pages[chapterIndex].first?.type != .imagePage
        let hasEndInfo = pages[chapterIndex].last?.type != .imagePage
        return min(
            max(pageRow + (hasStartInfo ? 0 : 1), 1),
            pages[chapterIndex].count - (hasStartInfo ? 1 : 0) - (hasEndInfo ? 1 : 0)
        )
    }

    // Update current page when scrolling
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)

        // ignore if page slider is being used
        guard !isSliding else { return }

        guard let chapter = chapter else { return }

        let chapterIndex = chapters.firstIndex(of: chapter) ?? 0
        let pagePath = getCurrentPagePath()
        let pageSection = pagePath?.section ?? 0

        if infinite {
            // check if we need to switch chapters
            if chapterIndex > 0 && pageSection < chapterIndex {
                movePreviousChapter()
                needsInfoRefresh = true
            } else if chapterIndex < chapters.count - 1 {
                if pageSection > chapterIndex {
                    moveNextChapter()
                    needsInfoRefresh = true
                }
            }
        }

        // update page number
        let page = getCurrentPage()
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

    // fix content size when rotating
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.zoomView.adjustContentSize()
        }
    }
}

// MARK: - Context Menu
extension ReaderWebtoonViewController: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            case let point = interaction.location(in: collectionNode.view),
            let indexPath = collectionNode.indexPathForItem(at: point),
            let node = collectionNode.nodeForItem(at: indexPath) as? ReaderWebtoonImageNode,
            let image = node.imageNode.image,
            UserDefaults.standard.bool(forKey: "Reader.saveImageOption")
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            let saveToPhotosAction = UIAction(
                title: NSLocalizedString("SAVE_TO_PHOTOS", comment: ""),
                image: UIImage(systemName: "photo")
            ) { _ in
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            let shareAction = UIAction(
                title: NSLocalizedString("SHARE", comment: ""),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                let items = [image]
                let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)
                self.present(activityController, animated: true)
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
        checkInfiniteLoad()
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard infinite else { return }
        checkInfiniteLoad()
    }

    // check if at the top or bottom to append the next/prev chapter
    func checkInfiniteLoad() {
        // prepend previous chapter
        if !loadingPrevious {
            let topPath = getCurrentPagePath(pos: .top)
            if topPath == nil || (topPath?.section == 0 && topPath?.row == 0) {
                loadingPrevious = true
                Task {
                    await prependPreviousChapter()
                    loadingPrevious = false
                }
            }
        }
        if !loadingNext {
            let bottomPath = getCurrentPagePath(pos: .bottom)
            // append next chapter
            if bottomPath == nil || (bottomPath?.section == pages.count - 1 && bottomPath?.item == pages[pages.count - 1].count - 1) {
                loadingNext = true
                delegate?.setCompleted()
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

        // queue remove last section if we have three already
        let removeLast = chapters.count >= 3

        chapters.insert(prevChapter, at: 0)
        pages.insert(
            [Page(
                type: .prevInfoPage,
                sourceId: prevChapter.sourceId,
                chapterId: prevChapter.id,
                index: -1
            )]  + viewModel.preloadedPages,
            at: 0
        )

        await MainActor.run {
            let layout = collectionNode.collectionViewLayout as? VerticalContentOffsetPreservingLayout
            layout?.isInsertingCellsAbove = true

            // disable animations and adjust offset before re-enabling
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            collectionNode.performBatchUpdates {
                collectionNode.insertSections(IndexSet(integer: 0))
            } completion: { finished in
                if finished {
                    if removeLast {
                        self.chapters.removeLast()
                        self.pages.removeLast()

                        // remove last section
                        self.collectionNode.performBatchUpdates {
                            self.collectionNode.deleteSections(IndexSet(integer: self.pages.count - 1))
                        } completion: { finished in
                            if finished {
                                self.scrollView.contentOffset = self.collectionNode.contentOffset
                                self.zoomView.adjustContentSize()
                                CATransaction.commit()
                            }
                        }
                    } else {
                        self.scrollView.contentOffset = self.collectionNode.contentOffset
                        self.zoomView.adjustContentSize()
                        CATransaction.commit()
                    }
                }
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

        // queue remove first section if we have three already
        let removeFirst = chapters.count >= 3

        chapters.append(nextChapter)
        pages.append(viewModel.preloadedPages + [Page(
            type: .nextInfoPage,
            sourceId: nextChapter.sourceId,
            chapterId: nextChapter.id,
            index: -2
        )])

        await MainActor.run {
            collectionNode.performBatchUpdates {
                collectionNode.insertSections(IndexSet(integer: pages.count - 1))
            } completion: { finished in
                // disable animations and adjust offset before re-enabling
                if finished {
                    if removeFirst {
                        self.chapters.removeFirst()
                        self.pages.removeFirst()
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        self.collectionNode.performBatchUpdates {
                            self.collectionNode.deleteSections(IndexSet(integer: 0))
                        } completion: { finished in
                            if finished {
                                self.scrollView.contentOffset = self.collectionNode.contentOffset
                                self.zoomView.adjustContentSize()
                                CATransaction.commit()
                            }
                        }
                    } else {
                        self.scrollView.contentOffset = self.collectionNode.contentOffset
                        self.zoomView.adjustContentSize()
                    }
                }
            }
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
        delegate?.setTotalPages(pages.filter({ $0.type == .imagePage }).count)
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
        delegate?.setTotalPages(pages.filter({ $0.type == .imagePage }).count)
        viewModel.setPages(chapter: chapter, pages: pages)
    }

    /// Refresh info page chapter info
    func refreshInfoPages() {
        let paths = pages.enumerated().flatMap { section, pages in
            pages.enumerated().compactMap { item, page in
                if page.type != .imagePage {
                    return IndexPath(item: item, section: section)
                } else {
                    return nil
                }
            }
        }
        collectionNode.performBatchUpdates {
            collectionNode.reloadItems(at: paths)
        } completion: { finished in
            if finished {
                self.zoomView.adjustContentSize()
            }
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
            let layout = self.collectionNode.collectionViewLayout as? VerticalContentOffsetPreservingLayout
        else { return }

        var offset: CGFloat = 0
        for idx in 0..<chapterIndex {
            offset += layout.getHeightFor(section: idx)
        }

        let hasStartInfo = pages[chapterIndex].first?.type != .imagePage
        let hasEndInfo = pages[chapterIndex].last?.type != .imagePage

        if hasStartInfo {
            offset += layout.getHeightFor(section: chapterIndex, range: 0..<1)
        }

        let height = layout.getHeightFor(
            section: chapterIndex,
            range: (hasStartInfo ? 1 : 0)..<pages[chapterIndex].count - (hasEndInfo ? 1 : 0)
        ) - collectionNode.bounds.height

        scrollView.setContentOffset(
            CGPoint(x: collectionNode.contentOffset.x, y: offset + height * value),
            animated: false
        )

        let page = getCurrentPage()
        delegate?.displayPage(page)
    }

    func sliderStopped(value: CGFloat) {
        isSliding = false
        scrollViewDidScroll(collectionNode.view)
    }

    func setChapter(_ chapter: Chapter, startPage: Int) {
        self.chapter = chapter
        chapters = [chapter]

        Task {
            await viewModel.loadPages(chapter: chapter)
            delegate?.setTotalPages(viewModel.pages.count)
            if viewModel.pages.isEmpty {
                pages = []
                showLoadFailAlert()
                await collectionNode.reloadData()
                return
            }
            pages = [[
                Page(type: .prevInfoPage, sourceId: chapter.sourceId, chapterId: chapter.id, index: -1)
            ] + viewModel.pages + [
                Page(type: .nextInfoPage, sourceId: chapter.sourceId, chapterId: chapter.id, index: -2)
            ]]

            var startPage = startPage
            if startPage < 1 {
                startPage = 1
            } else if startPage > viewModel.pages.count {
                startPage = viewModel.pages.count
            }

            await collectionNode.reloadData()
            zoomView.adjustContentSize()

            // scroll to first page
            collectionNode.scrollToItem(
                at: IndexPath(row: startPage, section: 0),
                at: .top,
                animated: false
            )
            scrollView.contentOffset = collectionNode.contentOffset
        }
    }
}

// MARK: - Collection View Delegate
extension ReaderWebtoonViewController: ASCollectionDelegate {

    // Refresh info pages after they move off screen
    func collectionNode(_ collectionNode: ASCollectionNode, didEndDisplayingItemWith node: ASCellNode) {
        guard needsInfoRefresh else { return }
        if node is ReaderWebtoonTransitionNode {
            needsInfoRefresh = false
            refreshInfoPages()
        }
    }
}

// MARK: - Data Source
extension ReaderWebtoonViewController: ASCollectionDataSource {

    func numberOfSections(in collectionNode: ASCollectionNode) -> Int {
        pages.count
    }

    func collectionNode(_ collectionNode: ASCollectionNode, numberOfItemsInSection section: Int) -> Int {
        pages[section].count
    }

    func collectionNode(_ collectionNode: ASCollectionNode, nodeBlockForItemAt indexPath: IndexPath) -> ASCellNodeBlock {
        guard let chapter else { return { ASCellNode() } }
        var page = pages[indexPath.section][indexPath.item]
        if page.type == .imagePage {
            // image page
            return {
                let cell = ReaderWebtoonImageNode(page: page)
                cell.delegate = self
                return cell
            }
        } else {
            // transition page
            let chapterIndex = chapters.firstIndex(of: chapter) ?? 0

            // determine page type
            if (indexPath.section == chapterIndex && indexPath.item == 0)
                || (indexPath.section == chapterIndex - 1 && indexPath.item > 0) {
                page.type = .prevInfoPage
            } else {
                page.type = .nextInfoPage
            }

            let to = page.type == .prevInfoPage
                ? self.delegate?.getPreviousChapter()
                : self.delegate?.getNextChapter()
            return {
                ReaderWebtoonTransitionNode(transition: Transition(
                    type: page.type == .prevInfoPage ? .prev : .next,
                    from: chapter,
                    to: to
                ))
            }
        }
    }
}
