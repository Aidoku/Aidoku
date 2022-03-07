//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/29/22.
//

import UIKit

class LibraryViewController: MangaCollectionViewController {

    var unfilteredManga: [Manga] = [] {
        didSet {
            Task { @MainActor in
                self.emptyTextStackView.isHidden = !self.unfilteredManga.isEmpty
                self.collectionView?.alwaysBounceVertical = !self.unfilteredManga.isEmpty
            }
        }
    }

    override var manga: [Manga] {
        get {
            unfilteredManga.filter { searchText.isEmpty ? true : $0.title?.lowercased().contains(searchText.lowercased()) ?? true }
        }
        set {
            unfilteredManga = newValue
        }
    }

    var searchText: String = ""
    var updatedLibrary = false

    let emptyTextStackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Library"

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Find in Library"
        navigationItem.searchController = searchController

        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        preloadsChapters = true
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

//        collectionView?.register(MangaListSelectionHeader.self,
//                                 forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
//                                 withReuseIdentifier: "MangaListSelectionHeader")

        emptyTextStackView.isHidden = true
        emptyTextStackView.axis = .vertical
        emptyTextStackView.distribution = .equalSpacing
        emptyTextStackView.spacing = 5
        emptyTextStackView.alignment = .center

        let emptyTitleLabel = UILabel()
        emptyTitleLabel.text = "Library Empty"
        emptyTitleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        emptyTitleLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTitleLabel)

        let emptyTextLabel = UILabel()
        emptyTextLabel.text = "Add manga from the browse tab"
        emptyTextLabel.font = .systemFont(ofSize: 15)
        emptyTextLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTextLabel)

        emptyTextStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyTextStackView)

        emptyTextStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        emptyTextStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        fetchLibrary()

        NotificationCenter.default.addObserver(forName: Notification.Name("updateLibrary"), object: nil, queue: nil) { _ in
            let previousManga = self.manga
            self.manga = DataManager.shared.libraryManga
            if !self.manga.isEmpty && self.manga.count == previousManga.count { // reorder
                Task { @MainActor in
                    self.collectionView?.performBatchUpdates {
                        for (i, manga) in previousManga.enumerated() {
                            let from = IndexPath(row: i, section: 0)
                            if let j = self.manga.firstIndex(where: { $0.sourceId == manga.sourceId && $0.id == manga.id }) {
                                let to = IndexPath(row: j, section: 0)
                                self.collectionView?.moveItem(at: from, to: to)
                            }
                        }
                    }
                }
            } else { // reload
                Task { @MainActor in
                    self.collectionView?.reloadData()
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

        super.viewWillAppear(animated)

        if !updatedLibrary {
            updatedLibrary = true
            Task {
                await DataManager.shared.updateLibrary()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh), for: .valueChanged)
        collectionView?.refreshControl = refreshControl

        navigationItem.hidesSearchBarWhenScrolling = true
    }

    func fetchLibrary() {
        manga = DataManager.shared.libraryManga
        reloadData()
    }

    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl) {
        Task {
            await DataManager.shared.updateLibrary()
            refreshControl.endRefreshing()
        }
    }
}

extension LibraryViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // unfortunately only gets called for a swipe to dismiss
        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none
        loadChaptersAndHistory()
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController: UICollectionViewDelegateFlowLayout {

//    func collectionView(_ collectionView: UICollectionView,
//                        layout collectionViewLayout: UICollectionViewLayout,
//                        referenceSizeForHeaderInSection section: Int) -> CGSize {
//        CGSize(width: collectionView.bounds.width, height: 40)
//    }
//
//    func collectionView(_ collectionView: UICollectionView,
//                        viewForSupplementaryElementOfKind kind: String,
//                        at indexPath: IndexPath) -> UICollectionReusableView {
//        if kind == UICollectionView.elementKindSectionHeader {
//            var header = collectionView.dequeueReusableSupplementaryView(
//                ofKind: kind,
//                withReuseIdentifier: "MangaListSelectionHeader",
//                for: indexPath
//            ) as? MangaListSelectionHeader
//            if header == nil {
//                header = MangaListSelectionHeader(frame: .zero)
//            }
//            header?.delegate = nil
//            header?.options = ["Default"]
//            header?.selectedOption = 0
//            header?.delegate = self
//            return header ?? UICollectionReusableView()
//        }
//        return UICollectionReusableView()
//    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didSelectItemAt: indexPath)
        DataManager.shared.setOpened(manga: manga[indexPath.row])
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: MangaListSelectionHeaderDelegate {
    func optionSelected(_ index: Int) {
        fetchLibrary()
    }
}

// MARK: - Search Results Updater
extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        collectionView?.reloadData()
    }
}
