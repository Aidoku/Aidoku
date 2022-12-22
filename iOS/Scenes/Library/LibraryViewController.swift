//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/23/22.
//

import UIKit
import LocalAuthentication

class LibraryViewController: BookCollectionViewController {

    lazy var viewModel = LibraryViewModel()

    private lazy var filterBarButton: UIBarButtonItem = {
        let filterImage: UIImage?
        if #available(iOS 15.0, *) {
            filterImage = UIImage(systemName: "line.3.horizontal.decrease")
        } else {
            filterImage = UIImage(systemName: "line.horizontal.3.decrease")
        }
        return UIBarButtonItem(image: filterImage, style: .plain, target: self, action: nil)
    }()

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

    private lazy var refreshControl = UIRefreshControl()

    private let emptyStackView = EmptyPageStackView()
    private let lockedStackView = LockedPageStackView()

    private lazy var locked = viewModel.categoryLocked

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

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
        var items: [UIBarButtonItem] = []
        if viewModel.categories.isEmpty {
            items.append(filterBarButton)
        }
        if viewModel.categoryLocked {
            items.append(lockBarButton)
        }
        navigationItem.rightBarButtonItems = items

        // pull to refresh
        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh(refreshControl:)), for: .valueChanged)
        collectionView.refreshControl = refreshControl

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
            header.filterButton.alpha = 1
            header.filterButton.menu = self.filterBarButton.menu
            header.filterButton.showsMenuAsPrimaryAction = true
            header.updateMenu()
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
        viewModel.loadLibrary()
        updateSortMenu()
        updateLockState()
        updateHeaderLockIcons()
        updateDataSource()
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

    override func observe() {
        super.observe()

        let checkNavbarDownloadButton: (Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let shouldShowButton = await DownloadManager.shared.hasQueuedDownloads()
                let index = self.navigationItem.rightBarButtonItems?.firstIndex(of: self.downloadBarButton)
                if shouldShowButton && index == nil {
                    if self.navigationItem.rightBarButtonItems?.count ?? 0 == 0 {
                        self.navigationItem.rightBarButtonItems = [self.downloadBarButton]
                    } else if let index = self.navigationItem.rightBarButtonItems?.firstIndex(of: self.filterBarButton) {
                        // left of filter button
                        self.navigationItem.rightBarButtonItems?.insert(self.downloadBarButton, at: index + 1)
                    } else {
                        // rightmost button
                        self.navigationItem.rightBarButtonItems?.insert(self.downloadBarButton, at: 0)
                    }
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
                self.viewModel.refreshCategories()
                self.collectionView.collectionViewLayout = self.makeCollectionViewLayout()
                self.updateDataSource()
                if self.viewModel.categories.isEmpty {
                    self.navigationItem.rightBarButtonItem = self.filterBarButton
                } else {
                    self.navigationItem.rightBarButtonItem = nil
                }
            }
        }

        addObserver(forName: "updateLibraryLock") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.locked = self.viewModel.categoryLocked
                self.updateNavbarLock()
                self.updateHeaderLockIcons()
                self.updateLockState()
                self.updateDataSource()
            }
        }

        addObserver(forName: "updateLibrary") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        let updatePinType: (Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            self.viewModel.pinType = self.viewModel.getPinType()
            Task { @MainActor in
                self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        addObserver(forName: "Library.pinManga", using: updatePinType)
        addObserver(forName: "Library.pinMangaType", using: updatePinType)

        // TODO: change this notification (elsewhere)
        // it should come with the book info or chapter or whatever that was read
        addObserver(forName: "updateHistory") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.viewModel.fetchUnreads()
                self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        // lock library when moving to background
        addObserver(forName: UIApplication.willResignActiveNotification.rawValue) { [weak self] _ in
            guard let self = self else { return }
            self.locked = self.viewModel.categoryLocked
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
        CellRegistration { cell, _, info in
            cell.sourceId = info.sourceId
            cell.bookId = info.bookId
            cell.title = info.title
            cell.badgeNumber = info.unread
            Task {
                await cell.loadImage(url: info.coverUrl)
            }
        }
    }

    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl? = nil) {
        Task { @MainActor in
            await BookManager.shared.refreshLibrary()
            viewModel.loadLibrary()
            updateDataSource()
            refreshControl?.endRefreshing()
        }
    }

    @objc func openDownloadQueue() {
        present(UINavigationController(rootViewController: DownloadQueueViewController()), animated: true)
    }
}

// MARK: - Data Source Updating
extension LibraryViewController {

    func clearDataSource() {
        let snapshot = NSDiffableDataSourceSnapshot<Section, BookInfo>()
        dataSource.apply(snapshot)
    }

    func updateDataSource() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, BookInfo>()

        if !locked {
            if !viewModel.pinnedBooks.isEmpty {
                snapshot.appendSections(Section.allCases)
                snapshot.appendItems(viewModel.pinnedBooks, toSection: .pinned)
            } else {
                snapshot.appendSections([.regular])
            }

            snapshot.appendItems(viewModel.books, toSection: .regular)
        }

        dataSource.apply(snapshot)

        // handle empty library or category
        emptyStackView.isHidden = !viewModel.books.isEmpty || !viewModel.pinnedBooks.isEmpty
        collectionView.isScrollEnabled = emptyStackView.isHidden && lockedStackView.isHidden
        collectionView.refreshControl = collectionView.isScrollEnabled ? refreshControl : nil
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
}

// MARK: - Sorting
extension LibraryViewController {

    func toggleSort(method: LibraryViewModel.SortMethod) {
        viewModel.toggleSort(method: method)
        updateDataSource()
        updateSortMenu()
    }

    func toggleFilter(method: LibraryViewModel.FilterMethod) {
        viewModel.toggleFilter(method: method)
        updateDataSource()
        updateSortMenu()
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
            if let idx = viewModel.filters.firstIndex(where: { $0.type == .downloaded }) {
                return UIImage(systemName: viewModel.filters[idx].exclude ? "xmark" : "checkmark")
            } else {
                return nil
            }
        }
        let filterMenu = UIMenu(title: NSLocalizedString("FILTER_BY", comment: ""), options: .displayInline, children: [
            UIAction(
                title: NSLocalizedString("DOWNLOADED", comment: ""),
                image: filterImage(for: .downloaded)
            ) { _ in
                self.toggleFilter(method: .downloaded)
            }
        ])
        filterBarButton.menu = UIMenu(title: "", children: [sortMenu, filterMenu])
        (collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(index: 0)
        ) as? MangaListSelectionHeader)?.filterButton.menu = filterBarButton.menu
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: MangaListSelectionHeaderDelegate {

    func optionSelected(_ index: Int) {
        if index == 0 {
            viewModel.currentCategory = nil
            emptyStackView.title = NSLocalizedString("LIBRARY_EMPTY", comment: "")
            lockedStackView.text = NSLocalizedString("LIBRARY_LOCKED", comment: "")
        } else {
            viewModel.currentCategory = viewModel.categories[index - 1]
            emptyStackView.title = NSLocalizedString("CATEGORY_EMPTY", comment: "")
            lockedStackView.text = NSLocalizedString("CATEGORY_LOCKED", comment: "")
        }
        viewModel.loadLibrary()
        locked = viewModel.categoryLocked
        updateNavbarLock()
        updateLockState()
        updateDataSource()
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController {

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didSelectItemAt: indexPath)
        guard
            !UserDefaults.standard.bool(forKey: "General.incognitoMode"),
            let info = dataSource.itemIdentifier(for: indexPath)
        else { return }
        Task {
            await CoreDataManager.shared.setOpened(sourceId: info.sourceId, mangaId: info.bookId)
            self.viewModel.bookOpened(sourceId: info.sourceId, bookId: info.bookId)
            self.updateDataSource()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let book = indexPath.section == 0 && !viewModel.pinnedBooks.isEmpty ? viewModel.pinnedBooks[indexPath.row] : viewModel.books[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            var actions: [UIAction] = []

            if let url = book.url {
                actions.append(UIAction(
                    title: NSLocalizedString("SHARE", comment: ""),
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { _ in
                    let activityViewController = UIActivityViewController(
                        activityItems: [url],
                        applicationActivities: nil
                    )
                    activityViewController.popoverPresentationController?.sourceView = self.view
                    self.present(activityViewController, animated: true)
                })
            }

            actions.append(UIAction(
                title: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: ""),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self.viewModel.removeFromLibrary(book: book)
                self.updateDataSource()
            })

            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Search Results
extension LibraryViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        viewModel.search(query: searchController.searchBar.text ?? "")
        updateDataSource()
    }
}
