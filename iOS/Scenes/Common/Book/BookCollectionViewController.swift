//
//  BookCollectionViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/1/22.
//

import UIKit

class BookCollectionViewController: BaseCollectionViewController {

    lazy var dataSource = makeDataSource()

    var itemSpacing: CGFloat = 12

    override func configure() {
        super.configure()
        collectionView.dataSource = dataSource
        collectionView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: 10,
            right: 0
        )
    }

    override func observe() {
        addObserver(forName: "General.portraitRows") { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }
        addObserver(forName: "General.landscapeRows") { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    // MARK: Cell Registration
    typealias CellRegistration = UICollectionView.CellRegistration<BookGridCell, BookInfo>

    func makeCellRegistration() -> CellRegistration {
        CellRegistration { cell, _, info in
            cell.sourceId = info.sourceId
            cell.bookId = info.bookId
            cell.title = info.title
            Task {
                await cell.loadImage(url: info.coverUrl)
            }
        }
    }

    // MARK: Collection View Layout
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            switch Section(rawValue: sectionIndex) {
            case .pinned, .regular:
                return self?.makeGridLayoutSection(environment: environment)
            case nil:
                return nil
            }
        }
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = itemSpacing
        layout.configuration = config
        return layout
    }
}

extension BookCollectionViewController {

    // TODO: list layout
//    func makeListLayoutSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
//    }

    func makeGridLayoutSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemsPerRow = UserDefaults.standard.integer(
            forKey: environment.container.contentSize.width > environment.container.contentSize.height
                ? "General.landscapeRows"
                : "General.portraitRows"
        )

        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1 / CGFloat(itemsPerRow)),
            heightDimension: .fractionalWidth(3 / (2 * CGFloat(itemsPerRow)))
        ))

        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(environment.container.contentSize.width * 3 / (2 * CGFloat(itemsPerRow)))
            ),
            subitem: item,
            count: itemsPerRow
        )

        group.interItemSpacing = .fixed(itemSpacing)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        section.interGroupSpacing = itemSpacing

        return section
    }
}

// MARK: - Collection View Delegate
extension BookCollectionViewController {

    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? BookGridCell {
            cell.highlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? BookGridCell {
            cell.unhighlight(animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let info = dataSource.itemIdentifier(for: indexPath) else { return }
        navigationController?.pushViewController(
            MangaViewController(manga: info.toBook().toManga(), chapters: []),
            animated: true
        )
    }
}

// MARK: - Data Source
extension BookCollectionViewController {

    enum Section: Int, CaseIterable {
        case pinned
        case regular
    }

    func makeDataSource() -> UICollectionViewDiffableDataSource<Section, BookInfo> {
        UICollectionViewDiffableDataSource(
            collectionView: collectionView,
            cellProvider: makeCellRegistration().cellProvider
        )
    }
}
