//
//  MangaCollectionViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

class MangaCollectionViewController: UIViewController {

    enum MangaCellBadgeType {
        case none
        case unread
        case downloaded
    }

    var collectionView: UICollectionView!
    var manga: [Manga] = []
    var pinnedManga: [Manga] = []

    var chapters: [String: [Chapter]] = [:]
    var badges: [String: Int] = [:]

    var hoveredCell: MangaCoverCell?
    var hovering = false

    var cellsPerRow: Int {
        UserDefaults.standard.integer(
            forKey: view.bounds.width > view.bounds.height ? "General.landscapeRows" : "General.portraitRows"
        )
    }

    var badgeType: MangaCellBadgeType = .none {
        didSet {
            if badgeType == .none {
                badges = [:]
                for i in 0..<manga.count {
                    if let cell = collectionView?.cellForItem(at: IndexPath(row: i, section: 0)) as? MangaCoverCell {
                        cell.badgeNumber = nil
                    }
                }
            }
        }
    }

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: MangaGridFlowLayout(
            cellsPerRow: cellsPerRow,
            minimumInteritemSpacing: 12,
            minimumLineSpacing: 12,
            sectionInset: UIEdgeInsets(top: 0, left: view.layoutMargins.left, bottom: 10, right: view.layoutMargins.right)
        ))
        collectionView?.backgroundColor = .systemBackground
        collectionView?.delegate = self
        collectionView?.dataSource = self
        collectionView?.delaysContentTouches = false
        collectionView?.alwaysBounceVertical = true
        collectionView?.register(MangaCoverCell.self, forCellWithReuseIdentifier: "MangaCoverCell")
        collectionView?.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView ?? UICollectionView())

        collectionView?.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        collectionView?.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        collectionView?.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        collectionView?.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("General.portraitRows"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                (self.collectionView?.collectionViewLayout as? MangaGridFlowLayout)?.cellsPerRow = self.cellsPerRow
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("General.landscapeRows"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                (self.collectionView?.collectionViewLayout as? MangaGridFlowLayout)?.cellsPerRow = self.cellsPerRow
            }
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        becomeFirstResponder()

        navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
        navigationController?.tabBarController?.tabBar.tintColor = UITabBar.appearance().tintColor
    }

    override func viewLayoutMarginsDidChange() {
        if let layout = collectionView?.collectionViewLayout as? MangaGridFlowLayout {
            layout.sectionInset = UIEdgeInsets(top: 0, left: view.layoutMargins.left, bottom: 10, right: view.layoutMargins.right)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let cellsPerRow = UserDefaults.standard.integer(
            forKey: size.width > size.height ? "General.landscapeRows" : "General.portraitRows"
        )

        collectionView?.collectionViewLayout = MangaGridFlowLayout(
            cellsPerRow: cellsPerRow,
            minimumInteritemSpacing: 12,
            minimumLineSpacing: 12,
            sectionInset: UIEdgeInsets(top: 0, left: view.layoutMargins.left, bottom: 10, right: view.layoutMargins.right)
        )
    }

    func reloadData() {
        Task { @MainActor in
            if collectionView?.numberOfSections == 1 && !pinnedManga.isEmpty { // insert pinned section
                collectionView?.performBatchUpdates {
                    collectionView?.insertSections(IndexSet(integer: 0))
                }
            } else if collectionView?.numberOfSections == 2 && pinnedManga.isEmpty { // remove pinned section
                collectionView?.performBatchUpdates {
                    collectionView?.deleteSections(IndexSet(integer: 0))
                }
            } else { // reload all sections
                collectionView?.performBatchUpdates {
                    if collectionView?.numberOfSections == 1 {
                        collectionView?.reloadSections(IndexSet(integer: 0))
                    } else {
                        collectionView?.reloadSections(IndexSet(integersIn: 0...1))
                    }
                }
            }
        }
    }

    func openMangaView(for manga: Manga) {
        navigationController?.pushViewController(
            MangaViewController(manga: manga, chapters: chapters["\(manga.sourceId).\(manga.id)"] ?? []),
            animated: true
        )
    }
}

// MARK: - Collection View Data Source
extension MangaCollectionViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 && !pinnedManga.isEmpty ? pinnedManga.count : manga.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MangaCoverCell", for: indexPath) as? MangaCoverCell
        if cell == nil {
            cell = MangaCoverCell(frame: .zero)
        }
        if indexPath.section == 0 && pinnedManga.count > indexPath.row || manga.count > indexPath.row {
            let targetManga = indexPath.section == 0 && pinnedManga.count > indexPath.row ? pinnedManga[indexPath.row] : manga[indexPath.row]
            cell?.manga = targetManga
            cell?.badgeNumber = badges["\(targetManga.sourceId).\(targetManga.id)"]
        }
        return cell ?? UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.section == 0 && pinnedManga.count > indexPath.row || manga.count > indexPath.row {
            let targetManga = indexPath.section == 0 && pinnedManga.count > indexPath.row ? pinnedManga[indexPath.row] : manga[indexPath.row]
            (cell as? MangaCoverCell)?.badgeNumber = badges["\(targetManga.sourceId).\(targetManga.id)"]
        }
    }
}

// MARK: - Collection View Delegate
extension MangaCollectionViewController: UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        pinnedManga.isEmpty ? 1 : 2
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == 0 && pinnedManga.count > indexPath.row {
            openMangaView(for: pinnedManga[indexPath.row])
        } else {
            if manga.count > indexPath.row {
                openMangaView(for: manga[indexPath.row])
            }
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
        let targetManga: Manga
        if indexPath.section == 0 && !pinnedManga.isEmpty {
            guard pinnedManga.count > indexPath.row else { return nil }
            targetManga = pinnedManga[indexPath.row]
        } else {
            guard manga.count > indexPath.row else { return nil }
            targetManga = manga[indexPath.row]
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            var actions: [UIAction] = []

            if DataManager.shared.libraryContains(manga: targetManga) {
                actions.append(UIAction(
                    title: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: ""),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    Task.detached {
                        DataManager.shared.delete(manga: targetManga, context: DataManager.shared.backgroundContext)
                    }
                    (collectionView.cellForItem(at: indexPath) as? MangaCoverCell)?.showsLibraryBadge = false
                })
            } else {
                actions.append(UIAction(
                    title: NSLocalizedString("ADD_TO_LIBRARY", comment: ""),
                    image: UIImage(systemName: "books.vertical.fill")
                ) { _ in
                    Task.detached {
                        if let newManga = try? await SourceManager.shared.source(for: targetManga.sourceId)?.getMangaDetails(manga: targetManga) {
                            DataManager.shared.addToLibrary(manga: newManga, context: DataManager.shared.backgroundContext)
                        }
                    }
                    (collectionView.cellForItem(at: indexPath) as? MangaCoverCell)?.showsLibraryBadge = true
                })
            }
            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Key Handler
extension MangaCollectionViewController {
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
                title: "Select Item to the Left",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Select Item to the Right",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Select Item Above",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Select Item Below",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Open Selected Item",
                action: #selector(enterKeyPressed),
                input: "\r",
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Clear Selection",
                action: #selector(escKeyPressed),
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            )
        ]
    }

    // swiftlint:disable:next cyclomatic_complexity
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
        switch sender.input {
        case UIKeyCommand.inputLeftArrow: position -= 1
        case UIKeyCommand.inputRightArrow: position += 1
        case UIKeyCommand.inputUpArrow: position -= cellsPerRow
        case UIKeyCommand.inputDownArrow: position += cellsPerRow
        default: return
        }
        if position < 0 {
            guard section > 0 else { return }
            section -= 1
            position += collectionView.numberOfItems(inSection: section) / cellsPerRow * cellsPerRow
            if position < collectionView.numberOfItems(inSection: section) - cellsPerRow {
                position += cellsPerRow
            }
        } else if position >= collectionView.numberOfItems(inSection: section) {
            guard section < collectionView.numberOfSections - 1 else { return }
            section += 1
            position -= collectionView.numberOfItems(inSection: section - 1) / cellsPerRow * cellsPerRow
            if position >= cellsPerRow {
               position -= cellsPerRow
            }
        }
        position = min(position, collectionView.numberOfItems(inSection: section) - 1)
        let newHoveredIndexPath = IndexPath(row: position, section: section)
        guard collectionView.indexPathsForVisibleItems.contains(newHoveredIndexPath) else { return }
        hoveredCell.unhighlight()
        (collectionView.cellForItem(at: newHoveredIndexPath) as? MangaCoverCell)?.highlight()
        collectionView.scrollToItem(at: newHoveredIndexPath, at: .centeredVertically, animated: true)
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
