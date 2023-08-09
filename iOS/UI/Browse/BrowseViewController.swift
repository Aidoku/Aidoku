//
//  BrowseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import SwiftUI
import SafariServices

class BrowseViewController: BaseTableViewController {

    let viewModel = BrowseViewModel()

    lazy var dataSource = makeDataSource()

    private lazy var refreshControl = UIRefreshControl()
    private lazy var emptyStackView = EmptyPageStackView()

    override var tableViewStyle: UITableView.Style {
        .grouped
    }

    override func configure() {
        super.configure()

        title = NSLocalizedString("BROWSE", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        // search controller
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        // Initial navbar with migration and lang select buttons.
        self.updateNavBar()

        // configure table view
        tableView.dataSource = dataSource
        tableView.register(
            SourceTableViewCell.self,
            forCellReuseIdentifier: String(describing: SourceTableViewCell.self)
        )
        tableView.register(
            UITableViewHeaderFooterView.self,
            forHeaderFooterViewReuseIdentifier: String(describing: UITableViewHeaderFooterView.self)
        )
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.sectionFooterHeight = 8
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        refreshControl.addTarget(self, action: #selector(refreshSourceLists(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl

        // empty text
        emptyStackView.title = NSLocalizedString("BROWSE_NO_SOURCES", comment: "")
        emptyStackView.text = NSLocalizedString("BROWSE_NO_SOURCES_TEXT", comment: "")
        emptyStackView.buttonText = NSLocalizedString("ADDING_SOURCES_GUIDE_BUTTON", comment: "")
        emptyStackView.addButtonTarget(self, action: #selector(openGuidePage))
        emptyStackView.showsButton = true
        emptyStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStackView)

        // load data
        viewModel.loadInstalledSources()
        viewModel.loadPinnedSources()
        updateDataSource()
        Task {
            await viewModel.loadExternalSources()
            updateDataSource()
        }
    }

    override func constrain() {
        super.constrain()

        NSLayoutConstraint.activate([
            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func observe() {
        // update pinned list
        addObserver(forName: "updatePinnedList") { [weak self] _ in
            guard let self = self else { return }
            let snapshot = self.dataSource.snapshot()
            let sourceList = snapshot.itemIdentifiers(inSection: .pinned).map { $0.sourceId }
            UserDefaults.standard.set(sourceList, forKey: "Browse.pinnedList")
            
            if sourceList.count == 0 { self.stopEditing() }
            Task { @MainActor in
                self.viewModel.loadInstalledSources()
                self.viewModel.loadPinnedSources()
                self.viewModel.filterExternalSources()
                self.updateDataSource()
            }
        }
        // source installed/imported/pinned
        addObserver(forName: "updateSourceList") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.viewModel.loadInstalledSources()
                self.viewModel.loadPinnedSources()
                self.viewModel.filterExternalSources()
                if let query = self.navigationItem.searchController?.searchBar.text, !query.isEmpty {
                    self.viewModel.search(query: query)
                }
                self.updateDataSource()
            }
        }
        // source lists added/removed
        addObserver(forName: "updateSourceLists") { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.viewModel.loadExternalSources()
                self.updateDataSource()
            }
        }
        // show nsfw sources setting
        addObserver(forName: "Browse.showNsfwSources") { [weak self] _ in
            guard let self = self else { return }
            Task {
                self.viewModel.filterExternalSources()
                self.updateDataSource()
            }
        }
        // browse language selection
        addObserver(forName: "Browse.languages") { [weak self] _ in
            guard let self = self else { return }
            Task {
                self.viewModel.filterExternalSources()
                self.updateDataSource()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // fix refresh control snapping height
        refreshControl.didMoveToSuperview()

        // hack to show search bar on initial presentation
        if !navigationItem.hidesSearchBarWhenScrolling {
            navigationItem.hidesSearchBarWhenScrolling = true
        }
    }

    // store update count and display badge
    func checkUpdateCount() {
        let updateCount = viewModel.updatesSources.count
        UserDefaults.standard.set(updateCount, forKey: "Browse.updateCount")
        let tabBarItem = tabBarController?.tabBar.items?.first(
            where: { $0.title == NSLocalizedString("BROWSE", comment: "") }
        )
        tabBarItem?.badgeValue = updateCount > 0 ? String(updateCount) : nil
    }

    @objc func refreshSourceLists(_ refreshControl: UIRefreshControl? = nil) {
        Task {
            await viewModel.loadExternalSources()
            updateExternalSources()
            refreshControl?.endRefreshing()
        }
    }

    @objc func openGuidePage() {
        let safariViewController = SFSafariViewController(
            url: URL(string: "https://aidoku.app/help/guides/getting-started/#installing-a-source")!
        )
        present(safariViewController, animated: true)
    }

    @objc func openLanguageSelectPage() {
        present(UINavigationController(rootViewController: LanguageSelectViewController()), animated: true)
    }

    @objc func openMigrateSourcePage() {
        let migrateView = MigrateSourcesView()
        present(UIHostingController(rootView: SwiftUINavigationView(rootView: AnyView(migrateView))), animated: true)
    }

    @objc func stopEditing() {
        tableView.setEditing(false, animated: true)
        self.updateNavBar()
    }
}

// MARK: - Table View Delegate
extension BrowseViewController {
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .none
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if
            sectionIdentifier(for: indexPath.section) == .installed || sectionIdentifier(for: indexPath.section) == .pinned,
            let info = dataSource.itemIdentifier(for: indexPath),
            let source = SourceManager.shared.source(for: info.sourceId)
        {
            let vc = SourceViewController(source: source)
            navigationController?.pushViewController(vc, animated: true)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard
            let cell = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: String(describing: UITableViewHeaderFooterView.self)
            ),
            let currentSection = sectionIdentifier(for: section)
        else { return nil }
        var config = SmallSectionHeaderConfiguration()
        switch currentSection {
        case .updates:
            config.title = NSLocalizedString("UPDATES", comment: "")
        case .pinned:
            config.title = NSLocalizedString("PINNED", comment: "")
        case .installed:
            config.title = NSLocalizedString("INSTALLED", comment: "")
        case .external:
            config.title = NSLocalizedString("EXTERNAL", comment: "")
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return sectionIdentifier(for: indexPath.section) == .pinned
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return sectionIdentifier(for: indexPath.section) == .pinned
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // untested because I can't execute them
        let grabbedCell = self.viewModel.pinnedSources[sourceIndexPath.row]
        self.viewModel.pinnedSources.remove(at: sourceIndexPath.row)
        self.viewModel.pinnedSources.insert(grabbedCell, at: destinationIndexPath.row)
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            sectionIdentifier(for: indexPath.section) == .installed || sectionIdentifier(for: indexPath.section) == .pinned,
            let info = dataSource.itemIdentifier(for: indexPath),
            let source = SourceManager.shared.source(for: info.sourceId)
        else { return nil }
        if tableView.isEditing { return nil } // Hide context menu when the user is reshuffling sources.
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            var actions: [UIMenuElement] = []
            switch (self.sectionIdentifier(for: indexPath.section)) {
            case .installed:
                actions = [
                    UIAction(
                        title: NSLocalizedString("PINNED_PIN", comment: ""),
                        image: UIImage(systemName: "pin")
                    ) { _ in
                        SourceManager.shared.pin(source: source)
                        self.viewModel.loadPinnedSources()
                        self.updateDataSource()
                    }, UIAction(
                        title: NSLocalizedString("UNINSTALL", comment: ""),
                        image: UIImage(systemName: "trash")
                    ) { _ in
                        SourceManager.shared.remove(source: source)
                        self.viewModel.loadInstalledSources()
                        self.updateDataSource()
                    }
                ]
            case .pinned:
                actions = [
                    UIMenu(title: "", options: .displayInline, children: [UIAction(
                        title: NSLocalizedString("PINNED_SHUFFLE", comment: ""),
                        image: UIImage(systemName: "shuffle")
                    ) { _ in
                        tableView.setEditing(true, animated: true)
                        self.updateNavBar()
                    }]), UIAction(
                        title: NSLocalizedString("PINNED_UNPIN", comment: ""),
                        image: UIImage(systemName: "pin.slash")
                    ) { _ in
                        SourceManager.shared.unpin(source: source)
                        self.viewModel.loadPinnedSources()
                        self.updateDataSource()
                    }, UIAction(
                        title: NSLocalizedString("UNINSTALL", comment: ""),
                        image: UIImage(systemName: "trash")
                    ) { _ in
                        SourceManager.shared.remove(source: source)
                        self.viewModel.loadPinnedSources()
                        self.viewModel.loadInstalledSources()
                        self.updateDataSource()
                    }
                ]
            default:
                break
            }
            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Data Source
extension BrowseViewController {

    enum Section: Int {
        case pinned
        case updates
        case installed
        case external
    }
    
    // Ability to edit tableview for a diffable data source.
    class SourceCellDataSource: UITableViewDiffableDataSource<Section, SourceInfo2> {
        override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            if #available(iOS 15.0, *) {
                return sectionIdentifier(for: indexPath.section) == .pinned
            } else {
                return false
            }
        }
        
        override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            if #available(iOS 15.0, *) {
                return sectionIdentifier(for: indexPath.section) == .pinned
            } else {
                return false
            }
        }
        
        func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
                // Prevent rows from changing sections
                if sourceIndexPath.section != proposedDestinationIndexPath.section {
                    return sourceIndexPath
                } else {
                    return proposedDestinationIndexPath
                }
            }
        
        override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            guard let sourceItem = itemIdentifier(for: sourceIndexPath) else { return }
            guard sourceIndexPath != destinationIndexPath else { return }
            
            let destinationItem = itemIdentifier(for: destinationIndexPath)
            
            var snapshot = self.snapshot()
            
            if let destinationItem = destinationItem {
                if let sourceIndex = snapshot.indexOfItem(sourceItem),
                   let destinationIndex = snapshot.indexOfItem(destinationItem) {
                    
                    snapshot.deleteItems([sourceItem])
                    
                    if destinationIndex > sourceIndex {
                        snapshot.insertItems([sourceItem], afterItem: destinationItem)
                    }
                    else {
                        snapshot.insertItems([sourceItem], beforeItem: destinationItem)
                    }
                }
            }
            apply(snapshot, animatingDifferences: false)
            NotificationCenter.default.post(name: Notification.Name("updatePinnedList"), object: nil)
        }
        
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, SourceInfo2> {
        SourceCellDataSource(tableView: tableView) { [weak self] tableView, indexPath, info in
            guard
                let self = self,
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: String(describing: SourceTableViewCell.self)
                ) as? SourceTableViewCell,
                let section = self.sectionIdentifier(for: indexPath.section)
            else {
                return UITableViewCell()
            }
            cell.setSourceInfo(info)
            if info.externalInfo != nil {
                if section == .external {
                    cell.buttonTitle = NSLocalizedString("BUTTON_GET", comment: "")
                } else if section == .updates {
                    cell.buttonTitle = NSLocalizedString("BUTTON_UPDATE", comment: "")
                }
                cell.selectionStyle = .none
                cell.accessoryType = .none
            } else {
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            }
            return cell
        }
    }

    func updateDataSource() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SourceInfo2>()

        if !viewModel.updatesSources.isEmpty {
            snapshot.appendSections([.updates])
            snapshot.appendItems(viewModel.updatesSources, toSection: .updates)
        }
        if !viewModel.pinnedSources.isEmpty {
            snapshot.appendSections([.pinned])
            snapshot.appendItems(viewModel.pinnedSources, toSection: .pinned)
        }
        if !viewModel.installedSources.isEmpty {
            snapshot.appendSections([.installed])
            snapshot.appendItems(viewModel.installedSources, toSection: .installed)
        }
        if !viewModel.externalSources.isEmpty {
            snapshot.appendSections([.external])
            snapshot.appendItems(viewModel.externalSources, toSection: .external)
        }

        dataSource.apply(snapshot)

        Task { @MainActor in
            if navigationItem.searchController?.searchBar.text?.isEmpty ?? true {
                emptyStackView.isHidden = !snapshot.itemIdentifiers.isEmpty
            }
            checkUpdateCount()
        }
    }

    func updateExternalSources() {
        var snapshot = dataSource.snapshot()

        snapshot.deleteSections([.updates, .external])
        if !viewModel.updatesSources.isEmpty {
            if snapshot.indexOfSection(.installed) != nil {
                snapshot.insertSections([.updates], beforeSection: .installed)
            } else {
                snapshot.appendSections([.updates])
            }
            snapshot.appendItems(viewModel.updatesSources, toSection: .updates)
        }
        if !viewModel.externalSources.isEmpty {
            snapshot.appendSections([.external])
            snapshot.appendItems(viewModel.externalSources, toSection: .external)
        }

        if #available(iOS 15.0, *) {
            // prevents jumpiness from pull to refresh
            dataSource.applySnapshotUsingReloadData(snapshot)
        } else {
            dataSource.apply(snapshot)
        }

        Task { @MainActor in
            emptyStackView.isHidden = !snapshot.itemIdentifiers.isEmpty
            checkUpdateCount()
        }
    }

    /// Returns the identifier for the provided section index.
    private func sectionIdentifier(for section: Int) -> Section? {
        if #available(iOS 15.0, *) {
            return dataSource.sectionIdentifier(for: section)
        } else {
            guard section >= 0 else { return nil }
            let sections = dataSource.snapshot().sectionIdentifiers
            return sections.count > section ? sections[section] : nil
        }
    }
}

// MARK: - Search Results
extension BrowseViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        viewModel.search(query: searchController.searchBar.text)
        updateDataSource()
    }
}

// Updating view
extension BrowseViewController {
    func updateNavBar() {
        if tableView.isEditing {
            Task { @MainActor in
                navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(stopEditing))]
            }
        } else {
            let globeImage: UIImage?
            if #available(iOS 15.0, *) {
                globeImage = UIImage(systemName: "globe.americas.fill")
            } else {
                globeImage = UIImage(systemName: "globe")
            }
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(
                    image: globeImage,
                    style: .plain,
                    target: self,
                    action: #selector(openLanguageSelectPage)
                ),
                UIBarButtonItem(
                    image: UIImage(systemName: "arrow.left.arrow.right"),
                    style: .plain,
                    target: self,
                    action: #selector(openMigrateSourcePage)
                )
            ]
        }
    }
}
