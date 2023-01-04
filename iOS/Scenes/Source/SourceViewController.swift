//
//  SourceViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import SafariServices

class SourceViewController: MangaCollectionViewController {

    let viewModel = SourceViewModel()

    let source: Source
    var hidesListings = false

    private var ignoreOptionChange = false
    private var storedTabBarAppearance: UITabBarAppearance?

    private lazy var refreshControl = UIRefreshControl()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        return activityIndicator
    }()

    init(source: Source) {
        self.source = source
        self.viewModel.source = source
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        super.configure()

        title = source.manifest.info.name
        navigationItem.hidesSearchBarWhenScrolling = false

        if source.titleSearchable {
            let searchController = UISearchController(searchResultsController: nil)
            searchController.searchResultsUpdater = self
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.searchBar.text = viewModel.titleQuery
            navigationItem.searchController = searchController
        }

        refreshControl.addTarget(self, action: #selector(refresh(_:)), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        // header view
        let registration = UICollectionView.SupplementaryRegistration<MangaListSelectionHeader>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, _ in
            guard let self = self else { return }
            header.delegate = self
            header.title = NSLocalizedString("LIST_HEADER", comment: "")
            header.options = self.viewModel.listings.map { $0.name } + [NSLocalizedString("LIST_ALL", comment: "")]
            header.selectedOption = self.viewModel.currentListing != nil
                ? self.viewModel.listings.firstIndex(of: self.viewModel.currentListing!) ?? 0
                : self.viewModel.listings.count
            header.filterButton.alpha = self.source.filterable ? 1 : 0
            header.filterButton.addTarget(self, action: #selector(self.openFilterPopover), for: .touchUpInside)
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

        view.addSubview(activityIndicator)

        updateNavbarItems(showFilterButton: false) // don't show filter button before filters/listings load

        // load initial data
        Task {
            if !hidesListings {
                await viewModel.loadListings()
                self.collectionView.collectionViewLayout = self.makeCollectionViewLayout()
                updateHeaderListing()
            }
            if source.filterable {
                await viewModel.loadFilters()
                if viewModel.listings.isEmpty {
                    updateNavbarItems() // add filter button to navbar
                }
            }
            await viewModel.loadNextMangaPage()
            updateDataSource()
        }
    }

    override func constrain() {
        super.constrain()

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func observe() {
        // refresh when languages change
        addObserver(forName: "\(source.id).languages") { [weak self] _ in
            guard let self = self else { return }
            self.refresh()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // fix tab bar background turning clear when presenting
        if #available(iOS 15.0, *) {
            storedTabBarAppearance = navigationController?.tabBarController?.tabBar.scrollEdgeAppearance
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            navigationController?.tabBarController?.tabBar.scrollEdgeAppearance = tabBarAppearance
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // hack to show search bar on initial presentation
        if !navigationItem.hidesSearchBarWhenScrolling {
            navigationItem.hidesSearchBarWhenScrolling = !hidesListings // if hiding listings, make search bar sticky
        }

        // reset tab bar background fix
        if #available(iOS 15.0, *) {
            navigationController?.tabBarController?.tabBar.scrollEdgeAppearance = storedTabBarAppearance
        }
    }

    override func makeCellRegistration() -> CellRegistration {
        CellRegistration { cell, _, info in
            cell.sourceId = info.sourceId
            cell.mangaId = info.mangaId
            cell.title = info.title
            let inLibrary = CoreDataManager.shared.hasLibraryManga(sourceId: info.sourceId, mangaId: info.mangaId)
            cell.showsBookmark = inLibrary
            Task {
                await cell.loadImage(url: info.coverUrl)
            }
        }
    }

    // collection view layout with header
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = super.makeCollectionViewLayout()
        guard let layout = layout as? UICollectionViewCompositionalLayout else { return layout }

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = layout.configuration.interSectionSpacing
        if !viewModel.listings.isEmpty {
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

    func updateNavbarItems(showFilterButton: Bool = true) {
        var items = [
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis"),
                style: .plain,
                target: self,
                action: #selector(openInfoPage)
            )
        ]
        // show filter button in navbar if header is hidden
        if showFilterButton && source.filterable && (hidesListings || viewModel.listings.isEmpty) {
            let filterImage: UIImage?
            if #available(iOS 15.0, *) {
                filterImage = UIImage(systemName: "line.3.horizontal.decrease.circle")
            } else {
                filterImage = UIImage(systemName: "line.horizontal.3.decrease.circle")
            }
            items.append(
                UIBarButtonItem(
                    image: filterImage,
                    style: .plain,
                    target: self,
                    action: #selector(openFilterPopover)
                )
            )
        }
        // show safari button if source has a url to open
        if source.manifest.info.url != nil || !(source.manifest.info.urls?.isEmpty ?? true) {
            items.append(
                UIBarButtonItem(
                    image: UIImage(systemName: "safari"),
                    style: .plain,
                    target: self,
                    action: #selector(openSourceWebView)
                )
            )
        }
        let finalItems = items // switch to constant
        Task { @MainActor in
            navigationItem.rightBarButtonItems = finalItems
        }
    }

    func updateHeaderListing() {
        guard let header = (collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(index: 0)
        ) as? MangaListSelectionHeader) else { return }
        let listingOption = self.viewModel.currentListing != nil
            ? self.viewModel.listings.firstIndex(of: self.viewModel.currentListing!) ?? 0
            : self.viewModel.listings.count
        ignoreOptionChange = true
        header.setSelectedOption(listingOption)
    }

    @objc func refresh(_ refreshControl: UIRefreshControl? = nil) {
        viewModel.currentPage = nil
        Task {
            await viewModel.loadNextMangaPage()
            updateDataSource()
            refreshControl?.endRefreshing()
        }
    }

    @objc func openInfoPage() {
        let infoController = UINavigationController(rootViewController: SourceInfoViewController(source: source))
        present(infoController, animated: true)
    }

    @objc func openFilterPopover() {
        // save current filters to compare with when done
        viewModel.saveSelectedFilters()

        let vc = FilterModalViewController(filters: viewModel.filters, selectedFilters: viewModel.selectedFilters)
        vc.delegate = self
        vc.resetButton.addTarget(self, action: #selector(resetSelectedFilters), for: .touchUpInside)
        vc.modalPresentationStyle = .overFullScreen
        present(vc, animated: false)
    }

    @objc func openSourceWebView() {
        let url: URL?
        if let urlString = source.manifest.info.url {
            url = URL(string: urlString)
        } else if let urlString = source.manifest.info.urls?.first  {
            url = URL(string: urlString)
        } else {
            url = nil
        }
        if let url = url {
            let safariViewController = SFSafariViewController(url: url)
            present(safariViewController, animated: true)
        }
    }

    @objc func resetSelectedFilters() {
        viewModel.resetSelectedFilters()
    }
}

// MARK: Collection View Delegate
extension SourceViewController {
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        if indexPath.row == viewModel.manga.count - 1 && viewModel.hasMore {
            Task {
                await viewModel.loadNextMangaPage()
                updateDataSource()
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let indexPath = indexPaths.first,
            let mangaInfo = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            var actions: [UIAction] = []

            let inLibrary = CoreDataManager.shared.hasLibraryManga(
                sourceId: mangaInfo.sourceId,
                mangaId: mangaInfo.mangaId
            )

            // library option
            if inLibrary {
                actions.append(UIAction(
                    title: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: ""),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    Task {
                        await MangaManager.shared.removeFromLibrary(
                            sourceId: mangaInfo.sourceId,
                            mangaId: mangaInfo.mangaId
                        )
                        self.refreshCells(for: [mangaInfo])
                    }
                })
            } else {
                actions.append(UIAction(
                    title: NSLocalizedString("ADD_TO_LIBRARY", comment: ""),
                    image: UIImage(systemName: "books.vertical.fill")
                ) { _ in
                    Task {
                        await MangaManager.shared.addToLibrary(manga: mangaInfo.toManga(), fetchMangaDetails: true)
                        self.refreshCells(for: [mangaInfo])
                    }
                })
            }

            // share option
            if let url = mangaInfo.url {
                actions.append(UIAction(
                    title: NSLocalizedString("SHARE", comment: ""),
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { [weak self] _ in
                    guard let self = self else { return }

                    let activityViewController = UIActivityViewController(
                        activityItems: [url],
                        applicationActivities: nil
                    )
                    activityViewController.popoverPresentationController?.sourceView = self.view

                    self.present(activityViewController, animated: true)
                })
            }
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

// MARK: - Data Source
extension SourceViewController {

    func updateDataSource() {
        // show/hide loading indicator
        if viewModel.manga.isEmpty && viewModel.hasMore {
            activityIndicator.startAnimating()
            UIView.animate(withDuration: 0.3) {
                self.activityIndicator.alpha = 1
            }
        } else if activityIndicator.alpha == 1 {
            UIView.animate(withDuration: 0.3) {
                self.activityIndicator.alpha = 0
            } completion: { _ in
                self.activityIndicator.stopAnimating()
            }
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, MangaInfo>()

        viewModel.manga = viewModel.manga.unique() // ensure unique elements for data source

        snapshot.appendSections([.regular])
        snapshot.appendItems(viewModel.manga)

        dataSource.apply(snapshot)
    }

    func insert(items: [MangaInfo]) {
        var snapshot = dataSource.snapshot()
        snapshot.appendItems(items)
        dataSource.apply(snapshot)
    }

    func refreshCells(for mangaInfo: [MangaInfo]) {
        var snapshot = dataSource.snapshot()
        if #available(iOS 15.0, *) {
            snapshot.reconfigureItems(mangaInfo)
        } else {
            snapshot.reloadItems(mangaInfo)
        }
        dataSource.apply(snapshot)
    }
}

// MARK: - Search Results
extension SourceViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        var query = searchController.searchBar.text
        if query?.isEmpty ?? false {
            query = nil
        }
        if query != viewModel.titleQuery {
            Task {
                viewModel.currentListing = nil
                updateHeaderListing()
                let success = await viewModel.search(titleQuery: searchController.searchBar.text)
                if success {
                    await MainActor.run {
                        updateDataSource()
                    }
                }
            }
        }
    }
}

// MARK: - Listing Header Delegate
extension SourceViewController: MangaListSelectionHeaderDelegate {

    func optionSelected(_ index: Int) {
        guard !ignoreOptionChange else {
            ignoreOptionChange = false
            return
        }
        if index == viewModel.listings.count { // "all" listing
            viewModel.currentListing = nil
            Task {
                await CoreDataManager.shared.setListing(sourceId: source.id, listing: 0)
            }
        } else {
            // remove search query when switching to listing
            navigationItem.searchController?.searchBar.text = nil
            viewModel.titleQuery = nil
            viewModel.currentListing = viewModel.listings[index]
            Task {
                await CoreDataManager.shared.setListing(sourceId: source.id, listing: index + 1)
            }
            DataManager.shared.setListing(for: source, listing: index + 1)
        }
        viewModel.currentPage = nil
        Task {
            await viewModel.loadNextMangaPage()
            updateDataSource()
        }
    }
}

// MARK: - Filter Modal Delegate
extension SourceViewController: MiniModalDelegate {

    func modalWillDismiss() {
        let shouldRefresh = viewModel.savedFiltersDiffer()
        viewModel.clearSavedFilters()
        if shouldRefresh {
            viewModel.currentPage = nil
            viewModel.currentListing = nil
            viewModel.manga = []
            Task {
                await CoreDataManager.shared.setListing(sourceId: source.id, listing: 0)
            }
            Task {
                await viewModel.loadNextMangaPage()
                updateDataSource()
            }
        }
    }
}
