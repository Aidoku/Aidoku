//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/23/22.
//

import UIKit
import LocalAuthentication
import SwiftUI
import AidokuRunner

class LibraryViewController: OldMangaCollectionViewController {
    let viewModel = LibraryViewModel()

    // MARK: Bar Buttons
    private lazy var downloadBarButton = makeBarButton(
        systemName: "square.and.arrow.down",
        action: #selector(openDownloadQueue),
        titleKey: "DOWNLOAD_QUEUE",
        sharesBackground: false
    )
    private lazy var lockBarButton = makeBarButton(
        systemName: locked ? "lock" : "lock.open",
        action: #selector(performToggleLock),
        titleKey: "TOGGLE_LOCK"
    )
    private lazy var moreBarButton =  makeBarButton(
        systemName: "ellipsis",
        action: nil,
        titleKey: "MORE_BARBUTTON"
    )
    private lazy var mangaUpdatesButton = makeBarButton(
        systemName: "bell",
        action: #selector(openMangaUpdates),
        titleKey: "MANGA_UPDATES",
        sharesBackground: false
    )

    private func makeBarButton(systemName: String? = nil, action: Selector?, titleKey: String, sharesBackground: Bool = true) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: systemName.flatMap { UIImage(systemName: $0) },
            style: .plain,
            target: self,
            action: action
        )
        item.title = NSLocalizedString(titleKey)
        if #available(iOS 26.0, *), !sharesBackground {
            item.sharesBackground = false
        }
        return item
    }

    private lazy var refreshControl = UIRefreshControl()
    private lazy var emptyStackView = EmptyPageStackView()
    private lazy var lockedStackView = LockedPageStackView()

    private lazy var locked = viewModel.isCategoryLocked()
    private var ignoreOptionChange = false
    private var lastSearch: String?

    private let libraryUndoManager = UndoManager()
    override var undoManager: UndoManager { libraryUndoManager }
    override var canBecomeFirstResponder: Bool { true }

    override var usesListLayout: Bool {
        get {
            UserDefaults.standard.bool(forKey: "Library.listView")
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: "Library.listView")
        }
    }

    override init() {
        super.init()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // fix refresh control snapping height
        refreshControl.didMoveToSuperview()

        // hack to show search bar on initial presentation
        if !navigationItem.hidesSearchBarWhenScrolling {
            navigationItem.hidesSearchBarWhenScrolling = true
        }

        becomeFirstResponder()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // load stored download queue state on first load
        Task {
            await SourceManager.shared.loadSources() // make sure sources are loaded first
            await DownloadManager.shared.loadQueueState()
        }
    }

    override func configure() {
        super.configure()

        title = NSLocalizedString("LIBRARY")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        collectionView.keyboardDismissMode = .onDrag

        // search controller
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("LIBRARY_SEARCH")
        navigationItem.searchController = searchController

        // navbar buttons
        updateMoreMenu()

        // toolbar buttons (editing)
        let deleteButton = UIBarButtonItem(
            title: nil,
            style: .plain,
            target: self,
            action: #selector(removeSelectedFromLibrary)
        )
        deleteButton.image = UIImage(systemName: "trash")
        if #unavailable(iOS 26.0) {
            deleteButton.tintColor = .systemRed
        }

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

        collectionView.allowsMultipleSelection = !ProcessInfo.processInfo.isMacCatalystApp
        collectionView.allowsSelectionDuringEditing = true

        // header view
        let registration = UICollectionView.SupplementaryRegistration<MangaListSelectionHeader>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, _ in
            guard let self else { return }
            header.delegate = self
            header.options = [NSLocalizedString("ALL")] + self.viewModel.categories
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
        view.addSubview(emptyStackView)

        // locked text view
        lockedStackView.isHidden = true
        lockedStackView.text = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED")
            : NSLocalizedString("CATEGORY_LOCKED")
        lockedStackView.buttonText = NSLocalizedString("VIEW_LIBRARY")
        lockedStackView.button.addTarget(self, action: #selector(performUnlock), for: .touchUpInside)
        view.addSubview(lockedStackView)

        // load data
        Task {
            // load categories
            viewModel.categories = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                CoreDataManager.shared.getCategories(context: context).map { $0.title ?? "" }
            }
            // refresh header
            collectionView.collectionViewLayout = self.makeCollectionViewLayout()
            updateNavbarItems()

            // load library
            await viewModel.loadLibrary()
            updateEmptyStack()
            updateLockState()
        }
    }

    override func constrain() {
        super.constrain()

        emptyStackView.translatesAutoresizingMaskIntoConstraints = false
        lockedStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            lockedStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lockedStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func observe() {
        super.observe()

        let checkNavbarDownloadButton: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
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
        addObserver(forName: .downloadsQueued, using: checkNavbarDownloadButton)
        addObserver(forName: .downloadCancelled, using: checkNavbarDownloadButton)
        addObserver(forName: .downloadsCancelled, using: checkNavbarDownloadButton)

        let updateDownloadCounts: (Notification) -> Void = { [weak self] notification in
            guard let self else { return }
            if let id = notification.object as? ChapterIdentifier {
                Task {
                    await self.viewModel.fetchDownloadCounts(for: id.mangaIdentifier)
                    self.updateDataSource()
                }
            } else if let id = notification.object as? MangaIdentifier {
                Task {
                    await self.viewModel.fetchDownloadCounts(for: id)
                    self.updateDataSource()
                }
            }
        }
        addObserver(forName: .downloadFinished) { notification in
            checkNavbarDownloadButton(notification)
            updateDownloadCounts(.init(name: .downloadFinished, object: (notification.object as? Download)?.mangaIdentifier))
        }
        addObserver(forName: .downloadRemoved, using: updateDownloadCounts)
        addObserver(forName: .downloadsRemoved, using: updateDownloadCounts)

        addObserver(forName: .updateLibrary) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateEmptyStack()
                self.updateDataSource()
            }
        }
        addObserver(forName: .updateLibraryLock) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.locked = self.viewModel.isCategoryLocked()
                self.updateLockState()
            }
        }
        addObserver(forName: .updateCategories) { [weak self] _ in
            guard let self else { return }
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
        addObserver(forName: .updateMangaCategories) { [weak self] _ in
            guard let self, self.viewModel.currentCategory != nil else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }
        addObserver(forName: .updateManga) { [weak self] notification in
            guard let self, let id = notification.object as? MangaIdentifier else { return }
            Task {
                let libraryReloaded = if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
                    await self.viewModel.mangaOpened(sourceId: id.sourceKey, mangaId: id.mangaKey)
                } else {
                    false
                }
                if !libraryReloaded {
                    if self.viewModel.sortMethod == .lastUpdated || self.viewModel.sortMethod == .lastChapter {
                        // if sorting by updated or last chapter, or pinning updated, we need to reload the library to update the order
                        await self.viewModel.loadLibrary()
                    } else {
                        // otherwise, just update the unread count (in case chapters were added)
                        await self.viewModel.fetchUnreads(for: id)
                    }
                }
                self.updateDataSource()
            }
        }

        addObserver(forName: .pinTitles) { [weak self] _ in
            guard let self else { return }
            self.viewModel.pinType = self.viewModel.getPinType()
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        // refresh badges
        addObserver(forName: "Library.unreadChapterBadges") { [weak self] _ in
            if UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") {
                self?.viewModel.badgeType.insert(.unread)
            } else {
                self?.viewModel.badgeType.remove(.unread)
            }
            self?.reloadItems()
        }
        addObserver(forName: "Library.downloadedChapterBadges") { [weak self] _ in
            if UserDefaults.standard.bool(forKey: "Library.downloadedChapterBadges") {
                self?.viewModel.badgeType.insert(.downloaded)
            } else {
                self?.viewModel.badgeType.remove(.downloaded)
            }
            self?.reloadItems()
        }

        // update history
        addObserver(forName: .updateHistory) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.fetchUnreads()
                if self.viewModel.pinType != .unread {
                    await self.viewModel.loadLibrary()
                }
                self.updateDataSource()
            }
        }
        addObserver(forName: .historyAdded) { [weak self] notification in
            guard let self, let chapters = notification.object as? [Chapter] else { return }
            Task { @MainActor in
                let manga = Array(Set(chapters.map { MangaInfo(mangaId: $0.mangaId, sourceId: $0.sourceId) }))
                await self.viewModel.updateHistory(for: manga, read: true)
                self.updateDataSource()
            }
        }
        addObserver(forName: .historyRemoved) { [weak self] notification in
            guard let self else { return }
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
        addObserver(forName: .historySet) { [weak self] notification in
            guard let self, let item = notification.object as? (chapter: Chapter, page: Int) else { return }
            Task { @MainActor in
                self.viewModel.mangaRead(sourceId: item.chapter.sourceId, mangaId: item.chapter.mangaId)
                self.updateDataSource()
            }
        }

        // lock library when moving to background
        addObserver(forName: UIApplication.willResignActiveNotification) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.locked = self.viewModel.isCategoryLocked()
                self.updateLockState()
            }
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

    // cells with badges
    override func configure(cell: MangaGridCell, info: MangaInfo) {
        super.configure(cell: cell, info: info)

        cell.badgeNumber = viewModel.badgeType.contains(.unread) ? info.unread : 0
        cell.badgeNumber2 = viewModel.badgeType.contains(.downloaded) ? info.downloads : 0

        cell.setEditing(self.isEditing, animated: false)
    }

    override func configure(cell: MangaListCell, info: MangaInfo) {
        super.configure(cell: cell, info: info)

        cell.badgeNumber = viewModel.badgeType.contains(.unread) ? info.unread : 0
        cell.badgeNumber2 = viewModel.badgeType.contains(.downloaded) ? info.downloads : 0

        cell.setEditing(isEditing, animated: false)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        updateNavbarItems()
        updateToolbar()

        if ProcessInfo.processInfo.isMacCatalystApp {
            collectionView.allowsMultipleSelection = editing
        }

        for cell in collectionView.visibleCells {
            if let cell = cell as? MangaGridCell {
                cell.setEditing(editing, animated: animated)
            } else if let cell = cell as? MangaListCell {
                cell.setEditing(editing, animated: animated)
            }
        }
    }
}

extension LibraryViewController {
    func updateNavbarItems() {
        if isEditing {
            let allItemsSelected = collectionView.indexPathsForSelectedItems?.count ?? 0 == dataSource.snapshot().itemIdentifiers.count
            navigationItem.leftBarButtonItem = if allItemsSelected {
                makeBarButton(
                    action: #selector(deselectAllItems),
                    titleKey: "DESELECT_ALL"
                )
            } else {
                makeBarButton(
                    action: #selector(selectAllItems),
                    titleKey: "SELECT_ALL"
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
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    self.navigationController?.isToolbarHidden = false
                    self.navigationController?.toolbar.alpha = 1
                    if #available(iOS 26.0, *) {
                        // hide tab bar on iOS 26 (it covers the toolbar)
                        self.tabBarController?.isTabBarHidden = true
                    }
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
            let hasSelectedItems = !(collectionView.indexPathsForSelectedItems?.isEmpty ?? true)
            toolbarItems?.first?.isEnabled = hasSelectedItems
            toolbarItems?.last?.isEnabled = hasSelectedItems
        } else if !(self.navigationController?.isToolbarHidden ?? true) {
            // fade out toolbar
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.navigationController?.toolbar.alpha = 0
                if #available(iOS 26.0, *) {
                    // reshow tab bar on iOS 26
                    self.tabBarController?.isTabBarHidden = false
                }
            } completion: { _ in
                self.navigationController?.isToolbarHidden = true
            }
        }
    }

    // updates library empty message
    // should be called when category changes and when library loads initially
    func updateEmptyStack() {
        emptyStackView.imageSystemName = "books.vertical.fill"
        emptyStackView.title = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_EMPTY")
            : NSLocalizedString("CATEGORY_EMPTY")
        emptyStackView.text = viewModel.actuallyEmpty
            ? NSLocalizedString("LIBRARY_ADD_CONTENT")
            : NSLocalizedString("LIBRARY_ADJUST_FILTERS")
    }

    @objc func stopEditing() {
        setEditing(false, animated: true)
        deselectAllItems()
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
        Task {
            // delay hiding refresh control to avoid buggy animation
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            refreshControl?.endRefreshing()
        }

        Task {
            await MangaManager.shared.backgroundRefreshLibrary(category: viewModel.currentCategory)
        }
    }

    @objc func openDownloadQueue() {
        let viewController = UIHostingController(rootView: DownloadQueueView())
        viewController.navigationItem.largeTitleDisplayMode = .never
        viewController.navigationItem.title = NSLocalizedString("DOWNLOAD_QUEUE")
        if #available(iOS 26.0, *) {
            viewController.preferredTransition = .zoom { _ in
                self.downloadBarButton
            }
        }
        viewController.modalPresentationStyle = .pageSheet
        present(viewController, animated: true)
    }

    @objc func openMangaUpdates() {
        let path = NavigationCoordinator(rootViewController: self)
        let viewController = UIHostingController(rootView: MangaUpdatesView().environmentObject(path))
        viewController.navigationItem.largeTitleDisplayMode = .never
        viewController.navigationItem.title = NSLocalizedString("MANGA_UPDATES")
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc func removeSelectedFromLibrary() {
        let inCategory = viewModel.currentCategory != nil
        let selectedItems = collectionView.indexPathsForSelectedItems ?? []
        confirmAction(
            actions: inCategory ? [
                UIAlertAction(
                    title: NSLocalizedString("REMOVE_FROM_CATEGORY"),
                    style: .destructive
                ) { _ in
                    Task {
                        let identifiers = selectedItems.compactMap { self.dataSource.itemIdentifier(for: $0) }
                        await self.removeFromCategory(mangaInfo: identifiers)?.value
                        self.updateNavbarItems()
                        self.updateToolbar()
                    }
                }
            ] : [],
            continueActionName: NSLocalizedString("REMOVE_FROM_LIBRARY"),
            sourceItem: toolbarItems?.first
        ) {
            Task {
                let identifiers = selectedItems.compactMap { self.dataSource.itemIdentifier(for: $0) }
                await self.removeFromLibrary(mangaInfo: identifiers)?.value
                self.updateNavbarItems()
                self.updateToolbar()
            }
        }
    }

    @objc func addSelectedToCategories() {
        let manga = (collectionView.indexPathsForSelectedItems ?? []).compactMap {
            dataSource.itemIdentifier(for: $0)
        }
        present(
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
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot)
    }
}

// MARK: - Locking
extension LibraryViewController {
    func lock() {
        locked = true
        updateLockState()
    }

    func unlock() {
        locked = false
        updateLockState()
    }

    func attemptUnlock() async {
        do {
            let success = try await LAContext().evaluatePolicy(
                .defaultPolicy,
                localizedReason: NSLocalizedString("AUTH_FOR_LIBRARY")
            )
            guard success else { return }
        } catch {
            // The error is displayed to users, so we can ignore it.
            return
        }

        unlock()
    }

    @objc func performUnlock() {
        Task {
            await attemptUnlock()
        }
    }

    @objc func performToggleLock() {
        Task {
            if locked {
                await attemptUnlock()
            } else {
                lock()
            }
        }
    }

    func updateLockState() {
        if locked {
            guard emptyStackView.alpha != 0 else { return } // lock view already showing
            collectionView.isScrollEnabled = false
            emptyStackView.alpha = 0
            lockedStackView.alpha = 0
            lockedStackView.isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.lockedStackView.alpha = 1
            }
        } else {
            collectionView.isScrollEnabled = emptyStackView.isHidden
            lockedStackView.isHidden = true
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.emptyStackView.alpha = 1
            }
        }
        lockBarButton.image = UIImage(systemName: locked ? "lock" : "lock.open")

        lockedStackView.text = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED")
            : NSLocalizedString("CATEGORY_LOCKED")

        updateNavbarLock()
        updateHeaderLockIcons()
        updateDataSource()
    }

    func updateNavbarLock() {
        guard !isEditing else { return }
        let index = navigationItem.rightBarButtonItems?.firstIndex(of: lockBarButton)
        if locked && index == nil {
            if navigationItem.rightBarButtonItems?.count ?? 0 == 0 {
                navigationItem.rightBarButtonItems = [lockBarButton]
            } else {
                navigationItem.rightBarButtonItems?.insert(lockBarButton, at: 1)
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
        header.options = [NSLocalizedString("ALL")] + viewModel.categories
        header.setSelectedOption(
            viewModel.currentCategory != nil
                ? (viewModel.categories.firstIndex(of: viewModel.currentCategory!) ?? -1) + 1
                : 0
        )
    }
}

// MARK: - Sorting and Filtering
extension LibraryViewController {
    func setSort(method: LibraryViewModel.SortMethod, ascending: Bool) {
        Task {
            await viewModel.setSort(method: method, ascending: ascending)
            updateDataSource()
            updateMoreMenu()
        }
    }

    func toggleFilter(method: LibraryViewModel.FilterMethod, value: String? = nil) {
        Task {
            await viewModel.toggleFilter(method: method, value: value)
            updateDataSource()
            if #available(iOS 26.0, *) {
                updateFilterMenuState()
            } else {
                updateMoreMenu()
            }
        }
    }

    func filterState(for method: LibraryViewModel.FilterMethod, value: String? = nil) -> UIMenuElement.State {
        if let filter = viewModel.filters.first(where: { $0.type == method && $0.value == value }) {
            filter.exclude ? .mixed : .on
        } else {
            .off
        }
    }

    func removeFilterAction() -> UIAction {
        UIAction(
            title: NSLocalizedString("REMOVE_FILTER"),
            image: UIImage(systemName: "minus.circle")
        ) { [weak self] _ in
            Task {
                self?.viewModel.filters = []
                await self?.viewModel.loadLibrary()
                self?.updateDataSource()
                self?.updateMoreMenu()
            }
        }
    }

    func filtersSubtitle() -> String? {
        guard !viewModel.filters.isEmpty else { return nil }
        var options: [String] = []
        var methods: Set<LibraryViewModel.FilterMethod> = []
        for filterMethod in LibraryViewModel.FilterMethod.allCases {
            // ensure we only list each method type once (e.g. for multiple source filters)
            guard methods.insert(filterMethod).inserted else {
                continue
            }
            if let filter = viewModel.filters.first(where: { $0.type == filterMethod }) {
                guard options.count < 3 else {
                    options.removeLast() // make subtitle fit in two lines
                    options.append(NSLocalizedString("AND_MORE"))
                    break
                }
                if filter.exclude {
                    options.append(String(format: NSLocalizedString("NOT_%@"), filterMethod.title))
                } else {
                    options.append(filterMethod.title)
                }
            }
        }
        return options.joined(separator: NSLocalizedString("FILTER_SEPARATOR"))
    }

    @available(iOS 26.0, *)
    func updateFilterMenuState() {
        // _contextMenuInteraction only exists on ios 26+
        // a similar thing could probably be achieved on lower versions by putting a UIButton in the bar button custom view
        let contextMenuInteraction = moreBarButton.value(forKey: "_contextMenuInteraction") as? UIContextMenuInteraction
        guard let contextMenuInteraction else { return }

        func updateFilterSubmenu(_ menu: UIMenu) -> UIMenu {
            menu.subtitle = self.filtersSubtitle()
            return menu.replacingChildren(menu.children.map { element in
                guard let action = element as? UIAction else { return element }
                if let method = LibraryViewModel.FilterMethod.allCases.first(where: { $0.title == action.title }) {
                    action.state = filterState(for: method)
                }
                return action
            })
        }

        contextMenuInteraction.updateVisibleMenu { menu in
            if menu.title == NSLocalizedString("BUTTON_FILTER") {
                updateFilterSubmenu(menu)
            } else if menu.title == LibraryViewModel.FilterMethod.source.title {
                menu.replacingChildren(self.viewModel.sourceKeys.map { key in
                    UIAction(
                        title: SourceManager.shared.source(for: key)?.name ?? key,
                        attributes: .keepsMenuPresented,
                        state: self.filterState(for: .source, value: key)
                    ) { [weak self] _ in
                        self?.toggleFilter(method: .source, value: key)
                    }
                })
            } else if menu.title == LibraryViewModel.FilterMethod.contentRating.title {
                menu.replacingChildren(MangaContentRating.allCases.map { rating in
                    UIAction(
                        title: rating.title,
                        attributes: .keepsMenuPresented,
                        state: self.filterState(for: .contentRating, value: rating.stringValue)
                    ) { [weak self] _ in
                        self?.toggleFilter(method: .contentRating, value: rating.stringValue)
                    }
                })
            } else {
                menu.replacingChildren(menu.children.map { element in
                    guard let menu = element as? UIMenu else { return element }
                    if menu.children.first?.title == NSLocalizedString("SORT_BY") {
                        let shouldShowRemoveFilter = !self.viewModel.filters.isEmpty
                        let isShowingRemoveFilter = menu.children.last?.title == NSLocalizedString("REMOVE_FILTER")

                        let updatedChildren = menu.children.map { element in
                            if element.title == NSLocalizedString("BUTTON_FILTER"), let menu = element as? UIMenu {
                                updateFilterSubmenu(menu) as UIMenuElement
                            } else {
                                element
                            }
                        }

                        if shouldShowRemoveFilter && !isShowingRemoveFilter {
                            return menu.replacingChildren(updatedChildren + [removeFilterAction()])
                        } else if !shouldShowRemoveFilter && isShowingRemoveFilter {
                            return menu.replacingChildren(updatedChildren.dropLast())
                        }
                    }
                    return element
                })
            }
        }

        if !viewModel.filters.isEmpty {
            moreBarButton.isSelected = true
            moreBarButton.image = UIImage(systemName: "line.3.horizontal.decrease")?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
        } else {
            moreBarButton.isSelected = false
            moreBarButton.image = UIImage(systemName: "ellipsis")
        }
    }

    func updateMoreMenu() {
        let selectAction = UIAction(
            title: NSLocalizedString("SELECT"),
            image: UIImage(systemName: "checkmark.circle")
        ) { [weak self] _ in
            guard let self else { return }
            self.setEditing(true, animated: true)
        }

        let layoutActions = [
            UIAction(
                title: NSLocalizedString("LAYOUT_GRID"),
                image: UIImage(systemName: "square.grid.2x2"),
                state: usesListLayout ? .off : .on
            ) { [weak self] _ in
                guard let self, self.usesListLayout else { return }
                self.usesListLayout = false
                self.collectionView.setCollectionViewLayout(self.makeCollectionViewLayout(), animated: true)
                self.collectionView.reloadData()
                self.updateMoreMenu()
            },
            UIAction(
                title: NSLocalizedString("LAYOUT_LIST"),
                image: UIImage(systemName: "list.bullet"),
                state: usesListLayout ? .on : .off
            ) { [weak self] _ in
                guard let self, !self.usesListLayout else { return }
                self.usesListLayout = true
                self.collectionView.setCollectionViewLayout(self.makeCollectionViewLayout(), animated: true)
                self.collectionView.reloadData()
                self.updateMoreMenu()
            }
        ]

        let sortMenu = UIMenu(
            title: NSLocalizedString("SORT_BY"),
            subtitle: viewModel.sortMethod.title,
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: [
                UIMenu(options: .displayInline, children: LibraryViewModel.SortMethod.allCases.map { method in
                    UIAction(
                        title: method.title,
                        state: viewModel.sortMethod == method ? .on : .off
                    ) { [weak self] _ in
                        self?.setSort(method: method, ascending: false)
                    }
                }),
                UIMenu(options: .displayInline, children: [false, true].map { ascending in
                    UIAction(
                        title: ascending ? viewModel.sortMethod.ascendingTitle : viewModel.sortMethod.descendingTitle,
                        state: viewModel.sortAscending == ascending ? .on : .off
                    ) { [weak self] _ in
                        guard let self else { return }
                        self.setSort(method: self.viewModel.sortMethod, ascending: ascending)
                    }
                })
            ]
        )

        let filterMenu = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }
            let attributes: UIMenuElement.Attributes = if #available(iOS 16.0, *) {
                .keepsMenuPresented
            } else {
                []
            }
            let filters = UIMenu(
                title: NSLocalizedString("BUTTON_FILTER"),
                subtitle: self.filtersSubtitle(),
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                children: LibraryViewModel.FilterMethod.allCases.compactMap { method in
                    guard method.isAvailable else { return nil }
                    return UIAction(
                        title: method.title,
                        image: method.image,
                        attributes: attributes,
                        state: self.filterState(for: method)
                    ) { [weak self] _ in
                        self?.toggleFilter(method: method)
                    }
                } + [
                    UIMenu(
                        title: LibraryViewModel.FilterMethod.contentRating.title,
                        image: LibraryViewModel.FilterMethod.contentRating.image,
                        children: MangaContentRating.allCases.map { rating in
                            UIAction(
                                title: rating.title,
                                attributes: attributes,
                                state: self.filterState(for: .contentRating, value: rating.stringValue)
                            ) { [weak self] _ in
                                self?.toggleFilter(method: .contentRating, value: rating.stringValue)
                            }
                        }
                    ),
                    UIMenu(
                        title: LibraryViewModel.FilterMethod.source.title,
                        image: LibraryViewModel.FilterMethod.source.image,
                        children: self.viewModel.sourceKeys.map { key in
                            UIAction(
                                title: SourceManager.shared.source(for: key)?.name ?? key,
                                attributes: attributes,
                                state: self.filterState(for: .source, value: key)
                            ) { [weak self] _ in
                                self?.toggleFilter(method: .source, value: key)
                            }
                        }
                    )
                ]
            )
            if self.viewModel.filters.isEmpty {
                completion([filters])
            } else {
                completion([filters, self.removeFilterAction()])
            }
        }

        moreBarButton.menu = UIMenu(
            children: [
                UIMenu(options: .displayInline, children: [selectAction]),
                UIMenu(options: .displayInline, children: layoutActions),
                UIMenu(options: .displayInline, children: [sortMenu, filterMenu])
            ]
        )

        if #available(iOS 26.0, *) {
            if !viewModel.filters.isEmpty {
                moreBarButton.isSelected = true
                moreBarButton.image = UIImage(systemName: "line.3.horizontal.decrease")?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
            } else {
                moreBarButton.isSelected = false
                moreBarButton.image = UIImage(systemName: "ellipsis")
            }
        }
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: MangaListSelectionHeaderDelegate {
    nonisolated func optionSelected(_ index: Int) {
        Task { @MainActor in
            guard !ignoreOptionChange else {
                ignoreOptionChange = false
                return
            }
            if index == 0 {
                viewModel.currentCategory = nil
            } else {
                viewModel.currentCategory = viewModel.categories[index - 1]
            }
            locked = viewModel.isCategoryLocked()
            updateLockState()
            deselectAllItems()
            updateToolbar()
            updateNavbarItems()

            await viewModel.loadLibrary()
            updateEmptyStack()
            updateDataSource()
        }
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController {
    // support two finger drag to select
    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        true
    }

    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        setEditing(true, animated: true)
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let info = dataSource.itemIdentifier(for: indexPath) else { return }

        if isEditing {
            let cell = collectionView.cellForItem(at: indexPath)
            guard let cell else { return }
            if let cell = cell as? MangaGridCell {
                cell.setSelected(true)
            } else if let cell = cell as? MangaListCell {
                cell.setSelected(true)
            }
            if #available(iOS 17.5, *) {
                UISelectionFeedbackGenerator().selectionChanged(at: cell.center)
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            updateNavbarItems()
            updateToolbar()
            return
        }

        if UserDefaults.standard.bool(forKey: "Library.opensReaderView") {
            Task {
                // get next chapter to read
                let history = await CoreDataManager.shared.getReadingHistory(
                    sourceId: info.sourceId,
                    mangaId: info.mangaId
                )
                let chapters = await CoreDataManager.shared.getChapters(sourceId: info.sourceId, mangaId: info.mangaId)
                    .map { $0.toNew() }

                let filters = CoreDataManager.shared.getMangaChapterFilters(
                    sourceId: info.sourceId,
                    mangaId: info.mangaId
                )
                let sortOption = ChapterSortOption(flags: filters.flags)
                let sortAscending = filters.flags & ChapterFlagMask.sortAscending != 0

                let sortedChapters: [AidokuRunner.Chapter] = {
                    switch sortOption {
                        case .sourceOrder:
                            return sortAscending ? chapters.reversed() : chapters
                        case .chapter:
                            return chapters.sorted {
                                let lhs = $0.chapterNumber ?? -1
                                let rhs = $1.chapterNumber ?? -1
                                return sortAscending ? lhs < rhs : lhs > rhs
                            }
                        case .uploadDate:
                            return chapters.sorted {
                                let lhs = $0.dateUploaded ?? .distantPast
                                let rhs = $1.dateUploaded ?? .distantPast
                                return sortAscending ? lhs < rhs : lhs > rhs
                            }
                    }
                }()

                let manga = AidokuRunner.Manga(
                    sourceKey: info.sourceId,
                    key: info.mangaId,
                    title: info.title ?? "",
                    chapters: sortedChapters
                )

                let nextChapter = MangaManager.shared.getNextChapter(
                    manga: manga,
                    chapters: sortedChapters,
                    readingHistory: history,
                    sortAscending: sortAscending
                )

                if let chapter = nextChapter {
                    // open reader view
                    guard let source = SourceManager.shared.source(for: info.sourceId) else {
                        return
                    }
                    let manga = AidokuRunner.Manga(
                        sourceKey: info.sourceId,
                        key: info.mangaId,
                        title: info.title ?? "",
                        chapters: sortedChapters
                    )
                    let readerController = ReaderViewController(
                        source: source,
                        manga: manga,
                        chapter: chapter
                    )
                    let navigationController = ReaderNavigationController(
                        readerViewController: readerController,
                        mangaInfo: info
                    )
                    if #available(iOS 18.0, *) {
                        navigationController.preferredTransition = .zoom { context in
                            guard
                                let navigationController = context.zoomedViewController as? ReaderNavigationController,
                                let info = navigationController.mangaInfo,
                                let indexPath = self.dataSource.indexPath(for: info),
                                let cell = self.collectionView.cellForItem(at: indexPath)
                            else {
                                return nil
                            }
                            if let cell = cell as? MangaListCell {
                                return cell.coverImageView
                            } else {
                                return cell.contentView
                            }
                        }
                    }
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
            let cell = collectionView.cellForItem(at: indexPath)
            if let cell = cell as? MangaGridCell {
                cell.setSelected(false)
            } else if let cell = cell as? MangaListCell {
                cell.setSelected(false)
            }
            updateNavbarItems()
            updateToolbar()
        }
    }

    // don't highlighting when selecting during editing
    override func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        guard !isEditing else { return }
        super.collectionView(collectionView, didHighlightItemAt: indexPath)
    }

    private func mangaInfo(at path: IndexPath) -> MangaInfo {
        let manga: [MangaInfo] = if path.section == 0 && !viewModel.pinnedManga.isEmpty {
            viewModel.pinnedManga
        } else {
            viewModel.manga
        }

        return manga[path.row]
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first else { return nil }

        let manga = mangaInfo(at: indexPath)
        let mangaInfo = indexPaths.map(mangaInfo(at:))

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            var actions: [UIMenuElement] = []
            let singleAttributes = mangaInfo.count > 1
                ? .disabled
                : UIMenuElement.Attributes()

            if let url = manga.url {
                actions.append(UIMenu(identifier: .share, options: .displayInline, children: [
                    UIAction(
                        title: NSLocalizedString("SHARE"),
                        image: UIImage(systemName: "square.and.arrow.up"),
                        attributes: singleAttributes
                    ) { _ in
                        let activityViewController = UIActivityViewController(
                            activityItems: [url],
                            applicationActivities: nil
                        )
                        activityViewController.popoverPresentationController?.sourceView = self.view
                        activityViewController.popoverPresentationController?.sourceRect = collectionView.cellForItem(at: indexPath)?.frame ?? .zero

                        self.present(activityViewController, animated: true)
                    }
                ]))
            }

            if UserDefaults.standard.bool(forKey: "Library.opensReaderView"), mangaInfo.count == 1 {
                actions.append(UIAction(
                    title: NSLocalizedString("MANGA_INFO"),
                    image: UIImage(systemName: "info.circle"),
                    attributes: singleAttributes
                ) { _ in
                    self.openInfoView(info: mangaInfo[0], zoom: false)
                })
            }

            if !self.viewModel.categories.isEmpty {
                actions.append(UIAction(
                    title: NSLocalizedString("EDIT_CATEGORIES"),
                    image: UIImage(systemName: "folder.badge.gearshape"),
                    attributes: singleAttributes
                ) { _ in
                    let manga = manga.toManga()
                    self.present(
                        UINavigationController(
                            rootViewController: CategorySelectViewController(
                                manga: manga.toNew()
                            )
                        ),
                        animated: true
                    )
                })
            }

            actions.append(UIAction(
                title: NSLocalizedString("MIGRATE"),
                image: UIImage(systemName: "arrow.left.arrow.right")
            ) { [weak self] _ in
                let manga = mangaInfo.map { $0.toManga() }
                let migrateView = MigrateMangaView(manga: manga)
                self?.present(UIHostingController(rootView: SwiftUINavigationView(rootView: migrateView)), animated: true)
            })

            var bottomMenuChildren: [UIMenuElement] = []

            bottomMenuChildren.append(UIMenu(title: NSLocalizedString("MARK_ALL"), image: nil, children: [
                // read chapters
                UIAction(title: NSLocalizedString("READ"), image: UIImage(systemName: "eye")) { _ in
                    (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()

                    Task {
                        for manga in mangaInfo {
                            let manga = manga.toManga()
                            let chapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceId, mangaId: manga.id)

                            await HistoryManager.shared.addHistory(
                                sourceId: manga.sourceId,
                                mangaId: manga.id,
                                chapters: chapters.map { $0.toNew() }
                            )
                        }

                        await (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
                    }
                },
                // unread chapters
                UIAction(title: NSLocalizedString("UNREAD"), image: UIImage(systemName: "eye.slash")) { _ in
                    (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()

                    Task {
                        for manga in mangaInfo {
                            let manga = manga.toManga()
                            let chapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceId, mangaId: manga.id)

                            await HistoryManager.shared.removeHistory(
                                sourceId: manga.sourceId,
                                mangaId: manga.id,
                                chapterIds: chapters.map { $0.id }
                            )
                        }

                        await (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
                    }
                }
            ]))

            let downloadAllAction = UIAction(title: NSLocalizedString("ALL")) { _ in
                if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") &&
                    Reachability.getConnectionType() == .wifi ||
                    !UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
                    Task {
                        for mangaInfo in mangaInfo {
                            await DownloadManager.shared.downloadAll(manga: mangaInfo.toManga().toNew())
                        }
                    }
                } else {
                    self.presentAlert(
                        title: NSLocalizedString("NO_WIFI_ALERT_TITLE"),
                        message: NSLocalizedString("NO_WIFI_ALERT_MESSAGE")
                    )
                }
            }

            let downloadUnreadAction = UIAction(title: NSLocalizedString("UNREAD")) { _ in
                if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") &&
                    Reachability.getConnectionType() == .wifi ||
                    !UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
                    Task {
                        for manga in mangaInfo {
                            await DownloadManager.shared.downloadUnread(manga: manga.toManga().toNew())
                        }
                    }
                } else {
                    self.presentAlert(
                        title: NSLocalizedString("NO_WIFI_ALERT_TITLE"),
                        message: NSLocalizedString("NO_WIFI_ALERT_MESSAGE")
                    )
                }
            }

            if manga.sourceId != LocalSourceRunner.sourceKey && SourceManager.shared.hasSourceInstalled(id: manga.sourceId) {
                bottomMenuChildren.append(UIMenu(
                    title: NSLocalizedString("DOWNLOAD"),
                    image: UIImage(systemName: "arrow.down.circle"),
                    children: [downloadAllAction, downloadUnreadAction]
                ))
            }

            if self.viewModel.currentCategory != nil {
                bottomMenuChildren.append(UIAction(
                    title: NSLocalizedString("REMOVE_FROM_CATEGORY"),
                    image: UIImage(systemName: "folder.badge.minus"),
                    attributes: .destructive
                ) { _ in
                    self.removeFromCategory(mangaInfo: mangaInfo)
                })
            }

            bottomMenuChildren.append(UIAction(
                title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self.removeFromLibrary(mangaInfo: mangaInfo)
            })

            actions.append(UIMenu(options: .displayInline, children: bottomMenuChildren))

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

// MARK: - Undoable Methods
extension LibraryViewController {
    @discardableResult
    func removeFromLibrary(mangaInfo: [MangaInfo]) -> Task<Void, Never>? {
        let mangaCount = mangaInfo.count
        let actionName =
            mangaCount > 1
            ? String(
                format: NSLocalizedString("REMOVING_%i_ITEMS_FROM_LIBRARY"), mangaCount
            ) : NSLocalizedString("REMOVING_(ONE)_ITEM_FROM_LIBRARY")
        undoManager.setActionName(actionName)

        let removedManga = mangaInfo.map {
            let manga = CoreDataManager.shared.getManga(sourceId: $0.sourceId, mangaId: $0.mangaId)?
                .toManga()

            let chapters = CoreDataManager.shared.getChapters(
                sourceId: $0.sourceId, mangaId: $0.mangaId
            ).map { $0.toChapter() }

            let trackItems = CoreDataManager.shared.getTracks(
                sourceId: $0.sourceId, mangaId: $0.mangaId
            ).map { $0.toItem() }

            let categories = CoreDataManager.shared.getCategories(
                sourceId: $0.sourceId, mangaId: $0.mangaId
            ).compactMap { $0.title }

            return (manga, chapters, trackItems, categories)
        }

        undoManager.registerUndo(withTarget: self) { target in
            target.undoManager.registerUndo(withTarget: target) { redoTarget in
                redoTarget.removeFromLibrary(mangaInfo: mangaInfo)
            }

            Task {
                for (manga, chapters, trackItems, categories) in removedManga {
                    guard let manga = manga else { continue }
                    await MangaManager.shared.restoreToLibrary(
                        manga: manga, chapters: chapters, trackItems: trackItems,
                        categories: categories)
                }

                NotificationCenter.default.post(
                    name: Notification.Name("updateLibrary"), object: nil)
            }
        }

        return Task {
            for manga in mangaInfo {
                await viewModel.removeFromLibrary(manga: manga)
            }

            updateDataSource()
        }
    }

    @discardableResult
    func removeFromCategory(mangaInfo: [MangaInfo]) -> Task<Void, Never>? {
        guard let currentCategory = viewModel.currentCategory else { return nil }
        let mangaCount = mangaInfo.count
        let actionName =
            mangaCount > 1
            ? String(
                format: NSLocalizedString("REMOVING_%i_ITEMS_FROM_CATEGORY_%@"),
                mangaCount, currentCategory)
            : String(
                format: NSLocalizedString("REMOVING_(ONE)_ITEM_FROM_CATEGORY_%@"),
                currentCategory)
        undoManager.setActionName(actionName)

        undoManager.registerUndo(withTarget: self) { target in
            target.undoManager.registerUndo(withTarget: target) { redoTarget in
                redoTarget.removeFromCategory(mangaInfo: mangaInfo)
            }

            Task {
                for manga in mangaInfo {
                    await target.viewModel.addToCurrentCategory(manga: manga)
                }

                NotificationCenter.default.post(
                    name: NSNotification.Name("updateMangaCategories"),
                    object: nil)
            }
        }

        return Task {
            for manga in mangaInfo {
                await viewModel.removeFromCurrentCategory(manga: manga)
            }

            updateDataSource()
        }
    }
}
