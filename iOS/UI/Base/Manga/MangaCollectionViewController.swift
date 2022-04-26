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
    var pinnedManga: [Manga] = []

    var chapters: [String: [Chapter]] = [:]
    var badges: [String: Int] = [:]

    var cellsPerRow: Int {
        UserDefaults.standard.integer(
            forKey: view.bounds.width > view.bounds.height ? "General.landscapeRows" : "General.portraitRows"
        )
    }

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

        collectionView?.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        collectionView?.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        collectionView?.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        collectionView?.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        NotificationCenter.default.addObserver(forName: Notification.Name("General.portraitRows"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                (self.collectionView?.collectionViewLayout as? MangaGridFlowLayout)?.cellsPerRow = self.cellsPerRow
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("General.landscapeRows"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                (self.collectionView?.collectionViewLayout as? MangaGridFlowLayout)?.cellsPerRow = self.cellsPerRow
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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

        let cellsPerRow = UserDefaults.standard.integer(
            forKey: size.width > size.height ? "General.landscapeRows" : "General.portraitRows"
        )

        collectionView?.collectionViewLayout = MangaGridFlowLayout(
            cellsPerRow: cellsPerRow,
            minimumInteritemSpacing: 12,
            minimumLineSpacing: 12,
            sectionInset: view.layoutMargins
        )
    }

    func reloadData() {
        Task { @MainActor in
            if collectionView?.numberOfSections == 1 && !pinnedManga.isEmpty { // insert pinned section
                collectionView?.performBatchUpdates {
                    collectionView?.insertSections(IndexSet(integer: 0))
                }
            } else if collectionView?.numberOfSections == 2 && pinnedManga.isEmpty { // remove pinned section
                collectionView?.performBatchUpdates {
                    collectionView?.deleteSections(IndexSet(integer: 0))
                }
            } else { // reload all sections
                collectionView?.performBatchUpdates {
                    if collectionView?.numberOfSections == 1 {
                        collectionView?.reloadSections(IndexSet(integer: 0))
                    } else {
                        collectionView?.reloadSections(IndexSet(integersIn: 0...1))
                    }
                }
            }
        }
    }

    func openMangaView(for manga: Manga) {
        let vc = MangaViewController(manga: manga, chapters: chapters["\(manga.sourceId).\(manga.id)"] ?? [])
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - Collection View Data Source
extension MangaCollectionViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 && !pinnedManga.isEmpty ? pinnedManga.count : manga.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MangaCoverCell", for: indexPath) as? MangaCoverCell
        if cell == nil {
            cell = MangaCoverCell(frame: .zero)
        }
        if indexPath.section == 0 && pinnedManga.count > indexPath.row || manga.count > indexPath.row {
            let targetManga = indexPath.section == 0 && pinnedManga.count > indexPath.row ? pinnedManga[indexPath.row] : manga[indexPath.row]
            cell?.manga = targetManga
            cell?.badgeNumber = badges["\(targetManga.sourceId).\(targetManga.id)"]
        }
        return cell ?? UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.section == 0 && pinnedManga.count > indexPath.row || manga.count > indexPath.row {
            let targetManga = indexPath.section == 0 && pinnedManga.count > indexPath.row ? pinnedManga[indexPath.row] : manga[indexPath.row]
            (cell as? MangaCoverCell)?.badgeNumber = badges["\(targetManga.sourceId).\(targetManga.id)"]
        }
    }
}

// MARK: - Collection View Delegate
extension MangaCollectionViewController: UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        pinnedManga.isEmpty ? 1 : 2
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == 0 && pinnedManga.count > indexPath.row {
            openMangaView(for: pinnedManga[indexPath.row])
        } else {
            if manga.count > indexPath.row {
                openMangaView(for: manga[indexPath.row])
            }
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
        let targetManga: Manga
        if indexPath.section == 0 && !pinnedManga.isEmpty {
            guard pinnedManga.count > indexPath.row else { return nil }
            targetManga = pinnedManga[indexPath.row]
        } else {
            guard manga.count > indexPath.row else { return nil }
            targetManga = manga[indexPath.row]
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            var actions: [UIAction] = []

            if DataManager.shared.libraryContains(manga: targetManga) {
                actions.append(UIAction(title: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: ""),
                                        image: UIImage(systemName: "trash")) { _ in
                    DataManager.shared.delete(manga: targetManga)
                })
            } else {
                actions.append(UIAction(title: NSLocalizedString("ADD_TO_LIBRARY", comment: ""),
                                        image: UIImage(systemName: "books.vertical.fill")) { _ in
                    Task { @MainActor in
                        if let newManga = try? await SourceManager.shared.source(for: targetManga.sourceId)?.getMangaDetails(manga: targetManga) {
                            _ = DataManager.shared.addToLibrary(manga: newManga)
                        }
                    }
                })
            }
            return UIMenu(title: "", children: actions)
        }
    }
}
