//
//  MangaCollectionViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/1/22.
//

import UIKit

class MangaCollectionViewController: BaseCollectionViewController {

    lazy var dataSource = makeDataSource()

    var itemSpacing: CGFloat = 12
    var sectionSpacing: CGFloat = 6 // extra spacing betweeen sections

    private var focusedIndexPath: IndexPath? {
        didSet {
            if let oldValue {
                collectionView(collectionView, didUnhighlightItemAt: oldValue)
            }
            if let focusedIndexPath {
                collectionView(collectionView, didHighlightItemAt: focusedIndexPath)
            }
        }
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
    typealias CellRegistration = UICollectionView.CellRegistration<MangaGridCell, MangaInfo>

    func makeCellRegistration() -> CellRegistration {
        CellRegistration { cell, _, info in
            cell.sourceId = info.sourceId
            cell.mangaId = info.mangaId
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
        config.interSectionSpacing = itemSpacing + sectionSpacing
        layout.configuration = config
        return layout
    }
}

extension MangaCollectionViewController {

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
extension MangaCollectionViewController {

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
        guard let info = dataSource.itemIdentifier(for: indexPath) else { return }
        let vc = MangaViewController(manga: info.toManga().toNew(), parent: self)
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - Data Source
extension MangaCollectionViewController {

    enum Section: Int, CaseIterable {
        case pinned
        case regular
    }

    func makeDataSource() -> UICollectionViewDiffableDataSource<Section, MangaInfo> {
        UICollectionViewDiffableDataSource(
            collectionView: collectionView,
            cellProvider: makeCellRegistration().cellProvider
        )
    }
}

// MARK: - Keyboard Shortcuts
extension MangaCollectionViewController {
    override var canBecomeFirstResponder: Bool { true }

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
                action: #selector(escapeKeyPressed),
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            )
        ]
    }

    @objc func escapeKeyPressed() {
        focusedIndexPath = nil
    }

    @objc func enterKeyPressed() {
        guard let focusedIndexPath else { return }
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: focusedIndexPath)
    }

    @objc func arrowKeyPressed(_ sender: UIKeyCommand) {
        guard let focusedIndexPath else {
            self.focusedIndexPath = IndexPath(item: 0, section: 0)
            return
        }

        var position = focusedIndexPath.row
        var section = focusedIndexPath.section
        let itemsPerRow = UserDefaults.standard.integer(
            forKey: UIScreen.main.bounds.width > UIScreen.main.bounds.height
                ? "General.landscapeRows"
                : "General.portraitRows"
        )
        switch sender.input {
            case UIKeyCommand.inputLeftArrow: position -= 1
            case UIKeyCommand.inputRightArrow: position += 1
            case UIKeyCommand.inputUpArrow: position -= itemsPerRow
            case UIKeyCommand.inputDownArrow: position += itemsPerRow
            default: return
        }
        if position < 0 {
            guard section > 0 else { return }
            section -= 1
            let itemsInPrevSection = collectionView.numberOfItems(inSection: section)
            position += itemsInPrevSection / itemsPerRow * itemsPerRow
            if position < itemsInPrevSection - itemsPerRow {
                position += itemsPerRow
            }
        } else if position >= collectionView.numberOfItems(inSection: section) {
            guard section < collectionView.numberOfSections - 1 else { return }
            section += 1
            position -= collectionView.numberOfItems(inSection: section - 1) / itemsPerRow * itemsPerRow
            if position >= itemsPerRow {
               position -= itemsPerRow
            }
        }

        position = min(position, collectionView.numberOfItems(inSection: section) - 1)
        let newFocusedndexPath = IndexPath(row: position, section: section)

        self.collectionView.scrollToItem(at: newFocusedndexPath, at: .centeredVertically, animated: true)
        self.focusedIndexPath = newFocusedndexPath
    }
}
