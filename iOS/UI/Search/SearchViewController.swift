//
//  SearchViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/3/22.
//

import UIKit

class MangaCarouselHeader: UICollectionReusableView {

    let titleLabel = UILabel()
    let viewMoreButton = UIButton(type: .roundedRect)

    var title: String? {
        didSet {
            titleLabel.text = title
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutViews() {
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        viewMoreButton.setTitle("View More", for: .normal)
        viewMoreButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(viewMoreButton)

        titleLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor).isActive = true
        titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        viewMoreButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor).isActive = true
        viewMoreButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }
}

class SearchViewController: UIViewController {

    var sources: [Source] = []
    var results: [String: MangaPageResult] = [:]

    var collectionView: UICollectionView?

    var query: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Search"

        navigationController?.navigationBar.prefersLargeTitles = true

        sources = SourceManager.shared.sources.filter { $0.titleSearchable }

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        let config = UICollectionViewCompositionalLayoutConfiguration()
        let sectionProvider: UICollectionViewCompositionalLayoutSectionProvider = { sectionIndex, _ in
            let mangaCount: CGFloat = CGFloat(self.results[self.sources[sectionIndex].id]?.manga.count ?? 0)

            let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(120), heightDimension: .fractionalHeight(1))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(widthDimension: .estimated(120),
                                                   heightDimension: mangaCount > 0 ? .estimated(180) : .absolute(0))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16)
            section.interGroupSpacing = 10

            let headerItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(40))
            let headerItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerItemSize,
                                                                         elementKind: "header",
                                                                         alignment: .top)
            section.boundarySupplementaryItems = mangaCount > 0 ? [headerItem] : []

            return section
        }

        let layout = UICollectionViewCompositionalLayout(sectionProvider: sectionProvider, configuration: config)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView?.backgroundColor = .systemBackground
        collectionView?.delegate = self
        collectionView?.dataSource = self
        collectionView?.delaysContentTouches = false
        collectionView?.register(MangaCarouselHeader.self,
                                 forSupplementaryViewOfKind: "header",
                                 withReuseIdentifier: "MangaCarouselHeader")
        collectionView?.register(MangaCoverCell.self, forCellWithReuseIdentifier: "MangaCoverCell")
        collectionView?.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView ?? UICollectionView())

        collectionView?.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        collectionView?.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

        NotificationCenter.default.addObserver(forName: Notification.Name("updateSourceList"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.sources = SourceManager.shared.sources.filter { $0.titleSearchable }
                self.collectionView?.reloadData()
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("loadedSourceFilters"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.sources = SourceManager.shared.sources.filter { $0.titleSearchable }
                self.collectionView?.reloadData()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
        navigationController?.tabBarController?.tabBar.tintColor = UITabBar.appearance().tintColor
    }

    func reloadData() {
        self.collectionView?.reloadSections(IndexSet(integersIn: 0..<self.sources.count))
    }

    func openMangaView(for manga: Manga) {
        navigationController?.pushViewController(MangaViewController(manga: manga), animated: true)
    }

    @objc func openSearchView(_ sender: UIButton) {
        guard sources.count > sender.tag else { return }
        let source = sources[sender.tag]
        let vc = SourceViewController(source: source)
        vc.restrictToSearch = true
        vc.page = 1
        vc.query = query
        vc.hasMore = results[source.id]?.hasNextPage ?? false
        vc.manga = results[source.id]?.manga ?? []
        navigationController?.pushViewController(vc, animated: true)
    }

    @MainActor
    func fetchData() async {
        guard let query = query, !query.isEmpty else { return }
        // TODO: Make this run in parallel
        for (i, source) in sources.enumerated() {
            let search = try? await source.fetchSearchManga(query: query, page: 1)
            results[source.info.id] = search
            self.collectionView?.reloadSections(IndexSet(integer: i))
        }
    }
}

// MARK: - Collection View Data Source
extension SearchViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        results[sources[section].id]?.manga.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == "header" {
            var headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                             withReuseIdentifier: "MangaCarouselHeader",
                                                                             for: indexPath) as? MangaCarouselHeader
            if headerView == nil {
                headerView = MangaCarouselHeader(frame: .zero)
            }

            headerView?.title = sources[indexPath.section].info.name
            headerView?.viewMoreButton.addTarget(self, action: #selector(openSearchView(_:)), for: .touchUpInside)
            headerView?.viewMoreButton.tag = indexPath.section

            return headerView ?? MangaCarouselHeader()
        }
        return MangaCarouselHeader()
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MangaCoverCell", for: indexPath) as? MangaCoverCell
        if cell == nil {
            cell = MangaCoverCell(frame: .zero)
        }
        cell?.manga = results[sources[indexPath.section].id]?.manga[indexPath.row]
        return cell ?? UICollectionViewCell()
    }

}

// MARK: - Collection View Delegate
extension SearchViewController: UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sources.count
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let manga = results[sources[indexPath.section].id]?.manga[indexPath.row] {
            openMangaView(for: manga)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaCoverCell {
            cell.highlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaCoverCell {
            cell.unhighlight(animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            var actions: [UIAction] = []
            if let manga = self.results[self.sources[indexPath.section].id]?.manga[indexPath.row] {
                if DataManager.shared.libraryContains(manga: manga) {
                    actions.append(UIAction(title: "Remove from Library", image: UIImage(systemName: "trash")) { _ in
                        DataManager.shared.delete(manga: manga)
                    })
                } else {
                    actions.append(UIAction(title: "Add to Library", image: UIImage(systemName: "books.vertical.fill")) { _ in
                        Task { @MainActor in
                            if let manga = try? await SourceManager.shared.source(for: manga.sourceId)?.getMangaDetails(manga: manga) {
                                _ = DataManager.shared.addToLibrary(manga: manga)
                            }
                        }
                    })
                }
            }
            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Search Bar Delegate
extension SearchViewController: UISearchBarDelegate {

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard searchBar.text != query else { return }
        query = searchBar.text
        Task {
            await fetchData()
        }
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        query = nil
        results = [:]
        reloadData()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            query = nil
            results = [:]
            reloadData()
        }
    }
}
