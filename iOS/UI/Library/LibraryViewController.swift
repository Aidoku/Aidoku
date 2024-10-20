//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/23/22.
//

import UIKit
import LocalAuthentication
import SwiftUI

class LibraryViewController: MangaCollectionViewController {

    let viewModel = LibraryViewModel()

    private lazy var downloadBarButton = UIBarButtonItem(
        image: UIImage(systemName: "square.and.arrow.down"),
        style: .plain,
        target: self,
        action: #selector(openDownloadQueue)
    )

    private lazy var lockBarButton = UIBarButtonItem(
        image: UIImage(systemName: locked ? "lock" : "lock.open"),
        style: .plain,
        target: self,
        action: #selector(toggleLock)
    )

    private lazy var moreBarButton = UIBarButtonItem(
        image: UIImage(systemName: "ellipsis"),
        style: .plain,
        target: nil,
        action: nil
    )

    private lazy var mangaUpdatesButton = UIBarButtonItem(
        image: UIImage(systemName: "bell"),
        style: .plain,
        target: self,
        action: #selector(openMangaUpdates)
    )

    private lazy var refreshControl = UIRefreshControl()

    private lazy var emptyStackView = EmptyPageStackView()
    private lazy var lockedStackView = LockedPageStackView()

    private lazy var locked = viewModel.isCategoryLocked()

    private lazy var opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")

    private var ignoreOptionChange = false
    private var lastSearch: String?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // fix refresh control snapping height
        refreshControl.didMoveToSuperview()

        // hack to show search bar on initial presentation
        if !navigationItem.hidesSearchBarWhenScrolling {
            navigationItem.hidesSearchBarWhenScrolling = true
        }

        if viewModel.shouldUpdateLibrary() {
            updateLibraryRefresh()
        }
    }

    override func configure() {
        super.configure()

        title = NSLocalizedString("LIBRARY", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        // search controller
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("LIBRARY_SEARCH", comment: "")
        navigationItem.searchController = searchController

        // navbar buttons
        moreBarButton.menu = UIMenu(children: [
            UIAction(
                title: NSLocalizedString("SELECT", comment: ""),
                image: UIImage(systemName: "checkmark.circle")
            ) { [weak self] _ in
                guard let self = self else { return }
                self.setEditing(true, animated: true)
            }
        ])

        // toolbar buttons (editing)
        let deleteButton = UIBarButtonItem(
            title: nil,
            style: .plain,
            target: self,
            action: #selector(removeSelectedFromLibrary)
        )
        deleteButton.image = UIImage(systemName: "trash")
        deleteButton.tintColor = .red

        let addButton = UIBarButtonItem(
            title: nil,
            style: .plain,
            target: self,
            action: #selector(addSelectedToCategories)
        )
        addButton.image = UIImage(systemName: "folder.badge.plus")

        toolbarItems = [
            deleteButton,
            UIBarButtonItem(systemItem: .flexibleSpace),
            addButton
        ]

        // pull to refresh
        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh(refreshControl:)), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        collectionView.allowsMultipleSelection = true
        collectionView.allowsSelectionDuringEditing = true

        // header view
        let registration = UICollectionView.SupplementaryRegistration<MangaListSelectionHeader>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, _ in
            guard let self = self else { return }
            header.delegate = self
            header.options = [NSLocalizedString("ALL", comment: "")] + self.viewModel.categories
            header.selectedOption = self.viewModel.currentCategory != nil
                ? (self.viewModel.categories.firstIndex(of: self.viewModel.currentCategory!) ?? -1) + 1
                : 0
            header.updateMenu()

            // load locked icons
            if UserDefaults.standard.bool(forKey: "Library.lockLibrary") {
                let lockedCategories = UserDefaults.standard.stringArray(forKey: "Library.lockedCategories") ?? []
                header.lockedOptions = [0] + lockedCategories.compactMap { category -> Int? in
                    if let index = self.viewModel.categories.firstIndex(of: category) {
                        return index + 1
                    }
                    return nil
                }
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            if kind == UICollectionView.elementKindSectionHeader {
                return collectionView.dequeueConfiguredReusableSupplementary(
                    using: registration,
                    for: indexPath
                )
            }
            return nil
        }

        // empty text view
        emptyStackView.isHidden = true
        emptyStackView.title = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_EMPTY", comment: "")
            : NSLocalizedString("CATEGORY_EMPTY", comment: "")
        emptyStackView.text = NSLocalizedString("LIBRARY_ADD_FROM_BROWSE", comment: "")
        emptyStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStackView)

        // locked text view
        lockedStackView.isHidden = true
        lockedStackView.text = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED", comment: "")
            : NSLocalizedString("CATEGORY_LOCKED", comment: "")
        lockedStackView.buttonText = NSLocalizedString("VIEW_LIBRARY", comment: "")
        lockedStackView.button.addTarget(self, action: #selector(unlock), for: .touchUpInside)
        lockedStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lockedStackView)

        // load data
        Task {
            // load categories
            viewModel.categories = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getCategories(context: context).map { $0.title ?? "" }
            }
            // refresh header
            collectionView.collectionViewLayout = self.makeCollectionViewLayout()
            updateNavbarItems()

            // load library
            await viewModel.loadLibrary()
            updateSortMenu()
            updateLockState()
            updateDataSource()
        }
    }

    override func constrain() {
        super.constrain()

        NSLayoutConstraint.activate([
            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            lockedStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lockedStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // swiftlint:disable:next cyclomatic_complexity
    override func observe() {
        super.observe()

        let checkNavbarDownloadButton: (Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard !self.isEditing else { return }
                let shouldShowButton = await DownloadManager.shared.hasQueuedDownloads()
                let index = self.navigationItem.rightBarButtonItems?.firstIndex(of: self.downloadBarButton)
                if shouldShowButton && index == nil {
                    // rightmost button
                    self.navigationItem.rightBarButtonItems?.insert(
                        self.downloadBarButton,
                        at: (self.navigationItem.rightBarButtonItems?.count ?? 1) - 1
                    )
                } else if !shouldShowButton, let index = index {
                    self.navigationItem.rightBarButtonItems?.remove(at: index)
                }
            }
        }

        addObserver(forName: "downloadsQueued", using: checkNavbarDownloadButton)
        addObserver(forName: "downloadFinished", using: checkNavbarDownloadButton)
        addObserver(forName: "downloadCancelled", using: checkNavbarDownloadButton)
        addObserver(forName: "downloadsCancelled", using: checkNavbarDownloadButton)

        addObserver(forName: "updateCategories") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.viewModel.refreshCategories()
                self.collectionView.collectionViewLayout = self.makeCollectionViewLayout()
                self.updateDataSource()
                if !self.isEditing {
                    self.updateToolbar() // show/hide add category button
                }
                self.updateHeaderCategories()
                // update lock state
                if UserDefaults.standard.bool(forKey: "Library.lockLibrary") {
                    NotificationCenter.default.post(name: Notification.Name("updateLibraryLock"), object: nil)
                }
            }
        }

        addObserver(forName: "updateMangaCategories") { [weak self] _ in
            guard let self = self, self.viewModel.currentCategory != nil else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        addObserver(forName: "updateLibraryLock") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.locked = self.viewModel.isCategoryLocked()
                self.updateNavbarLock()
                self.updateHeaderLockIcons()
                self.updateLockState()
                self.updateLockStackViewText()
                self.updateDataSource()
            }
        }

        addObserver(forName: "updateLibrary") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        let updatePinType: (Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            self.viewModel.pinType = self.viewModel.getPinType()
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        addObserver(forName: "Library.pinManga", using: updatePinType)
        addObserver(forName: "Library.pinMangaType", using: updatePinType)

        addObserver(forName: "Library.opensReaderView") { [weak self] notification in
            self?.opensReaderView = notification.object as? Bool ?? false
        }

        // refresh unread badges
        addObserver(forName: "Library.unreadChapterBadges") { [weak self] _ in
            self?.viewModel.badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none
            self?.reloadItems()
        }

        // update history
        addObserver(forName: "updateHistory") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.viewModel.fetchUnreads()
                if self.viewModel.pinType != .unread {
                    await self.viewModel.loadLibrary()
                }
                self.updateDataSource()
            }
        }
        addObserver(forName: "historyAdded") { [weak self] notification in
            guard let self = self, let chapters = notification.object as? [Chapter] else { return }
            Task { @MainActor in
                let manga = Array(Set(chapters.map { MangaInfo(mangaId: $0.mangaId, sourceId: $0.sourceId) }))
                await self.viewModel.updateHistory(for: manga, read: true)
                self.updateDataSource()
            }
        }
        addObserver(forName: "historyRemoved") { [weak self] notification in
            guard let self = self else { return }
            Task { @MainActor in
                var manga: [MangaInfo] = []
                if let chapters = notification.object as? [Chapter] {
                    manga = Array(Set(chapters.map { MangaInfo(mangaId: $0.mangaId, sourceId: $0.sourceId) }))
                } else if let mangaObject = notification.object as? Manga {
                    manga = [mangaObject.toInfo()]
                }
                await self.viewModel.updateHistory(for: manga, read: false)
                self.updateDataSource()
            }
        }
        addObserver(forName: "historySet") { [weak self] notification in
            guard let self = self, let item = notification.object as? (chapter: Chapter, page: Int) else { return }
            Task { @MainActor in
                self.viewModel.mangaRead(sourceId: item.chapter.sourceId, mangaId: item.chapter.mangaId)
                self.updateDataSource()
            }
        }

        // lock library when moving to background
        addObserver(forName: UIApplication.willResignActiveNotification.rawValue) { [weak self] _ in
            guard let self = self else { return }
            self.locked = self.viewModel.isCategoryLocked()
            self.updateLockState()
            self.updateDataSource()
        }
    }

    // collection view layout with header
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = super.makeCollectionViewLayout()
        guard let layout = layout as? UICollectionViewCompositionalLayout else { return layout }

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = layout.configuration.interSectionSpacing
        if !viewModel.categories.isEmpty {
            let globalHeader = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(40)
                ),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            config.boundarySupplementaryItems = [globalHeader]
        }
        layout.configuration = config

        return layout
    }

    // cells with unread badges
    override func makeCellRegistration() -> CellRegistration {
        CellRegistration { [weak self] cell, _, info in
            cell.sourceId = info.sourceId
            cell.mangaId = info.mangaId
            cell.title = info.title
            if self?.viewModel.badgeType == .unread {
                cell.badgeNumber = info.unread
            } else {
                cell.badgeNumber = 0
            }
            cell.setEditing(self?.isEditing ?? false, animated: false)
            if cell.isSelected {
                cell.select(animated: false)
            } else {
                cell.deselect(animated: false)
            }
            Task {
                await cell.loadImage(url: info.coverUrl)
            }
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
//        collectionView.setEditing(editing, animated: animated)
        updateNavbarItems()
        updateToolbar()
        reloadItems()
    }

    @objc func stopEditing() {
        setEditing(false, animated: true)
        deselectAllItems()
    }

    func updateNavbarItems() {
        if isEditing {
            if collectionView.indexPathsForSelectedItems?.count ?? 0 == dataSource.snapshot().itemIdentifiers.count {
                navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: NSLocalizedString("DESELECT_ALL", comment: ""),
                    style: .plain,
                    target: self,
                    action: #selector(deselectAllItems)
                )
            } else {
                navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: NSLocalizedString("SELECT_ALL", comment: ""),
                    style: .plain,
                    target: self,
                    action: #selector(selectAllItems)
                )
            }
            navigationItem.rightBarButtonItems = [UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(stopEditing)
            )]
        } else {
            var items: [UIBarButtonItem] = [moreBarButton]
            if viewModel.isCategoryLocked() {
                items.append(lockBarButton)
            }
            items.append(mangaUpdatesButton)
            navigationItem.rightBarButtonItems = items
            navigationItem.leftBarButtonItem = nil
            Task { @MainActor in
                if await DownloadManager.shared.hasQueuedDownloads() {
                    let index = (navigationItem.rightBarButtonItems?.count ?? 1) - 1
                    guard !(navigationItem.rightBarButtonItems?.contains(downloadBarButton) ?? true) else { return }
                    navigationItem.rightBarButtonItems?.insert(
                        downloadBarButton,
                        at: index
                    )
                }
            }
        }
    }

    func updateToolbar() {
        if isEditing {
            // show toolbar
            if navigationController?.isToolbarHidden ?? false {
                UIView.animate(withDuration: 0.3) {
                    self.navigationController?.isToolbarHidden = false
                    self.navigationController?.toolbar.alpha = 1
                }
            }
            // show add to category button if categories exist
            if viewModel.categories.isEmpty {
                if #available(iOS 16.0, *) {
                    toolbarItems?.last?.isHidden = true
                } else {
                    toolbarItems?.last?.image = nil
                }
            } else {
                if !self.viewModel.categories.isEmpty {
                    if #available(iOS 16.0, *) {
                        toolbarItems?.last?.isHidden = false
                    } else {
                        toolbarItems?.last?.image = UIImage(systemName: "folder.badge.plus")
                    }
                }
            }
            // enable items
            let selectedItems = collectionView.indexPathsForSelectedItems ?? []
            toolbarItems?.first?.isEnabled = !selectedItems.isEmpty
            toolbarItems?.last?.isEnabled = !selectedItems.isEmpty
        } else if !(self.navigationController?.isToolbarHidden ?? true) {
            // fade out toolbar
            UIView.animate(withDuration: 0.3) {
                self.navigationController?.toolbar.alpha = 0
            } completion: { _ in
                self.navigationController?.isToolbarHidden = true
            }
        }
    }

    @objc func selectAllItems() {
        for item in dataSource.snapshot().itemIdentifiers {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
        updateNavbarItems()
        updateToolbar()
        reloadItems()
    }

    @objc func deselectAllItems() {
        for item in dataSource.snapshot().itemIdentifiers {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
        updateNavbarItems()
        updateToolbar()
        reloadItems()
    }

    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl? = nil) {
        Task { @MainActor in
            await MangaManager.shared.refreshLibrary(category: viewModel.currentCategory)
            await viewModel.loadLibrary()
            updateDataSource()
            refreshControl?.endRefreshing()
        }
    }

    @objc func openDownloadQueue() {
        present(UINavigationController(rootViewController: DownloadQueueViewController()), animated: true)
    }

    @objc func openMangaUpdates() {
        let mangaUpdatesViewController = UIHostingController(rootView: MangaUpdatesView())
        // configure navigation item before displaying to fix animation
        mangaUpdatesViewController.navigationItem.largeTitleDisplayMode = .never
        mangaUpdatesViewController.navigationItem.title = NSLocalizedString("MANGA_UPDATES", comment: "")
        navigationController?.pushViewController(mangaUpdatesViewController, animated: true)
    }

    @objc func removeSelectedFromLibrary() {
        let inCategory = viewModel.currentCategory != nil
        let selectedItems = collectionView.indexPathsForSelectedItems ?? []
        confirmAction(
            actions: inCategory ? [
                UIAlertAction(
                    title: NSLocalizedString("REMOVE_FROM_CATEGORY", comment: ""),
                    style: .destructive
                ) { _ in
                    Task {
                        let identifiers = selectedItems.compactMap { self.dataSource.itemIdentifier(for: $0) }
                        for manga in identifiers {
                            await self.viewModel.removeFromCurrentCategory(manga: manga)
                        }
                        self.updateDataSource()
                        self.updateNavbarItems()
                        self.updateToolbar()
                    }
                }
            ] : [],
            continueActionName: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: "")
        ) {
            Task {
                let identifiers = selectedItems.compactMap { self.dataSource.itemIdentifier(for: $0) }
                for manga in identifiers {
                    await MangaManager.shared.removeFromLibrary(sourceId: manga.sourceId, mangaId: manga.mangaId)
                }
                self.viewModel.pinnedManga = self.viewModel.pinnedManga.filter { item in
                    !identifiers.contains(where: { $0.mangaId == item.mangaId && $0.sourceId == item.sourceId })
                }
                self.viewModel.manga = self.viewModel.pinnedManga.filter { item in
                    !identifiers.contains(where: { $0.mangaId == item.mangaId && $0.sourceId == item.sourceId })
                }
                self.updateDataSource()
                self.updateNavbarItems()
                self.updateToolbar()
            }
        }
    }
    @objc func addSelectedToCategories() {
        let manga = (collectionView.indexPathsForSelectedItems ?? []).compactMap {
            dataSource.itemIdentifier(for: $0)
        }
        self.present(
            UINavigationController(rootViewController: AddToCategoryViewController(
                manga: manga,
                disabledCategories: viewModel.currentCategory != nil ? [viewModel.currentCategory!] : []
            )),
            animated: true
        )
    }
}

// MARK: - Data Source Updating
extension LibraryViewController {

    func clearDataSource() {
        let snapshot = NSDiffableDataSourceSnapshot<Section, MangaInfo>()
        dataSource.apply(snapshot)
    }

    func updateDataSource() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, MangaInfo>()

        if !locked {
            if !viewModel.pinnedManga.isEmpty {
                snapshot.appendSections(Section.allCases)
                snapshot.appendItems(viewModel.pinnedManga, toSection: .pinned)
            } else {
                snapshot.appendSections([.regular])
            }

            snapshot.appendItems(viewModel.manga, toSection: .regular)
        }

        dataSource.apply(snapshot)

        // handle empty library or category
        if navigationItem.searchController?.searchBar.text?.isEmpty ?? true {
            emptyStackView.isHidden = !snapshot.itemIdentifiers.isEmpty
        }
        collectionView.isScrollEnabled = emptyStackView.isHidden && lockedStackView.isHidden
        collectionView.refreshControl = collectionView.isScrollEnabled ? refreshControl : nil
    }

    func reloadItems() {
        var snapshot = dataSource.snapshot()
        if #available(iOS 15.0, *) {
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
        } else {
            snapshot.reloadItems(snapshot.itemIdentifiers)
        }
        dataSource.apply(snapshot)
    }
}

// MARK: - Locking
extension LibraryViewController {

    @objc func unlock() {
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: NSLocalizedString("AUTH_FOR_LIBRARY", comment: "")
            ) { [weak self] success, _ in
                guard success, let self = self else { return }
                Task { @MainActor in
                    self.locked = false
                    self.updateLockState()
                    self.updateDataSource()
                }
            }
        } else { // biometrics not supported
            locked = false
            updateLockState()
            updateDataSource()
        }
    }

    @objc func toggleLock() {
        if locked {
            unlock()
        } else {
            locked = true
            updateLockState()
            updateDataSource()
        }
    }

    func updateLockState() {
        if locked {
            guard emptyStackView.alpha != 0 else { return } // lock view already showing
            collectionView.isScrollEnabled = false
            emptyStackView.alpha = 0
            lockedStackView.alpha = 0
            lockedStackView.isHidden = false
            UIView.animate(withDuration: 0.3) {
                self.lockedStackView.alpha = 1
            }
        } else {
            collectionView.isScrollEnabled = emptyStackView.isHidden
            lockedStackView.isHidden = true
            UIView.animate(withDuration: 0.3) {
                self.emptyStackView.alpha = 1
            }
        }
        lockBarButton.image = UIImage(systemName: locked ? "lock" : "lock.open")
    }

    func updateNavbarLock() {
        guard !self.isEditing else { return }
        let index = navigationItem.rightBarButtonItems?.firstIndex(of: lockBarButton)
        if locked && index == nil {
            if navigationItem.rightBarButtonItems?.count ?? 0 == 0 {
                navigationItem.rightBarButtonItems = [lockBarButton]
            } else {
                navigationItem.rightBarButtonItems?.append(lockBarButton)
            }
        } else if !locked, let index = index {
            navigationItem.rightBarButtonItems?.remove(at: index)
        }
    }

    func updateHeaderLockIcons() {
        guard let header = (collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(index: 0)
        ) as? MangaListSelectionHeader) else { return }
        if UserDefaults.standard.bool(forKey: "Library.lockLibrary") {
            let lockedCategories = UserDefaults.standard.stringArray(forKey: "Library.lockedCategories") ?? []
            header.lockedOptions = [0] + lockedCategories.compactMap { category -> Int? in
                if let index = viewModel.categories.firstIndex(of: category) {
                    return index + 1
                }
                return nil
            }
        } else {
            header.lockedOptions = []
        }
    }

    // update category options in header
    func updateHeaderCategories() {
        guard let header = (collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(index: 0)
        ) as? MangaListSelectionHeader) else { return }
        ignoreOptionChange = true
        header.options = [NSLocalizedString("ALL", comment: "")] + viewModel.categories
        header.setSelectedOption(
            viewModel.currentCategory != nil
                ? (viewModel.categories.firstIndex(of: viewModel.currentCategory!) ?? -1) + 1
                : 0
        )
    }
}

// MARK: - Sorting
extension LibraryViewController {

    func toggleSort(method: LibraryViewModel.SortMethod) {
        Task {
            await viewModel.toggleSort(method: method)
            updateDataSource()
            updateSortMenu()
        }
    }

    func toggleFilter(method: LibraryViewModel.FilterMethod) {
        Task {
            await viewModel.toggleFilter(method: method)
            updateDataSource()
            updateSortMenu()
        }
    }

    func updateSortMenu() {
        let chevronIcon = UIImage(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
        let sortMenu = UIMenu(title: NSLocalizedString("SORT_BY", comment: ""), options: .displayInline, children: [
            UIAction(
                title: NSLocalizedString("TITLE", comment: ""),
                image: viewModel.sortMethod == .alphabetical ? chevronIcon : nil
            ) { _ in
                self.toggleSort(method: .alphabetical)
            },
            UIAction(
                title: NSLocalizedString("LAST_READ", comment: ""),
                image: viewModel.sortMethod == .lastRead ? chevronIcon : nil
            ) { _ in
                self.toggleSort(method: .lastRead)
            },
            UIAction(
                title: NSLocalizedString("LAST_OPENED", comment: ""),
                image: viewModel.sortMethod == .lastOpened ? chevronIcon : nil
            ) { _ in
                self.toggleSort(method: .lastOpened)
            },
            UIAction(
                title: NSLocalizedString("LAST_UPDATED", comment: ""),
                image: viewModel.sortMethod == .lastUpdated ? chevronIcon : nil
            ) { _ in
                self.toggleSort(method: .lastUpdated)
            },
            UIAction(
                title: NSLocalizedString("DATE_ADDED", comment: ""),
                image: viewModel.sortMethod == .dateAdded ? chevronIcon : nil
            ) { _ in
                self.toggleSort(method: .dateAdded)
            },
            UIAction(
                title: NSLocalizedString("UNREAD_CHAPTERS", comment: ""),
                image: viewModel.sortMethod == .unreadChapters ? chevronIcon : nil
            ) { _ in
                self.toggleSort(method: .unreadChapters)
            },
            UIAction(
                title: NSLocalizedString("TOTAL_CHAPTERS", comment: ""),
                image: viewModel.sortMethod == .totalChapters ? chevronIcon : nil
            ) { _ in
                self.toggleSort(method: .totalChapters)
            }
        ])
        func filterImage(for method: LibraryViewModel.FilterMethod) -> UIImage? {
            if let filter = viewModel.filters.first(where: { $0.type == method }) {
                return UIImage(systemName: filter.exclude ? "xmark" : "checkmark")
            } else {
                return nil
            }
        }
        let trackingFilter: [UIAction]
        if TrackerManager.shared.hasAvailableTrackers {
            trackingFilter = [UIAction(
                title: NSLocalizedString("TRACKING", comment: ""),
                image: filterImage(for: .tracking)
            ) { _ in
                self.toggleFilter(method: .tracking)
            }]
        } else {
            trackingFilter = []
        }
        let filterMenu = UIMenu(title: NSLocalizedString("FILTER_BY", comment: ""), options: .displayInline, children: [
            UIAction(
                title: NSLocalizedString("DOWNLOADED", comment: ""),
                image: filterImage(for: .downloaded)
            ) { _ in
                self.toggleFilter(method: .downloaded)
            }
        ] + trackingFilter)
        let selectAction = UIAction(
            title: NSLocalizedString("SELECT", comment: ""),
            image: UIImage(systemName: "checkmark.circle")
        ) { [weak self] _ in
            guard let self = self else { return }
            self.setEditing(true, animated: true)
        }
        moreBarButton.menu = UIMenu(children: [
            selectAction, sortMenu, filterMenu
        ])
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: MangaListSelectionHeaderDelegate {

    func optionSelected(_ index: Int) {
        guard !ignoreOptionChange else {
            ignoreOptionChange = false
            return
        }
        if index == 0 {
            viewModel.currentCategory = nil
        } else {
            viewModel.currentCategory = viewModel.categories[index - 1]
        }
        updateLockStackViewText()
        locked = viewModel.isCategoryLocked()
        updateNavbarLock()
        updateLockState()
        deselectAllItems()
        updateToolbar()
        updateNavbarItems()
        Task {
            await viewModel.loadLibrary()
            updateDataSource()
        }
    }

    private func updateLockStackViewText() {
        lockedStackView.text = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED", comment: "")
            : NSLocalizedString("CATEGORY_LOCKED", comment: "")
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController {

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard
            let info = dataSource.itemIdentifier(for: indexPath)
        else { return }

        if isEditing {
            if let cell = collectionView.cellForItem(at: indexPath) as? MangaGridCell {
                cell.select()
                updateNavbarItems()
                updateToolbar()
            }
            return
        }

        if opensReaderView {
            Task {
                // get next chapter to read
                let history = await CoreDataManager.shared.getReadingHistory(
                    sourceId: info.sourceId,
                    mangaId: info.mangaId
                )
                let chapters = await CoreDataManager.shared.getChapters(sourceId: info.sourceId, mangaId: info.mangaId)
                let chapter = chapters.reversed().first(where: { history[$0.id]?.page ?? 0 != -1 })

                if let chapter = chapter {
                    // open reader view
                    let readerController = ReaderViewController(chapter: chapter, chapterList: chapters)
                    let navigationController = ReaderNavigationController(rootViewController: readerController)
                    navigationController.modalPresentationStyle = .fullScreen
                    present(navigationController, animated: true)
                } else {
                    // no chapter to read, open manga page
                    let indexPath = dataSource.indexPath(for: info) ?? indexPath // get new index path in case it changed
                    super.collectionView(collectionView, didSelectItemAt: indexPath)
                }
            }
        } else {
            super.collectionView(collectionView, didSelectItemAt: indexPath)
        }
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            Task {
                await CoreDataManager.shared.setOpened(sourceId: info.sourceId, mangaId: info.mangaId)
                await self.viewModel.mangaOpened(sourceId: info.sourceId, mangaId: info.mangaId)
                self.updateDataSource()
            }
        }
        collectionView.deselectItem(at: indexPath, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if isEditing {
            if let cell = collectionView.cellForItem(at: indexPath) as? MangaGridCell {
                cell.deselect()
                updateNavbarItems()
                updateToolbar()
            }
        }
    }

    // hide highlighting when editing
    override func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        guard !isEditing else { return }
        super.collectionView(collectionView, didHighlightItemAt: indexPath)
    }

    override func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        guard !isEditing else { return }
        super.collectionView(collectionView, didUnhighlightItemAt: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first else { return nil }
        let manga = indexPath.section == 0 && !viewModel.pinnedManga.isEmpty
            ? viewModel.pinnedManga[indexPath.row]
            : viewModel.manga[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            var actions: [UIMenuElement] = []

            if self.opensReaderView {
                actions.append(UIAction(
                    title: NSLocalizedString("MANGA_INFO", comment: ""),
                    image: UIImage(systemName: "info.circle")
                ) { _ in
                    super.collectionView(collectionView, didSelectItemAt: indexPath) // open info view
                })
            }

            if !self.viewModel.categories.isEmpty {
                actions.append(UIAction(
                    title: NSLocalizedString("EDIT_CATEGORIES", comment: ""),
                    image: UIImage(systemName: "folder.badge.gearshape")
                ) { _ in
                    let manga = manga.toManga()
                    self.present(
                        UINavigationController(rootViewController: CategorySelectViewController(manga: manga)),
                        animated: true
                    )
                })
            }

            actions.append(UIMenu(title: NSLocalizedString("MARK_ALL", comment: ""), image: nil, children: [
                // read chapters
                UIAction(title: NSLocalizedString("READ", comment: ""), image: UIImage(systemName: "eye")) { _ in
                    self.showLoadingIndicator()
                    Task {
                        let manga = manga.toManga()
                        let chapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceId, mangaId: manga.id)

                        await HistoryManager.shared.addHistory(chapters: chapters)
                        self.hideLoadingIndicator()
                    }
                },
                // unread chapters
                UIAction(title: NSLocalizedString("UNREAD", comment: ""), image: UIImage(systemName: "eye.slash")) { _ in
                    self.showLoadingIndicator()
                    Task {
                        let manga = manga.toManga()
                        let chapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceId, mangaId: manga.id)

                        await HistoryManager.shared.removeHistory(chapters: chapters)
                        self.hideLoadingIndicator()
                    }
                }
            ]))

            actions.append(UIAction(
                title: NSLocalizedString("MIGRATE", comment: ""),
                image: UIImage(systemName: "arrow.left.arrow.right")
            ) { [weak self] _ in
                let manga = manga.toManga()
                let migrateView = MigrateMangaView(manga: [manga])
                self?.present(UIHostingController(rootView: SwiftUINavigationView(rootView: AnyView(migrateView))), animated: true)
            })

            if let url = manga.url {
                actions.append(UIAction(
                    title: NSLocalizedString("SHARE", comment: ""),
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { _ in
                    let activityViewController = UIActivityViewController(
                        activityItems: [url],
                        applicationActivities: nil
                    )
                    activityViewController.popoverPresentationController?.sourceView = self.view
                    activityViewController.popoverPresentationController?.sourceRect = collectionView.cellForItem(at: indexPath)?.frame ?? .zero

                    self.present(activityViewController, animated: true)
                })
            }

            let downloadAllAction = UIAction(title: NSLocalizedString("ALL", comment: "")) { _ in
                if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") &&
                    Reachability.getConnectionType() == .wifi ||
                    !UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
                    Task {
                        await DownloadManager.shared.downloadAll(manga: manga.toManga())
                    }
                } else {
                    self.presentAlert(
                        title: NSLocalizedString("NO_WIFI_ALERT_TITLE", comment: ""),
                        message: NSLocalizedString("NO_WIFI_ALERT_MESSAGE", comment: "")
                    )
                }
            }
            let downloadUnreadAction = UIAction(title: NSLocalizedString("UNREAD", comment: "")) { _ in
                if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") &&
                    Reachability.getConnectionType() == .wifi ||
                    !UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
                    Task {
                        await DownloadManager.shared.downloadUnread(manga: manga.toManga())
                    }
                } else {
                    self.presentAlert(
                        title: NSLocalizedString("NO_WIFI_ALERT_TITLE", comment: ""),
                        message: NSLocalizedString("NO_WIFI_ALERT_MESSAGE", comment: "")
                    )
                }
            }

            actions.append(UIMenu(
                title: NSLocalizedString("DOWNLOAD", comment: ""),
                image: UIImage(systemName: "arrow.down.circle"),
                children: [downloadAllAction, downloadUnreadAction]
            ))

            if self.viewModel.currentCategory != nil {
                actions.append(UIAction(
                    title: NSLocalizedString("REMOVE_FROM_CATEGORY", comment: ""),
                    image: UIImage(systemName: "folder.badge.minus"),
                    attributes: .destructive
                ) { _ in
                    Task {
                        await self.viewModel.removeFromCurrentCategory(manga: manga)
                        self.updateDataSource()
                    }
                })
            }

            actions.append(UIAction(
                title: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: ""),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                Task {
                    await self.viewModel.removeFromLibrary(manga: manga)
                    self.updateDataSource()
                }
            })

            return UIMenu(title: "", children: actions)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        self.collectionView(collectionView, contextMenuConfigurationForItemsAt: [indexPath], point: point)
    }
}

// MARK: - Search Results
extension LibraryViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        guard searchController.searchBar.text != lastSearch else { return }
        lastSearch = searchController.searchBar.text
        Task {
            await viewModel.search(query: searchController.searchBar.text ?? "")
            updateDataSource()
        }
    }
}
