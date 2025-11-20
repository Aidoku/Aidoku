//
//  SourceSearchViewController.swift
//  Aidoku
//
//  Created by Skitty on 11/19/25.
//

import AidokuRunner
import Combine
import SwiftUI

class SourceSearchViewController: BaseCollectionViewController {
    let viewModel: SourceSearchViewModel

    var searchText: String = ""
    var enabledFilters: [FilterValue] = [] {
        didSet {
            if enabledFilters != oldValue {
                viewModel.loadManga(
                    searchText: searchText,
                    filters: enabledFilters,
                    force: true
                )
            }
        }
    }

    private lazy var dataSource = makeDataSource()
    private lazy var refreshControl = UIRefreshControl()
    private lazy var errorView = SourceErrorView()

    struct SkeletonView: View {
        var body: some View {
            HomeGridView.placeholder
        }
    }
    private lazy var skeletonViewController = {
        let hostingController = UIHostingController(rootView: SkeletonView())
        hostingController.view.backgroundColor = .clear
        hostingController.view.clipsToBounds = false
        return hostingController
    }()

    init(source: AidokuRunner.Source) {
        self.viewModel = .init(source: source)
        super.init()
    }

    override func configure() {
        super.configure()
        collectionView.dataSource = dataSource
        collectionView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: 10,
            right: 0
        )
        collectionView.keyboardDismissMode = .interactive

        // pull to refresh
        refreshControl.addTarget(self, action: #selector(refresh(_:)), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        errorView.onRetry = { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.viewModel.loadManga(
                searchText: self.searchText,
                filters: self.enabledFilters,
                force: true
            )
        }
        errorView.hide(animated: false)
        view.addSubview(errorView)

        addChild(skeletonViewController)
        collectionView.addSubview(skeletonViewController.view)
        skeletonViewController.didMove(toParent: self)
    }

    override func constrain() {
        super.constrain()

        errorView.translatesAutoresizingMaskIntoConstraints = false
        skeletonViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            skeletonViewController.view.topAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.topAnchor),
            skeletonViewController.view.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),
            skeletonViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func observe() {
        super.observe()

        viewModel.$loadingInitial
            .sink { [weak self] loading in
                guard let self, !loading else { return }

                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    self.skeletonViewController.view.alpha = 0
                } completion: { _ in
                    self.skeletonViewController.view.removeFromSuperview()
                    self.skeletonViewController.removeFromParent()
                }
            }
            .store(in: &cancellables)

        viewModel.$entries
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    if self.viewModel.error == nil {
                        self.updateDataSource()
                    }
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .sink { [weak self] error in
                guard let self else { return }
                if let error {
                    self.errorView.setError(error)
                    self.errorView.show()
                    self.clearEntries()
                } else {
                    self.errorView.hide()
                }
            }
            .store(in: &cancellables)

        viewModel.$shouldScrollToTop
            .sink { [weak self] shouldScroll in
                guard let self, shouldScroll else { return }
                self.scrollToTop()
                self.viewModel.shouldScrollToTop = false
            }
            .store(in: &cancellables)

        addObserver(forName: .init("refresh-content")) { [weak self] _ in
            guard let self else { return }
            self.viewModel.loadManga(
                searchText: self.searchText,
                filters: self.enabledFilters,
                force: true
            )
        }
    }

    // MARK: Collection View Layout
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            switch Section(rawValue: sectionIndex) {
                case .regular:
                    return MangaCollectionViewController.makeGridLayoutSection(environment: environment)
                case nil:
                    return nil
            }
        }
        let config = UICollectionViewCompositionalLayoutConfiguration()
        layout.configuration = config
        return layout
    }
}

extension SourceSearchViewController {
    func onAppear() {
        viewModel.onAppear(searchText: searchText, filters: enabledFilters)
    }

    func scrollToTop(animated: Bool = true) {
        collectionView.setContentOffset(.init(x: 0, y: -view.safeAreaInsets.top), animated: animated)
    }

    @objc func refresh(_ control: UIRefreshControl) {
        Task {
            viewModel.loadManga(searchText: searchText, filters: enabledFilters, force: true)
            await viewModel.waitForSearch()
            control.endRefreshing()
            scrollToTop() // it scrolls down slightly after refresh ends
        }
    }
}

extension SourceSearchViewController {
    // MARK: Cell Registration
    typealias CellRegistration = UICollectionView.CellRegistration<MangaGridCell, AidokuRunner.Manga>

    func makeCellRegistration() -> CellRegistration {
        CellRegistration { [weak self] cell, _, manga in
            cell.sourceId = manga.sourceKey
            cell.mangaId = manga.key
            cell.title = manga.title
            cell.showsBookmark = self?.viewModel.bookmarkedItems.contains(manga.key) ?? false
            Task {
                await cell.loadImage(url: manga.cover.flatMap { URL(string: $0) })
            }
        }
    }

    // MARK: Data Source
    enum Section: Int, CaseIterable {
        case regular
    }

    func makeDataSource() -> UICollectionViewDiffableDataSource<Section, AidokuRunner.Manga> {
        UICollectionViewDiffableDataSource(
            collectionView: collectionView,
            cellProvider: makeCellRegistration().cellProvider
        )
    }

    func updateDataSource() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, AidokuRunner.Manga>()
        snapshot.appendSections([.regular])
        snapshot.appendItems(viewModel.entries, toSection: .regular)
        dataSource.apply(snapshot)
    }

    func clearEntries() {
        dataSource.apply(.init())
    }
}

// MARK: UICollectionViewDelegate
extension SourceSearchViewController {
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaGridCell {
            cell.highlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaGridCell {
            cell.unhighlight(animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let manga = dataSource.itemIdentifier(for: indexPath) else { return }
        let viewController = MangaViewController(manga: manga, parent: self)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        let mangaCount = viewModel.entries.count
        let hasMore = viewModel.hasMore
        if indexPath.row == mangaCount - 1 && hasMore {
            Task {
                await viewModel.loadMore(searchText: searchText, filters: enabledFilters)
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            indexPaths.count == 1,
            let indexPath = indexPaths.first,
            let entry = dataSource.itemIdentifier(for: indexPath)
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ -> UIMenu? in
            guard let self else { return nil }

            var actions: [UIAction] = []

            if entry.isLocal() {
                actions.append(UIAction(
                    title: NSLocalizedString("REMOVE"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    Task {
                        await LocalFileManager.shared.removeManga(with: entry.key)
                        NotificationCenter.default.post(name: .init("refresh-content"), object: nil)
                    }
                })
            }

            let inLibrary = self.viewModel.bookmarkedItems.contains(entry.key)
            if inLibrary {
                actions.append(UIAction(
                    title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    // remove bookmark icon
                    self.viewModel.bookmarkedItems.remove(entry.key)
                    var snapshot = self.dataSource.snapshot()
                    snapshot.reloadItems([entry])
                    self.dataSource.apply(snapshot)
                    // remove from library
                    Task {
                        await MangaManager.shared.removeFromLibrary(
                            sourceId: entry.sourceKey,
                            mangaId: entry.key
                        )
                    }
                })
            } else {
                actions.append(UIAction(
                    title: NSLocalizedString("ADD_TO_LIBRARY"),
                    image: UIImage(systemName: "books.vertical.fill")
                ) { _ in
                    // add bookmark icon
                    self.viewModel.bookmarkedItems.insert(entry.key)
                    var snapshot = self.dataSource.snapshot()
                    snapshot.reloadItems([entry])
                    self.dataSource.apply(snapshot)
                    // add to library
                    Task {
                        await MangaManager.shared.addToLibrary(
                            sourceId: entry.sourceKey,
                            manga: entry,
                            fetchMangaDetails: true
                        )
                    }
                })
            }

            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: UISearchBarDelegate
extension SourceSearchViewController {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        viewModel.loadManga(
            searchText: searchText,
            filters: enabledFilters,
            delay: true
        )
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        viewModel.loadManga(
            searchText: searchText,
            filters: enabledFilters,
            force: true
        )
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchText = ""
        viewModel.loadManga(
            searchText: searchText,
            filters: enabledFilters
        )
    }
}
