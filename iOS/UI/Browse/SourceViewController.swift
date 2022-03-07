//
//  SourceViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

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
    var filters: [Filter] = []

    var hasMore = false
    var page: Int?
    var query: String?
    var currentListing: Listing?
    let selectedFilters = SelectedFilters()

    var oldSelectedFilters: [Filter] = []

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

        title = source.info.name

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
                    action: #selector(openFilterPopover(_:))
                )
            )
        }
        navigationItem.rightBarButtonItems = items
    }

    @objc func resetFilters() {
        selectedFilters.filters = source.getDefaultFilters()
    }

    func fetchFilters() async {
        let reset = source.needsFilterRefresh
        filters = (try? await source.getFilters()) ?? []
        if selectedFilters.filters.isEmpty || reset {
            resetFilters()
        }
    }

    func fetchData() async {
        if listings.isEmpty {
            listings = (try? await source.getListings()) ?? []
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

    @objc func openFilterPopover(_ sender: UIBarButtonItem) {
        oldSelectedFilters = selectedFilters.filters

        let vc = FilterModalViewController(filters: filters, selectedFilters: selectedFilters)
        vc.delegate = self
        vc.resetButton.addTarget(self, action: #selector(resetFilters), for: .touchUpInside)
        vc.modalPresentationStyle = .overFullScreen
        present(vc, animated: false)
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
            options.append("All")
            header?.title = "List"
            header?.options = options
            header?.selectedOption = currentListing == nil ? listings.count : listings.firstIndex(of: currentListing!) ?? 0

            header?.filterButton.alpha = source.filterable ? 1 : 0
            header?.filterButton.addTarget(self, action: #selector(openFilterPopover(_:)), for: .touchUpInside)

            header?.delegate = self
            return header ?? UICollectionReusableView()
        }
        return UICollectionReusableView()
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
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
        if oldSelectedFilters != selectedFilters.filters {
            update = true
        } else {
            for filter in oldSelectedFilters {
                if let target = selectedFilters.filters.first(where: { filter.name == $0.name }) {
                    if filter.value as? SortOption != target.value as? SortOption {
                        update = true
                        break
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
