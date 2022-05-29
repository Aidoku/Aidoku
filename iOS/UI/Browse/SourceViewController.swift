//
//  SourceViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import SafariServices

class SourceViewController: MangaCollectionViewController {

    let source: Source

    var restrictToSearch = false {
        didSet {
            navigationItem.hidesSearchBarWhenScrolling = restrictToSearch
            if restrictToSearch {
                currentListing = nil
            }
        }
    }

    var listings: [Listing] = []
    var filters: [FilterBase] = []

    var hasMore = false
    var page: Int?
    var query: String?
    var currentListing: Listing?
    let selectedFilters = SelectedFilters()

    var oldSelectedFilters: [FilterBase] = []

    var listingsLoaded = false

    init(source: Source) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = source.manifest.info.name

        navigationItem.hidesSearchBarWhenScrolling = false

        updateNavbarItems()

        collectionView?.register(MangaListSelectionHeader.self,
                                 forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                 withReuseIdentifier: "MangaListSelectionHeader")

        if source.titleSearchable {
            let searchController = UISearchController(searchResultsController: nil)
            searchController.searchBar.delegate = self
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.searchBar.text = query
            navigationItem.searchController = searchController
        }

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        Task {
            if filters.isEmpty || source.needsFilterRefresh {
                await fetchFilters()
            }
            if manga.isEmpty {
                await fetchData()
                UIView.animate(withDuration: 0.3) {
                    activityIndicator.alpha = 0
                }
                reloadData()
            } else {
                activityIndicator.alpha = 0
            }
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("\(source.id).languages"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task {
                self.page = nil
                await self.fetchData()
                self.reloadData()
            }
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !restrictToSearch {
            navigationItem.hidesSearchBarWhenScrolling = true
        }
    }

    func updateNavbarItems() {
        var items = [
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis"),
                style: .plain,
                target: self,
                action: #selector(openInfoPage)
            )
        ]
        if source.filterable && (restrictToSearch || (listings.isEmpty && listingsLoaded)) {
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
        let finalItems = items
        Task { @MainActor in
            navigationItem.rightBarButtonItems = finalItems
        }
    }

    func resetFilters(filters: [FilterBase]) {
        for filter in filters {
            if let filter = filter as? CheckFilter {
                filter.value = filter.defaultValue
            } else if let filter = filter as? SortFilter {
                filter.value = filter.defaultValue
            } else if let filter = filter as? SelectFilter {
                filter.value = filter.defaultValue
            } else if let filter = filter as? GroupFilter {
                resetFilters(filters: filter.filters)
            }
        }
    }

    @objc func resetSelectedFilters() {
        resetFilters(filters: filters)
        selectedFilters.filters = source.getDefaultFilters()
    }

    func fetchFilters() async {
        let reset = source.needsFilterRefresh
        filters = (try? await source.getFilters()) ?? []
        if selectedFilters.filters.isEmpty || reset {
            resetSelectedFilters()
        }
    }

    func fetchData() async {
        if listings.isEmpty {
            listings = source.listings
            listingsLoaded = true

            let sourceListing = DataManager.shared.getListing(for: source)
            if sourceListing > 0 && sourceListing - 1 < listings.count {
                currentListing = listings[sourceListing - 1]
            }

            self.updateNavbarItems()
        }
        if page == nil {
            manga = []
            page = 1
            hasMore = true
        } else if let current = page {
            page = current + 1
        }
        if hasMore, let page = page {
            let result: MangaPageResult?
            if let listing = currentListing {
                result = try? await source.getMangaListing(listing: listing, page: page)
            } else if let query = query {
                result = try? await source.fetchSearchManga(query: query, filters: selectedFilters.filters, page: page)
            } else {
                result = try? await source.getMangaList(filters: selectedFilters.filters, page: page)
            }
            manga.append(contentsOf: result?.manga ?? [])
            hasMore = result?.hasNextPage ?? false
        }
    }

    @objc func openInfoPage() {
        let infoController = UINavigationController(rootViewController: SourceInfoViewController(source: source))
        present(infoController, animated: true)
    }

    @objc func openFilterPopover() {
        oldSelectedFilters = selectedFilters.filters.compactMap { $0.copy() as? FilterBase }

        let vc = FilterModalViewController(filters: filters, selectedFilters: selectedFilters)
        vc.delegate = self
        vc.resetButton.addTarget(self, action: #selector(resetSelectedFilters), for: .touchUpInside)
        vc.modalPresentationStyle = .overFullScreen
        present(vc, animated: false)
    }

    @objc func openSourceWebView() {
        if let urlString = source.manifest.info.url, let url = URL(string: urlString) {
            let safariViewController = SFSafariViewController(url: url)
            present(safariViewController, animated: true)
        } else if let urlString = source.manifest.info.urls?.first, let url = URL(string: urlString) {
            let safariViewController = SFSafariViewController(url: url)
            present(safariViewController, animated: true)
        }
    }
}

// MARK: - Collection View Delegate
extension SourceViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        restrictToSearch || listings.isEmpty ? .zero : CGSize(width: collectionView.bounds.width, height: 40)
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader {
            var header = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                         withReuseIdentifier: "MangaListSelectionHeader",
                                                                         for: indexPath) as? MangaListSelectionHeader
            if header == nil {
                header = MangaListSelectionHeader(frame: .zero)
            }
            header?.delegate = nil
            var options = listings.map { $0.name }
            options.append(NSLocalizedString("LIST_ALL", comment: ""))
            header?.title = NSLocalizedString("LIST_HEADER", comment: "")
            header?.options = options
            header?.selectedOption = currentListing == nil ? listings.count : listings.firstIndex(of: currentListing!) ?? 0

            header?.filterButton.alpha = source.filterable ? 1 : 0
            header?.filterButton.addTarget(self, action: #selector(openFilterPopover), for: .touchUpInside)

            header?.delegate = self
            return header ?? UICollectionReusableView()
        }
        return UICollectionReusableView()
    }

    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.row == manga.count - 1 && hasMore {
            Task {
                let start = manga.count
                await fetchData()
                var indexPaths: [IndexPath] = []
                for i in start..<manga.count {
                    indexPaths.append(IndexPath(row: i, section: 0))
                }
                collectionView.insertItems(at: indexPaths)
            }
        }
        guard indexPath.row < manga.count else { return }
        (cell as? MangaCoverCell)?.showsLibraryBadge = DataManager.shared.libraryContains(manga: manga[indexPath.row])
    }
}

// MARK: - Listing Header Delegate
extension SourceViewController: MangaListSelectionHeaderDelegate {

    func optionSelected(_ index: Int) {
        if index == listings.count {
            currentListing = nil
            DataManager.shared.setListing(for: source, listing: 0)
        } else {
            currentListing = listings[index]
            DataManager.shared.setListing(for: source, listing: index + 1)
            query = nil
        }
        Task {
            page = nil
            await fetchData()
            reloadData()
        }
    }
}

// MARK: - Search Bar Delegate
extension SourceViewController: UISearchBarDelegate {

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard searchBar.text != query else { return }
        query = searchBar.text
        currentListing = nil
        DataManager.shared.setListing(for: source, listing: 0)
        Task {
            page = nil
            await fetchData()
            reloadData()
        }
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        query = nil
        Task {
            page = nil
            await fetchData()
            reloadData()
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            query = nil
            Task {
                page = nil
                await fetchData()
                reloadData()
            }
        }
    }
}

// MARK: - Modal Delegate
extension SourceViewController: MiniModalDelegate {

    func modalWillDismiss() {
        var update = false
        if oldSelectedFilters.count != selectedFilters.filters.count {
            update = true
        } else {
            for filter in oldSelectedFilters {
                if let target = selectedFilters.filters.first(where: { filter.type == $0.type && filter.name == $0.name }) {
                    if let target = target as? SortFilter, let filter = filter as? SortFilter {
                        if filter.value.index != target.value.index || filter.value.ascending != target.value.ascending {
                            update = true
                            break
                        }
                    } else {
                        if target.valueByPropertyName(name: "value") as? AnyHashable? != filter.valueByPropertyName(name: "value") as? AnyHashable? {
                            update = true
                            break
                        }
                    }
                } else {
                    update = true
                    break
                }
            }
        }
        if update {
            page = nil
            currentListing = nil
            DataManager.shared.setListing(for: source, listing: 0)
            Task {
                await fetchData()
                reloadData()
            }
        }
    }
}
