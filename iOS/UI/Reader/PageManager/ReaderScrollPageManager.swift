//
//  ReaderScrollPageManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/15/22.
//

import UIKit
import Kingfisher

class ReaderScrollPageManager: NSObject, ReaderPageManager {

    weak var delegate: ReaderPageManagerDelegate?

    var chapter: Chapter?
    var readingMode: MangaViewer?
    var pages: [Page] = []

    var collectionView: UICollectionView!

    var urls: [String] = []
    var pageViews: [String: ReaderPageView] = [:]
    var sizeCache: [String: CGSize] = [:]

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
        pageViews.removeAll()
        sizeCache.removeAll()
        collectionView.removeFromSuperview()
        collectionView = nil
    }

    func setChapter(chapter: Chapter, startPage: Int) {
        guard collectionView != nil else { return }

        self.chapter = chapter

        Task { @MainActor in
            await loadPages()
            if collectionView != nil {
                collectionView.reloadData()
            }
        }
    }

    func move(toPage page: Int) {
    }

    func loadPages() async {
        guard let chapter = chapter else { return }
        pages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
        urls = pages.map { $0.imageURL ?? "" }
    }
}

extension ReaderScrollPageManager: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {

        if let key = pageViews[urls[indexPath.item]]?.cacheKey,
           let size = sizeCache[key] {
            return size
        }

        return collectionView.frame.size
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // did change page
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // TODO: infinite scrolling
        // https://stackoverflow.com/questions/35938580/making-a-uicollectionview-continuously-scroll
    }
}

extension UIImage {
    func sizeFit(_ pageSize: CGSize) -> CGSize {
        guard size.height * size.width * pageSize.width * pageSize.height > 0 else { return .zero }

        let scaledHeight = size.height * (pageSize.width / size.width)
        return CGSize(width: pageSize.width, height: scaledHeight)
    }
}

extension ReaderScrollPageManager: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        urls.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "ReaderPageCollectionViewCell",
            for: indexPath
        ) as? ReaderPageCollectionViewCell

        if cell == nil {
            cell = ReaderPageCollectionViewCell(frame: .zero)
        }

        if let pageView = cell?.pageView {
            pageViews[urls[indexPath.item]] = pageView
        }

        cell?.pageView.delegate = self
        cell?.setPageImage(url: urls[indexPath.item])

        return cell ?? UICollectionViewCell()
    }
}

extension ReaderScrollPageManager: ReaderPageViewDelegate {

    func imageLoaded(result: Result<RetrieveImageResult, KingfisherError>) {
        switch result {
        case .success(let imageResult):
            let key = imageResult.source.cacheKey
            if sizeCache[key] == nil {
                sizeCache[key] = imageResult.image.sizeFit(collectionView.frame.size)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.collectionView.collectionViewLayout.invalidateLayout()
                }
            }
        case .failure:
            break
        }
    }
}

// MARK: - Reader Page Collection Cell
class ReaderPageCollectionViewCell: UICollectionViewCell {

    let imageView = UIImageView()
    let pageView = ReaderPageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutViews() {
//        imageView.frame = UIScreen.main.bounds
//        imageView.contentMode = .scaleAspectFit
//        imageView.backgroundColor = .red
//        imageView.translatesAutoresizingMaskIntoConstraints = false
//        addSubview(imageView)

        pageView.zoomEnabled = false
        pageView.imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageView.imageView)

        pageView.imageView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        pageView.imageView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        pageView.imageView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        pageView.imageView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    func setPageImage(url: String) {
        Task {
            await pageView.setPageImage(url: url)
        }
    }
}
