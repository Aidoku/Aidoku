//
//  MangaCollectionViewController.swift
//  Aidoku
//
//  Created by Skitty on 11/19/25.
//

import AidokuRunner
import Combine
import SwiftUI

class MangaCollectionViewController: BaseCollectionViewController {
    var usesListLayout = false

    lazy var dataSource = makeDataSource()
    lazy var refreshControl = UIRefreshControl()
    lazy var errorView = SourceErrorView()

    var entries: [AidokuRunner.Manga] = []
    var bookmarkedItems: Set<String> = []

    struct SkeletonView: View {
        let usesListLayout: Bool

        var body: some View {
            if usesListLayout {
                PlaceholderMangaHomeList.mainView(itemCount: 10)
                    .redacted(reason: .placeholder)
                    .shimmering()
            } else {
                HomeGridView.placeholder
            }
        }
    }
    lazy var skeletonViewController = {
        let hostingController = UIHostingController(rootView: SkeletonView(usesListLayout: usesListLayout))
        hostingController.view.backgroundColor = .clear
        hostingController.view.clipsToBounds = false
        return hostingController
    }()

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

    // MARK: Collection View Layout
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            switch Section(rawValue: sectionIndex) {
                case .regular:
                    if self.usesListLayout {
                        return OldMangaCollectionViewController.makeListLayoutSection(environment: environment)
                    } else {
                        return OldMangaCollectionViewController.makeGridLayoutSection(environment: environment)
                    }
                case nil:
                    return nil
            }
        }
    }
}

extension MangaCollectionViewController {
    @objc func refresh(_ control: UIRefreshControl) {
        control.endRefreshing()
    }

    func hideLoadingView() {
        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.skeletonViewController.view.alpha = 0
        } completion: { _ in
            self.skeletonViewController.view.removeFromSuperview()
            self.skeletonViewController.removeFromParent()
        }
    }
}

extension MangaCollectionViewController {
    // MARK: Cell Registration
    typealias GridCellRegistration = UICollectionView.CellRegistration<MangaGridCell, AidokuRunner.Manga>
    typealias ListCellRegistration = UICollectionView.CellRegistration<MangaListCell, AidokuRunner.Manga>

    func makeGridCellRegistration() -> GridCellRegistration {
        GridCellRegistration { [weak self] cell, _, manga in
            cell.sourceId = manga.sourceKey
            cell.mangaId = manga.key
            cell.title = manga.title
            cell.showsBookmark = self?.bookmarkedItems.contains(manga.key) ?? false
            Task {
                await cell.loadImage(url: manga.cover.flatMap { URL(string: $0) })
            }
        }
    }

    func makeListCellRegistration() -> ListCellRegistration {
        ListCellRegistration { [weak self] cell, _, manga in
            cell.configure(with: manga, isBookmarked: self?.bookmarkedItems.contains(manga.key) ?? false)
        }
    }

    // MARK: Data Source
    enum Section: Int, CaseIterable {
        case regular
    }

    func makeDataSource() -> UICollectionViewDiffableDataSource<Section, AidokuRunner.Manga> {
        if usesListLayout {
            UICollectionViewDiffableDataSource(
                collectionView: collectionView,
                cellProvider: makeListCellRegistration().cellProvider
            )
        } else {
            UICollectionViewDiffableDataSource(
                collectionView: collectionView,
                cellProvider: makeGridCellRegistration().cellProvider
            )
        }
    }

    func updateDataSource() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, AidokuRunner.Manga>()
        snapshot.appendSections([.regular])
        snapshot.appendItems(entries, toSection: .regular)
        dataSource.apply(snapshot)
    }

    func clearEntries() {
        dataSource.apply(.init())
    }
}

// MARK: UICollectionViewDelegate
extension MangaCollectionViewController {
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? MangaGridCell {
            cell.highlight()
        } else if let cell = cell as? MangaListCell {
            cell.highlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? MangaGridCell {
            cell.unhighlight()
        } else if let cell = cell as? MangaListCell {
            cell.unhighlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let manga = dataSource.itemIdentifier(for: indexPath) else { return }
        let viewController = MangaViewController(manga: manga, parent: self)
        navigationController?.pushViewController(viewController, animated: true)
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

            let inLibrary = bookmarkedItems.contains(entry.key)
            if inLibrary {
                actions.append(UIAction(
                    title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    // remove bookmark icon
                    self.bookmarkedItems.remove(entry.key)
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
                    self.bookmarkedItems.insert(entry.key)
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

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        highlightPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        guard
            let cell = collectionView.cellForItem(at: indexPath),
            cell is MangaListCell
        else {
            return nil
        }

        // add some padding to list cell
        let parameters = UIPreviewParameters()
        let padding: CGFloat = 8
        let rect = cell.bounds.insetBy(dx: -padding, dy: -padding)
        parameters.visiblePath = UIBezierPath(roundedRect: rect, cornerRadius: 12)

        return UITargetedPreview(view: cell.contentView, parameters: parameters)
    }
}
