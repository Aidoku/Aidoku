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

    var chapter: Chapter?
    var readingMode: MangaViewer?
    var pages: [Page] = []

    var collectionView: UICollectionView!

    var urls: [String] = []
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

    var previousPageIndex = 0

    var currentIndex: Int {
        let offset = CGPoint(x: 0, y: collectionView.contentOffset.y + 100)
        if let path = collectionView.indexPathForItem(at: offset) {
            return path.item
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

        parent.view.addSubview(collectionView)

        collectionView.topAnchor.constraint(equalTo: parent.view.topAnchor).isActive = true
        collectionView.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor).isActive = true
        collectionView.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor).isActive = true
        collectionView.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor).isActive = true
    }

    func remove() {
        guard collectionView != nil else { return }
        urls.removeAll()
        sizeCache.removeAll()
        collectionView.removeFromSuperview()
        collectionView = nil
    }

    func setChapter(chapter: Chapter, startPage: Int) {
        guard collectionView != nil else { return }

        self.chapter = chapter
        targetPage = startPage

        Task { @MainActor in
            await loadPages()
            setImages(for: 0..<startPage+1)
            if collectionView != nil {
                collectionView.reloadData()
            }
        }
    }

    func move(toPage page: Int) {
        collectionView.scrollToItem(at: IndexPath(item: page + 1, section: 0), at: .top, animated: false)
        delegate?.didMove(toPage: page)
    }

    func loadPages() async {
        guard let chapter = chapter else { return }
        pages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
        urls = pages.map { $0.imageURL ?? "" }
        delegate?.pagesLoaded()

        if chapterList.isEmpty {
            if let chapters = delegate?.chapterList, !chapters.isEmpty {
                chapterList = chapters
            } else {
                chapterList = await DataManager.shared.getChapters(from: chapter.sourceId, for: chapter.mangaId)
            }
        }
        if let chapterIndex = chapterList.firstIndex(of: chapter) {
            hasPreviousChapter = chapterIndex != chapterList.count - 1
            hasNextChapter = chapterIndex != 0
        } else {
            hasPreviousChapter = false
            hasNextChapter = false
        }
    }

    func setImages(for range: Range<Int>) {
        for i in range {
            guard i < urls.count else { break }
            if i < 0 {
                continue
            }
            let path = IndexPath(item: i + 1, section: 0)
            (collectionView(collectionView, cellForItemAt: path) as? ReaderPageCollectionViewCell)?.setPageImage(url: urls[i])
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

        if indexPath.item == 0 || indexPath.item >= urls.count + 1 {
            return CGSize(width: collectionView.frame.size.width, height: 300)
        }

        if let size = sizeCache[urls[indexPath.item - 1]] {
            lastSize = size
            return size
        } else if let size = lastSize {
            return size
        }

        return CGSize(width: collectionView.frame.size.width, height: 100) // collectionView.frame.size
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let newPageIndex = currentIndex - 1
        if previousPageIndex != newPageIndex {
            previousPageIndex = newPageIndex
            delegate?.didMove(toPage: newPageIndex)
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item == 0 || indexPath.item >= urls.count + 1 { return }

        if let cell = cell as? ReaderPageCollectionViewCell {
            cell.setPageImage(url: urls[indexPath.item - 1])
        }

        // TODO: infinite scrolling
        // https://stackoverflow.com/questions/35938580/making-a-uicollectionview-continuously-scroll
    }
}

// MARK: - Collection View Data Source
extension ReaderScrollPageManager: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        urls.isEmpty ? 0 : urls.count + 2
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "ReaderPageCollectionViewCell",
            for: indexPath
        )

        if let chapter = chapter, let cell = cell as? ReaderPageCollectionViewCell {
            if indexPath.item == 0 {
                cell.convertToInfo(type: .previous, currentChapter: chapter)
                if hasPreviousChapter {
                    cell.infoView?.previousChapter = chapterList[chapterIndex + 1]
                }
            } else if indexPath.item >= urls.count + 1 {
                cell.convertToInfo(type: .next, currentChapter: chapter)
                if hasNextChapter {
                    cell.infoView?.nextChapter = chapterList[chapterIndex - 1]
                }
            } else {
                cell.convertToPage()
                cell.pageView?.delegate = self
            }
        }

        return cell
    }
}

// MARK: - Collection View Prefetching
extension ReaderScrollPageManager: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.compactMap { path -> URL? in
            guard path.item > 0 && path.item < self.urls.count + 1 else { return nil }
            return URL(string: self.urls[path.item - 1])
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
                if let targetPage = targetPage, sizeCache.count >= targetPage {
                    move(toPage: targetPage)
                    self.targetPage = nil
                }
            }
        case .failure:
            break
        }
    }
}

// MARK: - Reader Page Collection Cell
class ReaderPageCollectionViewCell: UICollectionViewCell {

    var pageView: ReaderPageView?
    var infoView: ReaderInfoPageView?

    func convertToPage() {
        guard pageView == nil else { return }

        infoView?.removeFromSuperview()
        infoView = nil

        pageView = ReaderPageView()
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
        Task {
            await pageView?.setPageImage(url: url)
        }
    }
}
