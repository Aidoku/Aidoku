//
//  MangaCollectionViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

class MangaCollectionViewController: UIViewController {

    enum MangaCellBadgeType {
        case none
        case unread
        case downloaded
    }

    var collectionView: UICollectionView?
    var manga: [Manga] = []

    var chapters: [String: [Chapter]] = [:]
    var readHistory: [String: [String: Int]] = [:]
    var badges: [String: Int] = [:]

    var opensReaderView = false
    var preloadsChapters = false
    var badgeType: MangaCellBadgeType = .none {
        didSet {
            if badgeType == .none {
                badges = [:]
                for i in 0..<manga.count {
                    if let cell = collectionView?.cellForItem(at: IndexPath(row: i, section: 0)) as? MangaCoverCell {
                        cell.badgeNumber = nil
                    }
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let cellsPerRow: Int
        if UIDevice.current.userInterfaceIdiom == .pad {
            cellsPerRow = view.bounds.width > view.bounds.height ? 6 : 4
        } else {
            cellsPerRow = view.bounds.width > view.bounds.height ? 5 : 2
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: MangaGridFlowLayout(
            cellsPerRow: cellsPerRow,
            minimumInteritemSpacing: 12,
            minimumLineSpacing: 12,
            sectionInset: view.layoutMargins
        ))
        collectionView?.backgroundColor = .systemBackground
        collectionView?.delegate = self
        collectionView?.dataSource = self
        collectionView?.delaysContentTouches = false
        collectionView?.alwaysBounceVertical = true
        collectionView?.register(MangaCoverCell.self, forCellWithReuseIdentifier: "MangaCoverCell")
        collectionView?.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView ?? UICollectionView())

        collectionView?.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        collectionView?.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadChaptersAndHistory()
        navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
        navigationController?.tabBarController?.tabBar.tintColor = UITabBar.appearance().tintColor
    }

    override func viewLayoutMarginsDidChange() {
        if let layout = collectionView?.collectionViewLayout as? MangaGridFlowLayout {
            layout.sectionInset = UIEdgeInsets(top: 0, left: view.layoutMargins.left, bottom: 10, right: view.layoutMargins.right)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let cellsPerRow: Int
        if UIDevice.current.userInterfaceIdiom == .pad {
            cellsPerRow = size.width > size.height ? 6 : 4
        } else {
            cellsPerRow = size.width > size.height ? 5 : 2
        }

        collectionView?.collectionViewLayout = MangaGridFlowLayout(
            cellsPerRow: cellsPerRow,
            minimumInteritemSpacing: 12,
            minimumLineSpacing: 12,
            sectionInset: view.layoutMargins
        )
    }

    func getNextChapter(for manga: Manga) -> Chapter? {
        let id = readHistory[manga.id]?.max { a, b in a.value < b.value }?.key
        if let id = id {
            return chapters[manga.id]?.first { $0.id == id }
        }
        return chapters[manga.id]?.first
    }

    func loadChaptersAndHistory() {
        if opensReaderView {
            Task {
                for (i, m) in manga.enumerated() {
                    readHistory[m.id] = DataManager.shared.getReadHistory(manga: m)
                    chapters[m.id] = await DataManager.shared.getChapters(for: m)
                    if badgeType == .unread {
                        badges[m.id] = (chapters[m.id]?.count ?? 0) - (readHistory[m.id]?.count ?? 0)
                        if let cell = collectionView?.cellForItem(at: IndexPath(row: i, section: 0)) as? MangaCoverCell {
                            cell.badgeNumber = badges[m.id]
                        }
                    }
                }
            }
        } else if preloadsChapters || badgeType == .unread {
            Task {
                for (i, m) in manga.enumerated() {
                    chapters[m.id] = await DataManager.shared.getChapters(for: m)
                    if badgeType == .unread {
                        readHistory[m.id] = DataManager.shared.getReadHistory(manga: m)
                        badges[m.id] = (chapters[m.id]?.count ?? 0) - (readHistory[m.id]?.count ?? 0)
                        if let cell = collectionView?.cellForItem(at: IndexPath(row: i, section: 0)) as? MangaCoverCell {
                            cell.badgeNumber = badges[m.id]
                        }
                    }
                }
            }
        } else {
            chapters = [:]
            readHistory = [:]
        }
    }

    func reloadData() {
        Task { @MainActor in
            self.collectionView?.performBatchUpdates {
                self.collectionView?.reloadSections(IndexSet(integer: 0))
            }
        }
    }

    func openMangaView(for manga: Manga) {
        navigationController?.pushViewController(MangaViewController(manga: manga, chapters: chapters[manga.id] ?? []), animated: true)
    }
}

// MARK: - Collection View Data Source
extension MangaCollectionViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        manga.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MangaCoverCell", for: indexPath) as? MangaCoverCell
        if cell == nil {
            cell = MangaCoverCell(frame: .zero)
        }
        if manga.count > indexPath.row {
            cell?.manga = manga[indexPath.row]
            cell?.badgeNumber = badges[manga[indexPath.row].id]
        }
        return cell ?? UICollectionViewCell()
    }

}

// MARK: - Collection View Delegate
extension MangaCollectionViewController: UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard manga.count > indexPath.row else { return }
        let manga = manga[indexPath.row]
        if opensReaderView,
           let chapter = getNextChapter(for: manga),
           SourceManager.shared.source(for: manga.sourceId) != nil {
            let readerController = ReaderViewController(manga: manga, chapter: chapter, chapterList: chapters[manga.id] ?? [])
            let navigationController = ReaderNavigationController(rootViewController: readerController)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        } else {
            openMangaView(for: self.manga[indexPath.row])
        }
    }

    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaCoverCell {
            cell.highlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaCoverCell {
            cell.unhighlight(animated: true)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            var actions: [UIAction] = []
            if DataManager.shared.libraryContains(manga: self.manga[indexPath.row]) {
                actions.append(UIAction(title: "Remove from Library", image: UIImage(systemName: "trash")) { _ in
                    DataManager.shared.delete(manga: self.manga[indexPath.row])
                })
            } else {
                actions.append(UIAction(title: "Add to Library", image: UIImage(systemName: "books.vertical.fill")) { _ in
                    Task { @MainActor in
                        let manga = self.manga[indexPath.row]
                        if let newManga = try? await SourceManager.shared.source(for: manga.sourceId)?.getMangaDetails(manga: manga) {
                            _ = DataManager.shared.addToLibrary(manga: newManga)
                        }
                    }
                })
            }
            if self.opensReaderView {
                actions.append(UIAction(title: "Manga Info", image: UIImage(systemName: "info.circle")) { _ in
                    self.openMangaView(for: self.manga[indexPath.row])
                })
            }
            return UIMenu(title: "", children: actions)
        }
    }
}
