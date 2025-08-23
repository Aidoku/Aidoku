//
//  SearchViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/3/22.
//

import Foundation
import UIKit
import AidokuRunner
import SwiftUI

class MangaCarouselHeader: UICollectionReusableView {

    let titleLabel = UILabel()
    let viewMoreButton = UIButton(type: .roundedRect)

    var title: String? {
        didSet {
            titleLabel.text = title
        }
    }

    var contentRating: SourceContentRating? {
        didSet {
            setContentRatingTag(contentRating: contentRating)
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

        viewMoreButton.setTitle(NSLocalizedString("VIEW_MORE", comment: ""), for: .normal)
        viewMoreButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(viewMoreButton)

        titleLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor).isActive = true
        titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        viewMoreButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor).isActive = true
        viewMoreButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }

    private func setContentRatingTag(contentRating: SourceContentRating?) {
        guard contentRating != .safe else { return }

        let contentRatingTagContainer = UIView()
        let contentRatingTagLabel = UILabel()

        switch contentRating {
        case .containsNsfw:
            contentRatingTagLabel.text = "17+"
            contentRatingTagContainer.backgroundColor = UIColor.orange.withAlphaComponent(0.3)
        case .primarilyNsfw:
            contentRatingTagLabel.text = "18+"
            contentRatingTagContainer.backgroundColor = UIColor.red.withAlphaComponent(0.3)
        default:
            return
        }

        contentRatingTagContainer.layer.cornerRadius = 6
        contentRatingTagContainer.layer.masksToBounds = true

        contentRatingTagLabel.font = UIFont.systemFont(ofSize: 12)
        contentRatingTagLabel.textColor = .secondaryLabel
        contentRatingTagLabel.textAlignment = .center

        addSubview(contentRatingTagContainer)
        contentRatingTagContainer.addSubview(contentRatingTagLabel)

        contentRatingTagContainer.translatesAutoresizingMaskIntoConstraints = false
        contentRatingTagLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentRatingTagContainer.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            contentRatingTagContainer.centerYAnchor.constraint(equalTo: centerYAnchor),

            contentRatingTagLabel.topAnchor.constraint(equalTo: contentRatingTagContainer.topAnchor, constant: 3),
            contentRatingTagLabel.bottomAnchor.constraint(equalTo: contentRatingTagContainer.bottomAnchor, constant: -3),
            contentRatingTagLabel.leadingAnchor.constraint(equalTo: contentRatingTagContainer.leadingAnchor, constant: 5),
            contentRatingTagLabel.trailingAnchor.constraint(equalTo: contentRatingTagContainer.trailingAnchor, constant: -5)
        ])
    }
}

class SearchViewController: UIViewController {

    var sources: [AidokuRunner.Source] = []
    var results: [String: AidokuRunner.MangaPageResult] = [:]

    var collectionView: UICollectionView?

    var query: String?

    var hoveredCell: MangaCoverCell?
    var hovering = false

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SEARCH", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true

        sources = SourceManager.shared.sources

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        let config = UICollectionViewCompositionalLayoutConfiguration()
        let sectionProvider: UICollectionViewCompositionalLayoutSectionProvider = { sectionIndex, _ in
            let mangaCount: CGFloat = CGFloat(self.results[self.sources[sectionIndex].id]?.entries.count ?? 0)

            let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(120), heightDimension: .fractionalHeight(1))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(widthDimension: .estimated(120),
                                                   heightDimension: mangaCount > 0 ? .estimated(180) : .absolute(0.1))
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

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateSourceList"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sources = SourceManager.shared.sources
                self.collectionView?.reloadData()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("loadedSourceFilters"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sources = SourceManager.shared.sources
                self.collectionView?.reloadData()
            }
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        becomeFirstResponder()
        hoveredCell?.highlight()

        navigationController?.isToolbarHidden = true
        navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
        navigationController?.tabBarController?.tabBar.tintColor = UITabBar.appearance().tintColor
    }

    func reloadData() {
        self.collectionView?.reloadSections(IndexSet(integersIn: 0..<self.sources.count))
    }

    func openMangaView(for manga: AidokuRunner.Manga, source: AidokuRunner.Source) {
        let viewController = NewMangaViewController(source: source, manga: manga, parent: self)
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc func openSearchView(_ sender: UIButton) {
        guard sources.count > sender.tag else { return }
        let source = sources[sender.tag]
        if let legacySource = source.legacySource {
            let sourceController = SourceViewController(source: legacySource)
            sourceController.hidesListings = true
            sourceController.navigationItem.searchController?.searchBar.text = query
            Task {
                await sourceController.viewModel.setTitleQuery(query)
                await sourceController.viewModel.setCurrentPage(1)
                await sourceController.viewModel.setManga((results[source.id]?.entries ?? []).map { $0.toOld().toInfo() })
                await sourceController.viewModel.setHasMore(results[source.id]?.hasNextPage ?? false)
                navigationController?.pushViewController(sourceController, animated: true)
            }
        } else {
            let sourceController = NewSourceViewController(source: source, onlySearch: true, searchQuery: query)
            navigationController?.pushViewController(sourceController, animated: true)
        }
    }

    func fetchData() async {
        guard let query, !query.isEmpty else { return }

        // sources freeze if we run too many tasks concurrently, so we limit it
        let maxConcurrentTasks = 3

        await withTaskGroup(of: (Int, String, AidokuRunner.MangaPageResult?).self) { [sources] group in
            // add the initial tasks to the group
            for i in 0..<min(sources.count, maxConcurrentTasks) {
                let source = sources[i]
                group.addTask {
                    (i, source.id, try? await source.getSearchMangaList(query: query, page: 1, filters: []))
                }
            }

            var index = maxConcurrentTasks
            while let (i, id, result) = await group.next() {
                if index < sources.count {
                    // once a task completes, we can start a new one if there are still sources left
                    let source = sources[index]
                    group.addTask { [index] in
                        (index, source.id, try? await source.getSearchMangaList(query: query, page: 1, filters: []))
                    }
                    index += 1
                }
                self.updateResults(for: id, atIndex: i, result: result)
            }
        }
    }

    func updateResults(for id: String, atIndex i: Int, result: AidokuRunner.MangaPageResult?) {
        results[id] = result
        collectionView?.reloadSections(IndexSet(integer: i))
    }
}

// MARK: - Collection View Data Source
extension SearchViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        results[sources[section].id]?.entries.count ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        if kind == "header" {
            var headerView = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: "MangaCarouselHeader",
                for: indexPath
            ) as? MangaCarouselHeader
            if headerView == nil {
                headerView = MangaCarouselHeader(frame: .zero)
            }

            headerView?.title = sources[indexPath.section].name
            headerView?.contentRating = sources[indexPath.section].contentRating
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
        if let manga = results[sources[indexPath.section].id]?.entries[indexPath.row] {
            cell?.manga = manga.toOld()
            cell?.showsLibraryBadge = CoreDataManager.shared.hasLibraryManga(
                sourceId: manga.sourceKey,
                mangaId: manga.key
            )
        }
        return cell ?? UICollectionViewCell()
    }

}

// MARK: - Collection View Delegate
extension SearchViewController: UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sources.count
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let manga = results[sources[indexPath.section].id]?.entries[indexPath.row] {
            openMangaView(for: manga, source: sources[indexPath.section])
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

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            var actions: [UIAction] = []
            if let manga = self.results[self.sources[indexPath.section].id]?.entries[indexPath.row] {
                if CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceKey, mangaId: manga.key) {
                    actions.append(UIAction(
                        title: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: ""),
                        image: UIImage(systemName: "trash"),
                        attributes: .destructive
                    ) { _ in
                        Task {
                            await MangaManager.shared.removeFromLibrary(sourceId: manga.sourceKey, mangaId: manga.key)
                            (collectionView.cellForItem(at: indexPath) as? MangaCoverCell)?.showsLibraryBadge = false
                        }
                    })
                } else {
                    actions.append(UIAction(
                        title: NSLocalizedString("ADD_TO_LIBRARY", comment: ""),
                        image: UIImage(systemName: "books.vertical.fill")
                    ) { _ in
                        Task {
                            await MangaManager.shared.addToLibrary(
                                sourceId: manga.sourceKey,
                                manga: manga,
                                fetchMangaDetails: true
                            )
                            (collectionView.cellForItem(at: indexPath) as? MangaCoverCell)?.showsLibraryBadge = true
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

// MARK: - Key Handler
extension SearchViewController {
    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hoveredCell?.unhighlight()
        resignFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                title: NSLocalizedString("FOCUS_ITEM_LEFT"),
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("FOCUS_ITEM_RIGHT"),
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("FOCUS_ITEM_ABOVE"),
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("FOCUS_ITEM_BELOW"),
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("OPEN_FOCUS_ITEM"),
                action: #selector(enterKeyPressed),
                input: "\r",
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: NSLocalizedString("RESET_FOCUS"),
                action: #selector(escKeyPressed),
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            )
        ]
    }

    @objc func arrowKeyPressed(_ sender: UIKeyCommand) {
        guard let collectionView = collectionView, collectionView.numberOfSections > 0 else { return }
        if !hovering || hoveredCell == nil {
            hovering = true
            if hoveredCell == nil {
                hoveredCell = collectionView.cellForItem(at: IndexPath(row: 0, section: 0)) as? MangaCoverCell
            }
            hoveredCell?.highlight()
            return
        }
        guard let hoveredCell = hoveredCell, let hoveredIndexPath = collectionView.indexPath(for: hoveredCell) else { return }
        var position = hoveredIndexPath.row
        var section = hoveredIndexPath.section
        if sender.input == UIKeyCommand.inputUpArrow || sender.input == UIKeyCommand.inputDownArrow {
            guard let previousFirstIndexPath = collectionView.indexPathsForVisibleItems.filter({ $0.section == section }).sorted(by: <)[safe: 0]
                  else { return }
            section += sender.input == UIKeyCommand.inputUpArrow ? -1 : 1
            guard section >= 0, section < collectionView.numberOfSections else { return }
            collectionView.scrollToItem(at: IndexPath(row: 0, section: section), at: .centeredVertically, animated: true)
            guard let newFirstIndexPath = collectionView.indexPathsForVisibleItems.filter({ $0.section == section }).sorted(by: <)[safe: 0]
                  else { return }
            position += newFirstIndexPath.row - previousFirstIndexPath.row
        } else if sender.input == UIKeyCommand.inputLeftArrow || sender.input == UIKeyCommand.inputRightArrow {
            position += sender.input == UIKeyCommand.inputLeftArrow ? -1 : 1
            guard position >= 0, collectionView.indexPathsForVisibleItems.contains(IndexPath(row: position, section: section)) else { return }
        } else {
            return
        }
        position = min(position, collectionView.numberOfItems(inSection: section))
        let newHoveredIndexPath = IndexPath(row: position, section: section)
        hoveredCell.unhighlight()
        (collectionView.cellForItem(at: newHoveredIndexPath) as? MangaCoverCell)?.highlight()
        collectionView.scrollToItem(at: newHoveredIndexPath, at: [.centeredVertically, .centeredHorizontally], animated: true)
        collectionView.accessibilityScroll(.down)
        self.hoveredCell = (collectionView.cellForItem(at: newHoveredIndexPath) as? MangaCoverCell)
    }

    @objc func enterKeyPressed() {
        guard let collectionView = collectionView, let hoveredCell = hoveredCell,
              let hoveredIndexPath = collectionView.indexPath(for: hoveredCell) else { return }
        self.collectionView(collectionView, didSelectItemAt: hoveredIndexPath)
    }

    @objc func escKeyPressed() {
        guard let hoveredCell = hoveredCell else { return }
        hoveredCell.unhighlight()
        hovering = false
        self.hoveredCell = nil
    }
}
