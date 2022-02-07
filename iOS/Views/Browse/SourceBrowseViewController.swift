//
//  SourceBrowseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import SwiftUI

class SourceBrowseViewController: MangaCollectionViewController {
    
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
    
    var hasMore: Bool = false
    var page: Int? = nil
    var query: String? = nil
    var currentListing: Listing?
    let selectedFilters = SelectedFilters()
    
    var oldSelectedFilters: [Filter] = []
    
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
        
        let filterImage: UIImage?
        if #available(iOS 15.0, *) {
            filterImage = UIImage(systemName: "line.3.horizontal.decrease.circle")
        } else {
            filterImage = UIImage(systemName: "line.horizontal.3.decrease.circle")
        }
        let ellipsisButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: nil)
        ellipsisButton.isEnabled = false
        
        var items = [ellipsisButton]
        if source.filterable {
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
        
        collectionView?.register(MangaListSelectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "MangaListSelectionHeader")
        
        if source.titleSearchable {
            let searchController = UISearchController(searchResultsController: nil)
            searchController.searchBar.delegate = self
//            searchController.hidesNavigationBarDuringPresentation = false
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
            if filters.isEmpty {
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
    
    func fetchFilters() async {
        filters = (try? await source.getFilters()) ?? []
        if selectedFilters.filters.isEmpty {
            selectedFilters.filters = source.getDefaultFilters()
        }
    }
    
    func fetchData() async {
        if listings.isEmpty {
            listings = (try? await source.getListings()) ?? []
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
    
    @objc func openFilterPopover(_ sender: UIBarButtonItem) {
        oldSelectedFilters = selectedFilters.filters
        let vc = UIHostingController(rootView: SourceFiltersView(filters: filters, selectedFilters: selectedFilters))
        vc.preferredContentSize = CGSize(width: 300, height: 300)
        vc.modalPresentationStyle = .popover
        vc.presentationController?.delegate = self
        vc.popoverPresentationController?.permittedArrowDirections = .up
        vc.popoverPresentationController?.barButtonItem = sender
        present(vc, animated: true)
    }
}

// MARK: - Collection View Delegate
extension SourceBrowseViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        restrictToSearch || listings.isEmpty ? .zero : CGSize(width: collectionView.bounds.width, height: 40)
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader {
            var header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "MangaListSelectionHeader", for: indexPath) as? MangaListSelectionHeader
            if header == nil {
                header = MangaListSelectionHeader(frame: .zero)
            }
            header?.delegate = nil
            var options = listings.map { $0.name }
            options.append("All")
            header?.title = "List"
            header?.options = options
            header?.selectedOption = currentListing == nil ? listings.count : listings.firstIndex(of: currentListing!) ?? 0
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
extension SourceBrowseViewController: MangaListSelectionHeaderDelegate {
    
    func optionSelected(_ index: Int) {
        if index == listings.count {
            currentListing = nil
        } else {
            currentListing = listings[index]
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
extension SourceBrowseViewController: UISearchBarDelegate {
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard searchBar.text != query else { return }
        query = searchBar.text
        currentListing = nil
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

// MARK: - Popover Delegate
extension SourceBrowseViewController: UIPopoverPresentationControllerDelegate {
    
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
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
            Task {
                await fetchData()
                reloadData()
            }
        }
    }
}
