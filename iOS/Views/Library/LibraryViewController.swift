//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/29/22.
//

import UIKit

class LibraryViewController: MangaCollectionViewController {
    
    var unfilteredManga: [Manga] = [] {
        didSet {
            DispatchQueue.main.async {
                self.emptyTextStackView.isHidden = !self.unfilteredManga.isEmpty
                self.collectionView?.alwaysBounceVertical = !self.unfilteredManga.isEmpty
            }
        }
    }
    
    override var manga: [Manga] {
        get {
            unfilteredManga.filter { searchText.isEmpty ? true : $0.title?.lowercased().contains(searchText.lowercased()) ?? true }
        }
        set {
            unfilteredManga = newValue
        }
    }
    
    var searchText: String = ""
    
    let emptyTextStackView = UIStackView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Library"
        
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gear"),
            style: .plain,
            target: self,
            action: #selector(showSettings)
        )
        
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Find in Library"
        navigationItem.searchController = searchController
        
        opensReaderView = true
        
//        collectionView?.register(MangaListSelectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "MangaListSelectionHeader")
        
        emptyTextStackView.isHidden = true
        emptyTextStackView.axis = .vertical
        emptyTextStackView.distribution = .equalSpacing
        emptyTextStackView.spacing = 5
        emptyTextStackView.alignment = .center
        
        let emptyTitleLabel = UILabel()
        emptyTitleLabel.text = "Library Empty"
        emptyTitleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        emptyTitleLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTitleLabel)
        
        let emptyTextLabel = UILabel()
        emptyTextLabel.text = "Add manga from the browse tab"
        emptyTextLabel.font = .systemFont(ofSize: 15)
        emptyTextLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTextLabel)
        
        emptyTextStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyTextStackView)
        
        emptyTextStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        emptyTextStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        fetchLibrary()
        
        NotificationCenter.default.addObserver(forName: Notification.Name("updateLibrary"), object: nil, queue: nil) { _ in
            self.fetchLibrary()
        }
    }
    
//    override func viewWillAppear(_ animated: Bool) {
//        super.viewWillAppear(animated)
//        manga = DataManager.shared.libraryManga
//        collectionView?.reloadData()
//    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationItem.hidesSearchBarWhenScrolling = true
    }
    
    func fetchLibrary() {
        manga = DataManager.shared.libraryManga
        reloadData()
    }
    
    @objc func showSettings() {
        let settingsController = HostingController(rootView: SettingsView())
        present(settingsController, animated: true)
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController: UICollectionViewDelegateFlowLayout {
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
//        CGSize(width: collectionView.bounds.width, height: 40)
//    }
//
//    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
//        if kind == UICollectionView.elementKindSectionHeader {
//            var header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "MangaListSelectionHeader", for: indexPath) as? MangaListSelectionHeader
//            if header == nil {
//                header = MangaListSelectionHeader(frame: .zero)
//            }
//            header?.delegate = nil
//            header?.options = ["Default"]
//            header?.selectedOption = 0
//            header?.delegate = self
//            return header ?? UICollectionReusableView()
//        }
//        return UICollectionReusableView()
//    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didSelectItemAt: indexPath)
        DataManager.shared.setOpened(manga: manga[indexPath.row])
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: MangaListSelectionHeaderDelegate {
    func optionSelected(_ index: Int) {
        fetchLibrary()
    }
}

// MARK: - Search Results Updater
extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        collectionView?.reloadData()
    }
}
