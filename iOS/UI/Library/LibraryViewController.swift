//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/29/22.
//

import UIKit
import LocalAuthentication

class LibraryViewController: MangaCollectionViewController {

    var unfilteredManga: [Manga] = [] {
        didSet {
            manga = sortManga(unfilteredManga)
            Task { @MainActor in
                emptyTextStackView.isHidden = !unfilteredManga.isEmpty || !unfilteredPinnedManga.isEmpty
                collectionView.isScrollEnabled = emptyTextStackView.isHidden && !locked
            }
        }
    }

    var unfilteredPinnedManga: [Manga] = [] {
        didSet {
            pinnedManga = sortManga(unfilteredPinnedManga)
            Task { @MainActor in
                emptyTextStackView.isHidden = !unfilteredManga.isEmpty || !unfilteredPinnedManga.isEmpty
                collectionView.isScrollEnabled = emptyTextStackView.isHidden && !locked
            }
        }
    }

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

    struct LibraryFilter {
        var name: String
        var exclude: Bool = false
    }

    var filters: [LibraryFilter] = []

    var categories: [String] = []
    var currentCategory: String? = UserDefaults.standard.string(forKey: "Library.currentCategory") {
        didSet {
            UserDefaults.standard.set(currentCategory, forKey: "Library.currentCategory")
            if currentCategory == nil {
                lockedText.text = NSLocalizedString("LIBRARY_LOCKED", comment: "")
                emptyTitleLabel.text = NSLocalizedString("LIBRARY_EMPTY", comment: "")
            } else {
                lockedText.text = NSLocalizedString("CATEGORY_LOCKED", comment: "")
                emptyTitleLabel.text = NSLocalizedString("CATEGORY_EMPTY", comment: "")
            }
        }
    }

    var readHistory: [String: [String: (Int, Int)]] = [:]
    var opensReaderView = false
    var preloadsChapters = false

    var searchText: String = ""

    var queueFetchLibrary = false
    var locked = false

    var filterButton: UIBarButtonItem?

    let refreshControl = UIRefreshControl()

    let emptyTextStackView = UIStackView()
    let emptyTitleLabel = UILabel()

    let lockedView = UIStackView()
    let lockedImageView = UIImageView()
    let lockedText = UILabel()
    let lockedButton = UIButton(type: .roundedRect)

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("LIBRARY", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        view.backgroundColor = .systemBackground

        Task {
            await updateNavbarButtons()
            updateSortMenu()
        }

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("LIBRARY_SEARCH", comment: "")
        navigationItem.searchController = searchController

        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        preloadsChapters = true
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

        collectionView?.register(
            MangaListSelectionHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: "MangaListSelectionHeader"
        )

        // Library Empty text
        emptyTextStackView.isHidden = true
        emptyTextStackView.axis = .vertical
        emptyTextStackView.distribution = .equalSpacing
        emptyTextStackView.spacing = 5
        emptyTextStackView.alignment = .center

        emptyTitleLabel.text = currentCategory == nil
            ? NSLocalizedString("LIBRARY_EMPTY", comment: "")
            : NSLocalizedString("CATEGORY_EMPTY", comment: "")
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

        // locked category text
        lockedView.distribution = .fill
        lockedView.spacing = 12
        lockedView.alignment = .center
        lockedView.axis = .vertical
        lockedView.translatesAutoresizingMaskIntoConstraints = false
        lockedView.isHidden = true
        view.addSubview(lockedView)

        lockedImageView.image = UIImage(systemName: "lock.fill")
        lockedImageView.contentMode = .scaleAspectFit
        lockedImageView.tintColor = .secondaryLabel
        lockedImageView.translatesAutoresizingMaskIntoConstraints = false
        lockedView.addArrangedSubview(lockedImageView)

        lockedText.text = currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED", comment: "")
            : NSLocalizedString("CATEGORY_LOCKED", comment: "")
        lockedText.font = .systemFont(ofSize: 16, weight: .medium)
        lockedView.addArrangedSubview(lockedText)
        lockedView.setCustomSpacing(2, after: lockedText)

        lockedButton.setTitle(NSLocalizedString("VIEW_LIBRARY", comment: ""), for: .normal)
        lockedButton.addTarget(self, action: #selector(unlock), for: .touchUpInside)
        lockedView.addArrangedSubview(lockedButton)

        lockedImageView.heightAnchor.constraint(equalToConstant: 66).isActive = true
        lockedImageView.widthAnchor.constraint(equalToConstant: 66).isActive = true
        lockedView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        lockedView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        let unlockTap = UITapGestureRecognizer(target: self, action: #selector(unlock))
        lockedView.addGestureRecognizer(unlockTap)

        categories = DataManager.shared.getCategories()

        updateLockState(reload: false)
        Task { @MainActor in
            await fetchLibrary()
            collectionView.reloadData()
        }

        // notification listeners
        let fetchLibraryBlock: (Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.fetchLibrary()
            }
        }
        let queueFetchLibraryBlock: (Notification) -> Void = { [weak self] _ in
            self?.queueFetchLibrary = true
        }
        let updateNavbarBlock: (Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.updateNavbarButtons()
            }
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("Library.pinManga"), object: nil, queue: nil, using: queueFetchLibraryBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("Library.pinMangaType"), object: nil, queue: nil, using: queueFetchLibraryBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateHistory"), object: nil, queue: nil, using: queueFetchLibraryBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("reloadLibrary"), object: nil, queue: nil, using: fetchLibraryBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("resortLibrary"), object: nil, queue: nil
        ) { [weak self] _ in
            self?.resortManga()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateLibrary"), object: nil, queue: nil
        ) { [weak self] _ in
            self?.refreshManga()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateLibraryLock"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateLockState(reload: false)
                await self.fetchLibrary()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateCategories"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.categories = DataManager.shared.getCategories()
            if self.currentCategory != nil && !self.categories.contains(self.currentCategory!) {
                self.currentCategory = nil
            }
            Task {
                self.updateLockState(reload: false)
                await self.fetchLibrary(hardReload: true)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadsQueued"), object: nil, queue: nil, using: updateNavbarBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadFinished"), object: nil, queue: nil, using: updateNavbarBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadCancelled"), object: nil, queue: nil, using: updateNavbarBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadsCancelled"), object: nil, queue: nil, using: updateNavbarBlock
        ))
        // lock when app moves to background
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.updateLockState()
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

        super.viewWillAppear(animated)

        if queueFetchLibrary {
            queueFetchLibrary = false
            Task {
                await fetchLibrary()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh), for: .valueChanged)
        collectionView?.refreshControl = refreshControl

        navigationItem.hidesSearchBarWhenScrolling = true
    }
}

extension LibraryViewController {
    @MainActor
    func updateNavbarButtons() async {
        var buttons: [UIBarButtonItem] = []

        if filterButton == nil {
            let filterImage: UIImage?
            if #available(iOS 15.0, *) {
                filterImage = UIImage(systemName: "line.3.horizontal.decrease")
            } else {
                filterImage = UIImage(systemName: "line.horizontal.3.decrease")
            }
            filterButton = UIBarButtonItem(image: filterImage, style: .plain, target: self, action: nil)
        }
        if categories.isEmpty {
            filterButton?.isEnabled = true
            buttons.append(filterButton!)
        }

        if await DownloadManager.shared.hasQueuedDownloads() {
            let downloadQueueButton = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.down"),
                style: .plain,
                target: self,
                action: #selector(openDownloadQueue)
            )
            buttons.append(downloadQueueButton)
        }

        if UserDefaults.standard.bool(forKey: "Library.lockLibrary")
            && (currentCategory == nil
                || (UserDefaults.standard.stringArray(forKey: "Library.lockedCategories") ?? []).contains(currentCategory!)) {
            let lockButton: UIBarButtonItem
            if locked {
                lockButton = UIBarButtonItem(
                    image: UIImage(systemName: "lock"),
                    style: .plain,
                    target: self,
                    action: #selector(unlock)
                )
                filterButton?.isEnabled = false
            } else {
                lockButton = UIBarButtonItem(
                    image: UIImage(systemName: "lock.open"),
                    style: .plain,
                    target: self,
                    action: #selector(lock)
                )
            }
            buttons.append(lockButton)
        }

        navigationItem.rightBarButtonItems = buttons
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

    func toggleFilter(_ name: String) {
        if let idx = filters.firstIndex(where: { $0.name == name }) {
            if filters[idx].exclude {
                filters.remove(at: idx)
            } else {
                filters[idx].exclude = true
            }
        } else {
            filters.append(LibraryFilter(name: name))
        }
        resortManga(reload: true)
        updateSortMenu()
    }

    func filterImage(for name: String) -> UIImage? {
        if let idx = filters.firstIndex(where: { $0.name == name }) {
            if filters[idx].exclude {
                return UIImage(systemName: "xmark")
            } else {
                return UIImage(systemName: "checkmark")
            }
        } else {
            return nil
        }
    }

    func updateSortMenu() {
        let chevronIcon = UIImage(systemName: sortAscending ? "chevron.up" : "chevron.down")
        let sortMenu = UIMenu(title: NSLocalizedString("SORT_BY", comment: ""), options: .displayInline, children: [
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
        let filterMenu = UIMenu(title: NSLocalizedString("FILTER_BY", comment: ""), options: .displayInline, children: [
            UIAction(title: NSLocalizedString("DOWNLOADED", comment: ""), image: filterImage(for: "downloaded")) { _ in
                self.toggleFilter("downloaded")
            }
        ])
        filterButton?.menu = UIMenu(title: "", children: [sortMenu, filterMenu])
        (collectionView?.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(row: 0, section: 0)
        ) as? MangaListSelectionHeader)?.filterButton.menu = filterButton?.menu
    }

    func sortManga(_ manga: [Manga]) -> [Manga] {
        var filtered = manga.filter { searchText.isEmpty ? true : $0.title?.lowercased().contains(searchText.lowercased()) ?? true }
        for filter in filters {
            switch filter.name {
            case "downloaded":
                filtered = manga.filter {
                    let downloaded = DownloadManager.shared.hasDownloadedChapter(for: $0)
                    return filter.exclude ? !downloaded : downloaded
                }
            default: break
            }
        }
        switch sortOption {
        case 0:
            return filtered
                .sorted(by: sortAscending ? { $0.title ?? "" > $1.title ?? "" }
                                          : { $0.title ?? "" < $1.title ?? "" })
        case 1:
            return filtered
                .sorted(by: sortAscending ? { $0.lastOpened ?? Date.distantPast < $1.lastOpened ?? Date.distantPast }
                                          : { $0.lastOpened ?? Date.distantPast > $1.lastOpened ?? Date.distantPast })
        case 2:
            return filtered
                .sorted(by: sortAscending ? { $0.lastRead ?? Date.distantPast < $1.lastRead ?? Date.distantPast }
                                          : { $0.lastRead ?? Date.distantPast > $1.lastRead ?? Date.distantPast })
        case 3:
            return filtered
                .sorted(by: sortAscending ? { $0.lastUpdated ?? Date.distantPast < $1.lastUpdated ?? Date.distantPast }
                                          : { $0.lastUpdated ?? Date.distantPast > $1.lastUpdated ?? Date.distantPast })
        case 4:
            return filtered
                .sorted(by: sortAscending ? { $0.dateAdded ?? Date.distantPast < $1.dateAdded ?? Date.distantPast }
                                          : { $0.dateAdded ?? Date.distantPast > $1.dateAdded ?? Date.distantPast })
        default:
            return filtered
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

    func resortManga(reload: Bool = false) {
        let previousManga = manga
        let previousPinnedManga = pinnedManga

        manga = sortManga(unfilteredManga)
        pinnedManga = sortManga(unfilteredPinnedManga)

        if reload {
            reloadData()
        } else {
            reorderManga(previousManga: previousManga, previousPinnedManga: previousPinnedManga)
        }
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

    func reorder(manga newManga: [Manga], from oldManga: [Manga] = [], in section: Int) {
        // FIXME: there's a crash here somehow
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

    func fetchLibrary(hardReload: Bool = false) async {
        await loadChaptersAndHistory()
        if hardReload {
            collectionView.reloadData()
        } else {
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

        let libraryManga = currentCategory == nil ? DataManager.shared.libraryManga : DataManager.shared.getManga(inCategory: currentCategory!)

        if opensReaderView || preloadsChapters || badgeType == .unread {
            for m in libraryManga {
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
                    ids.removeAll { readHistory[mangaId]?[$0]?.0 ?? 0 == -1 }

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
                } else {
                    tempManga.append(m)
                }
            }
        } else {
            chapters = [:]
            readHistory = [:]
            tempManga = libraryManga
        }

        unfilteredManga = tempManga
        unfilteredPinnedManga = tempPinnedManga

        manga = sortManga(unfilteredManga)
        pinnedManga = sortManga(unfilteredPinnedManga)
    }

    func getNextChapter(for manga: Manga) -> Chapter? {
        let mangaId = "\(manga.sourceId).\(manga.id)"
        let id = readHistory[mangaId]?.max { a, b in a.value.1 < b.value.1 }?.key
        if let id = id {
            return chapters[mangaId]?.first { $0.id == id }
        }
        return chapters[mangaId]?.last
    }

    func updateLockState(recheck: Bool = true, reload: Bool = true) {
        if recheck {
            if !UserDefaults.standard.bool(forKey: "Library.lockLibrary") {
                locked = false
            } else {
                locked = currentCategory == nil
                    || (UserDefaults.standard.stringArray(forKey: "Library.lockedCategories") ?? []).contains(currentCategory!)
            }
        }
        collectionView.isScrollEnabled = emptyTextStackView.isHidden && !locked
        if locked {
            collectionView.refreshControl = nil
            lockedView.isHidden = false
            lockedView.alpha = 1
            emptyTextStackView.alpha = 0
            if reload {
                collectionView.reloadData()
            }
        } else {
            collectionView.refreshControl = refreshControl
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.lockedView.alpha = 0
                self.emptyTextStackView.alpha = 1
            } completion: { _ in
                self.lockedView.isHidden = true
                if reload {
                    if self.collectionView.numberOfSections == 1 {
                        self.collectionView.reloadSections(IndexSet(integer: 0))
                    } else {
                        self.collectionView.reloadSections(IndexSet(integersIn: 0...1))
                    }
                }
            }
        }
        Task {
            await updateNavbarButtons()
        }
    }

    @objc func unlock() {
        let context = LAContext()

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            let reason = NSLocalizedString("AUTH_FOR_LIBRARY", comment: "")

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    if success {
                        self.locked = false
                        self.updateLockState(recheck: false)
                    }
                }
            }
        } else { // biometrics not supported
            locked = false
            updateLockState(recheck: false)
        }
    }

    @objc func lock() {
        locked = true
        updateLockState(recheck: false)
    }

    @objc func openDownloadQueue() {
        present(UINavigationController(rootViewController: DownloadQueueViewController()), animated: true)
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController: UICollectionViewDelegateFlowLayout {

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        locked ? 0 : super.collectionView(collectionView, numberOfItemsInSection: section)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        section == 0 && !categories.isEmpty ? CGSize(width: collectionView.bounds.width, height: 40) : .zero
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader && indexPath.section == 0 {
            var header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: "MangaListSelectionHeader",
                for: indexPath
            ) as? MangaListSelectionHeader
            if header == nil {
                header = MangaListSelectionHeader(frame: .zero)
            }
            guard let header = header else { return UICollectionReusableView() }
            header.delegate = nil
            header.options = ["All"] + categories
            header.selectedOption = currentCategory == nil ? 0 : (categories.firstIndex(of: currentCategory!) ?? -1) + 1
            if UserDefaults.standard.bool(forKey: "Library.lockLibrary"),
               let lockedCategories = UserDefaults.standard.stringArray(forKey: "Library.lockedCategories") {
                header.lockedOptions = [0] + lockedCategories.compactMap { category -> Int? in
                    guard let index = categories.firstIndex(of: category) else { return nil }
                    return index + 1
                }
            } else {
                header.lockedOptions = []
            }
            header.delegate = self
            header.filterButton.alpha = 1
            header.filterButton.menu = filterButton?.menu
            header.filterButton.showsMenuAsPrimaryAction = true
            return header
        }
        return UICollectionReusableView()
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
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
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            Task.detached {
                DataManager.shared.setOpened(manga: targetManga, context: DataManager.shared.backgroundContext)
            }
        }
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

            if self.opensReaderView {
                actions.append(UIAction(title: NSLocalizedString("MANGA_INFO", comment: ""), image: UIImage(systemName: "info.circle")) { _ in
                    self.openMangaView(for: targetManga)
                })
            }
            if !self.categories.isEmpty {
                actions.append(UIAction(title: NSLocalizedString("EDIT_CATEGORIES", comment: ""), image: UIImage(systemName: "folder")) { _ in
                    self.present(UINavigationController(rootViewController: CategorySelectViewController(manga: targetManga)), animated: true)
                })
            }
            actions.append(UIAction(
                title: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: ""),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                DataManager.shared.delete(manga: targetManga)
            })

            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: MangaListSelectionHeaderDelegate {
    func optionSelected(_ index: Int) {
        if index == 0 {
            currentCategory = nil
        } else {
            currentCategory = categories[index - 1]
        }
        updateLockState(reload: false)
        Task {
            await fetchLibrary()
        }
    }
}

// MARK: - Search Results Updater
extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        resortManga(reload: true)
    }
}
