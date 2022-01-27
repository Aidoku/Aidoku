//
//  SourceBrowseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

class SourceBrowseViewController: MangaCollectionViewController {
    
    let source: Source
    
    var listings: [Listing] = []
    var filters: [Filter] = []
    
    var currentListing: Listing?
    let selectedFilters = SelectedFilters()
    
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
        navigationController?.navigationBar.prefersLargeTitles = true
        
        let filterImage: UIImage?
        if #available(iOS 15.0, *) {
            filterImage = UIImage(systemName: "line.3.horizontal.decrease.circle")
        } else {
            filterImage = UIImage(systemName: "line.horizontal.3.decrease.circle")
        }
        let ellipsisButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: nil)
        ellipsisButton.isEnabled = false
        navigationItem.rightBarButtonItems = [
            ellipsisButton,
            UIBarButtonItem(
                image: filterImage,
                style: .plain,
                target: self,
                action: #selector(openFilterPopover(_:))
            )
        ]
        
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        navigationItem.searchController = searchController
        
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        Task {
            await fetchData()
            UIView.animate(withDuration: 0.3) {
                activityIndicator.alpha = 0
            }
            reloadData()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationItem.hidesSearchBarWhenScrolling = true
    }
    
    override func viewLayoutMarginsDidChange() {
        if let layout = collectionView?.collectionViewLayout as? MangaGridFlowLayout {
            layout.sectionInset = UIEdgeInsets(top: 0, left: view.layoutMargins.left, bottom: 10, right: view.layoutMargins.right)
        }
    }
    
    func fetchData() async {
        if filters.isEmpty {
            filters = (try? await source.getFilters()) ?? []
            if selectedFilters.filters.isEmpty {
                selectedFilters.filters = source.getDefaultFilters()
            }
        }
        if listings.isEmpty {
            listings = (try? await source.getListings()) ?? []
        }
        if currentListing == nil {
            currentListing = listings.first
        }
        if let listing = currentListing {
            manga = (try? await source.getMangaListing(listing: listing, filters: selectedFilters.filters))?.manga ?? []
        }
    }
    
    @objc func openFilterPopover(_ sender: UIBarButtonItem) {
        let vc = HostingController(rootView: SourceFiltersView(filters: filters, selectedFilters: selectedFilters))
        vc.preferredContentSize = CGSize(width: 300, height: 300)
        vc.modalPresentationStyle = .popover
        vc.presentationController?.delegate = self
        vc.popoverPresentationController?.permittedArrowDirections = .up
        vc.popoverPresentationController?.barButtonItem = sender
        present(vc, animated: true)
    }
}

// MARK: - Search Bar Delegate
extension SourceBrowseViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let vc = SourceSearchViewController(source: source, query: searchBar.text, selectedFilters: selectedFilters)
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - Popover Delegate
extension SourceBrowseViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task {
            await fetchData()
            reloadData()
        }
    }
}
