//
//  SourceSearchViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

class SourceSearchViewController: MangaCollectionViewController {
    
    let source: Source
    var query: String?
    let selectedFilters: SelectedFilters
    
    let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    init(source: Source, query: String? = nil, selectedFilters: SelectedFilters) {
        self.source = source
        self.query = query
        self.selectedFilters = selectedFilters
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        title = "Search"
        navigationItem.largeTitleDisplayMode = .never
        
        let filterImage: UIImage?
        if #available(iOS 15.0, *) {
            filterImage = UIImage(systemName: "line.3.horizontal.decrease.circle")
        } else {
            filterImage = UIImage(systemName: "line.horizontal.3.decrease.circle")
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: filterImage,
            style: .plain,
            target: self,
            action: #selector(openFilterPopover(_:))
        )
        
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        navigationItem.searchController = searchController
        searchController.searchBar.text = query
        
        navigationItem.hidesSearchBarWhenScrolling = false
        
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        
        activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        Task {
            await doSearch()
            UIView.animate(withDuration: 0.3) {
                self.activityIndicator.alpha = 0
            }
            reloadData()
        }
    }
    
    func doSearch() async {
        let result = try? await source.fetchSearchManga(query: query ?? "", filters: selectedFilters.filters)
        manga = result?.manga ?? []
    }
    
    @objc func openFilterPopover(_ sender: UIBarButtonItem) {
        let vc = HostingController(rootView: SourceFiltersView(filters: source.filters, selectedFilters: selectedFilters))
        vc.preferredContentSize = CGSize(width: 300, height: 300)
        vc.modalPresentationStyle = .popover
        vc.presentationController?.delegate = self
        vc.popoverPresentationController?.permittedArrowDirections = .up
        vc.popoverPresentationController?.barButtonItem = sender
        present(vc, animated: true)
    }
}

// MARK: - Search Bar Delegate
extension SourceSearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard searchBar.text != query else { return }
        query = searchBar.text
        manga = []
        reloadData()
        activityIndicator.alpha = 1
        Task {
            await doSearch()
            UIView.animate(withDuration: 0.3) {
                self.activityIndicator.alpha = 0
            }
            reloadData()
        }
    }
}

// MARK: - Popover Delegate
extension SourceSearchViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task {
            await doSearch()
            reloadData()
        }
    }
}
