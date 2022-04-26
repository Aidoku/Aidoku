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
            manga = sortManga(unfilteredManga)
            Task { @MainActor in
                self.emptyTextStackView.isHidden = !self.unfilteredManga.isEmpty || !self.unfilteredPinnedManga.isEmpty
                self.collectionView?.alwaysBounceVertical = !self.unfilteredManga.isEmpty || !self.unfilteredPinnedManga.isEmpty
            }
        }
    }

    var unfilteredPinnedManga: [Manga] = [] {
        didSet {
            pinnedManga = sortManga(unfilteredPinnedManga)
            Task { @MainActor in
                self.emptyTextStackView.isHidden = !self.unfilteredManga.isEmpty || !self.unfilteredPinnedManga.isEmpty
                self.collectionView?.alwaysBounceVertical = !self.unfilteredManga.isEmpty || !self.unfilteredPinnedManga.isEmpty
            }
        }
    }

//    override var manga: [Manga] {
//        get {
//            sortManga(unfilteredManga)
//        }
//        set {
//            unfilteredManga = newValue
//        }
//    }
//
//    override var pinnedManga: [Manga] {
//        get {
//            sortManga(unfilteredPinnedManga)
//        }
//        set {
//            unfilteredPinnedManga = newValue
//        }
//    }

    // 0 = title, 1 = last opened, 2 = last read, 3 = latest chapter, 4 = date added
    var sortOption = UserDefaults.standard.integer(forKey: "Library.sortOption") {
        didSet {
            UserDefaults.standard.set(sortOption, forKey: "Library.sortOption")
        }
    }
    var sortAscending = UserDefaults.standard.bool(forKey: "Library.sortAscending") {
        didSet {
            UserDefaults.standard.set(sortAscending, forKey: "Library.sortAscending")
        }
    }

    var readHistory: [String: [String: Int]] = [:]
    var opensReaderView = false
    var preloadsChapters = false

    var searchText: String = ""
    var updatedLibrary = false

    let emptyTextStackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("LIBRARY", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        let filterImage: UIImage?
        if #available(iOS 15.0, *) {
            filterImage = UIImage(systemName: "line.3.horizontal.decrease")
        } else {
            filterImage = UIImage(systemName: "line.horizontal.3.decrease")
        }
        let filterButton = UIBarButtonItem(image: filterImage, style: .plain, target: self, action: nil)
        navigationItem.rightBarButtonItem = filterButton
        updateSortMenu()

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("LIBRARY_SEARCH", comment: "")
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
        emptyTitleLabel.text = NSLocalizedString("LIBRARY_EMPTY", comment: "")
        emptyTitleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        emptyTitleLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTitleLabel)

        let emptyTextLabel = UILabel()
        emptyTextLabel.text = NSLocalizedString("LIBRARY_ADD_FROM_BROWSE", comment: "")
        emptyTextLabel.font = .systemFont(ofSize: 15)
        emptyTextLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTextLabel)

        emptyTextStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyTextStackView)

        emptyTextStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        emptyTextStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        fetchLibrary()

        NotificationCenter.default.addObserver(forName: Notification.Name("Library.pinManga"), object: nil, queue: nil) { _ in
            self.fetchLibrary()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("Library.pinMangaType"), object: nil, queue: nil) { _ in
            self.fetchLibrary()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("reloadLibrary"), object: nil, queue: nil) { _ in
            self.fetchLibrary()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("resortLibrary"), object: nil, queue: nil) { _ in
            self.resortManga()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("updateLibrary"), object: nil, queue: nil) { _ in
            self.refreshManga()
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

    func toggleSort(_ option: Int) {
        if sortOption == option {
            sortAscending.toggle()
        } else {
            sortOption = option
            sortAscending = false
        }
        resortManga()
        updateSortMenu()
    }

    func updateSortMenu() {
        let chevronIcon = UIImage(systemName: sortAscending ? "chevron.up" : "chevron.down")
        navigationItem.rightBarButtonItem?.menu = UIMenu(title: NSLocalizedString("SORT_BY", comment: ""), children: [
            UIAction(title: NSLocalizedString("TITLE", comment: ""), image: sortOption == 0 ? chevronIcon : nil) { _ in
                self.toggleSort(0)
            },
            UIAction(title: NSLocalizedString("LAST_OPENED", comment: ""), image: sortOption == 1 ? chevronIcon : nil) { _ in
                self.toggleSort(1)
            },
            UIAction(title: NSLocalizedString("LAST_READ", comment: ""), image: sortOption == 2 ? chevronIcon : nil) { _ in
                self.toggleSort(2)
            },
            UIAction(title: NSLocalizedString("LATEST_CHAPTER", comment: ""), image: sortOption == 3 ? chevronIcon : nil) { _ in
                self.toggleSort(3)
            },
            UIAction(title: NSLocalizedString("DATE_ADDED", comment: ""), image: sortOption == 4 ? chevronIcon : nil) { _ in
                self.toggleSort(4)
            }
        ])
    }

    func sortManga(_ manga: [Manga]) -> [Manga] {
        let filtered = manga.filter { searchText.isEmpty ? true : $0.title?.lowercased().contains(searchText.lowercased()) ?? true }
        if sortOption == 0 { // title
            return filtered
                .sorted(by: sortAscending ? { $0.title ?? "" > $1.title ?? "" }
                                          : { $0.title ?? "" < $1.title ?? "" })
        } else if sortOption == 1 { // last opened
            return filtered
                .sorted(by: sortAscending ? { $0.lastOpened ?? Date.distantPast < $1.lastOpened ?? Date.distantPast }
                                          : { $0.lastOpened ?? Date.distantPast > $1.lastOpened ?? Date.distantPast })
        } else if sortOption == 2 { // last read
            return filtered
                .sorted(by: sortAscending ? { $0.lastRead ?? Date.distantPast < $1.lastRead ?? Date.distantPast }
                                          : { $0.lastRead ?? Date.distantPast > $1.lastRead ?? Date.distantPast })
        } else if sortOption == 3 { // latest chapter
            return filtered
                .sorted(by: sortAscending ? { $0.lastUpdated ?? Date.distantPast < $1.lastUpdated ?? Date.distantPast }
                                          : { $0.lastUpdated ?? Date.distantPast > $1.lastUpdated ?? Date.distantPast })
        } else if sortOption == 4 { // date added
            return filtered
                .sorted(by: sortAscending ? { $0.dateAdded ?? Date.distantPast < $1.dateAdded ?? Date.distantPast }
                                          : { $0.dateAdded ?? Date.distantPast > $1.dateAdded ?? Date.distantPast })
        } else {
            return filtered
        }
    }

    func reorder(manga newManga: [Manga], from oldManga: [Manga] = [], in section: Int) {
        collectionView?.performBatchUpdates {
            for (i, manga) in oldManga.enumerated() {
                let from = IndexPath(row: i, section: section)
                if let cell = collectionView?.cellForItem(at: from) as? MangaCoverCell {
                    cell.badgeNumber = badges["\(manga.sourceId).\(manga.id)"]
                }
                if let j = newManga.firstIndex(where: { $0.sourceId == manga.sourceId && $0.id == manga.id }),
                   j != i {
                    let to = IndexPath(row: j, section: section)
                    self.collectionView?.moveItem(at: from, to: to)
                }
            }
        }
    }

    func refreshManga() {
        let previousManga = manga
        let previousPinnedManga = pinnedManga

        Task { @MainActor in
            await loadChaptersAndHistory()
            reorderManga(previousManga: previousManga, previousPinnedManga: previousPinnedManga)
        }
    }

    func resortManga() {
        let previousManga = manga
        let previousPinnedManga = pinnedManga

        manga = sortManga(unfilteredManga)
        pinnedManga = sortManga(unfilteredPinnedManga)

        reorderManga(previousManga: previousManga, previousPinnedManga: previousPinnedManga)
    }

    func reorderManga(previousManga: [Manga], previousPinnedManga: [Manga]) {
        var reordered = false

        let newManga = manga
        let newPinnedManga = pinnedManga

        if collectionView?.numberOfSections == 1 && !newPinnedManga.isEmpty { // insert pinned section
            collectionView?.performBatchUpdates {
                self.collectionView?.insertSections(IndexSet(integer: 0))
            }
        } else if collectionView?.numberOfSections == 2 && newPinnedManga.isEmpty { // remove pinned section
            collectionView?.performBatchUpdates {
                self.collectionView?.deleteSections(IndexSet(integer: 0))
            }
        }

        if !newPinnedManga.isEmpty && newPinnedManga.count == previousPinnedManga.count {
            reorder(manga: newPinnedManga, from: previousPinnedManga, in: 0)
            reordered = true
        }

        if !newManga.isEmpty && newManga.count == previousManga.count { // reorder
            reorder(manga: newManga, from: previousManga, in: newPinnedManga.isEmpty ? 0 : 1)
            reordered = true
        }

        if !reordered {
            collectionView?.performBatchUpdates {
                if collectionView?.numberOfSections == 1 {
                    collectionView?.reloadSections(IndexSet(integer: 0))
                } else {
                    collectionView?.reloadSections(IndexSet(integersIn: 0...1))
                }
            }
        }
    }

    func fetchLibrary() {
        Task {
            await loadChaptersAndHistory()
            reloadData()
        }
    }

    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl) {
        Task {
            await DataManager.shared.updateLibrary()
            refreshControl.endRefreshing()
        }
    }

    func loadChaptersAndHistory() async {
        var tempManga: [Manga] = []
        var tempPinnedManga: [Manga] = []

        if opensReaderView || preloadsChapters || badgeType == .unread {
            for m in DataManager.shared.libraryManga {
                let mangaId = "\(m.sourceId).\(m.id)"

                if opensReaderView {
                    readHistory[mangaId] = DataManager.shared.getReadHistory(manga: m)
                }

                chapters[mangaId] = await DataManager.shared.getChapters(for: m)

                if badgeType == .unread {
                    if !opensReaderView && preloadsChapters {
                        readHistory[mangaId] = DataManager.shared.getReadHistory(manga: m)
                    }

                    var ids = (chapters[mangaId] ?? []).map { $0.id }
                    ids.removeAll { readHistory[mangaId]?.keys.contains($0) ?? false }

                    let badgeNum = ids.count
                    badges[mangaId] = badgeNum

                    let pinManga = UserDefaults.standard.bool(forKey: "Library.pinManga")
                    let pinType = UserDefaults.standard.integer(forKey: "Library.pinMangaType")

                    if badgeNum > 0 && pinManga
                        && (pinType == 0 || (pinType == 1 && m.lastUpdated ?? Date.distantPast > m.lastOpened ?? Date.distantPast)) {
                        tempPinnedManga.append(m)
                    } else if pinManga && pinType == 1 && m.lastUpdated ?? Date.distantPast > m.lastOpened ?? Date.distantFuture {
                        tempPinnedManga.append(m)
                    } else {
                        tempManga.append(m)
                    }
                }
            }
        } else {
            chapters = [:]
            readHistory = [:]
        }

        unfilteredManga = tempManga
        unfilteredPinnedManga = tempPinnedManga

        manga = sortManga(unfilteredManga)
        pinnedManga = sortManga(unfilteredPinnedManga)
    }

    func getNextChapter(for manga: Manga) -> Chapter? {
        let mangaId = "\(manga.sourceId).\(manga.id)"
        let id = readHistory[mangaId]?.max { a, b in a.value < b.value }?.key
        if let id = id {
            return chapters[mangaId]?.first { $0.id == id }
        }
        return chapters[mangaId]?.last
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
//        if indexPath.section == 0 && pinnedManga.count > indexPath.row {
//            openMangaView(for: pinnedManga[indexPath.row])
//        } else {
//            if manga.count > indexPath.row {
//                openMangaView(for: manga[indexPath.row])
//            }
//        }

        let targetManga: Manga
        if indexPath.section == 0 && !pinnedManga.isEmpty {
            guard pinnedManga.count > indexPath.row else { return }
            targetManga = pinnedManga[indexPath.row]
        } else {
            guard manga.count > indexPath.row else { return }
            targetManga = manga[indexPath.row]
        }
        if opensReaderView,
           let chapter = getNextChapter(for: targetManga),
           SourceManager.shared.source(for: targetManga.sourceId) != nil {
            let readerController = ReaderViewController(
                manga: targetManga,
                chapter: chapter,
                chapterList: chapters["\(targetManga.sourceId).\(targetManga.id)"] ?? []
            )
            let navigationController = ReaderNavigationController(rootViewController: readerController)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        } else {
            openMangaView(for: targetManga)
        }
        DataManager.shared.setOpened(manga: targetManga)
    }

    override func collectionView(
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
            if self.opensReaderView {
                actions.append(UIAction(title: NSLocalizedString("MANGA_INFO", comment: ""), image: UIImage(systemName: "info.circle")) { _ in
                    self.openMangaView(for: targetManga)
                })
            }
            return UIMenu(title: "", children: actions)
        }
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
