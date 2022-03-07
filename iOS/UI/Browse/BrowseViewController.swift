//
//  BrowseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

class SourceSectionHeaderView: UITableViewHeaderFooterView {

    let title = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        configureContents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureContents() {
        title.font = .systemFont(ofSize: 16, weight: .medium)
        title.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(title)

        NSLayoutConstraint.activate([
            title.heightAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}

class BrowseViewController: UIViewController {

    let tableView = UITableView(frame: .zero, style: .grouped)

    let sourceURL = "https://sources.aidoku.app"

    var sources = SourceManager.shared.sources {
        didSet {
            reloadData()
        }
    }
    var updates: [ExternalSourceInfo] = [] {
        didSet {
            reloadData()
        }
    }
    var externalSources: [ExternalSourceInfo] = [] {
        didSet {
            reloadData()
        }
    }
    var installableSources: [ExternalSourceInfo] {
        externalSources.filter { !SourceManager.shared.hasSourceInstalled(id: $0.id) }
    }

    var searchText: String = ""

    var filteredSources: [Source] {
        sources.filter { searchText.isEmpty ? true : $0.info.name.lowercased().contains(searchText.lowercased()) }
    }
    var filteredUpdates: [ExternalSourceInfo] {
        updates.filter {
            if let appVersion = Float(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
                if let maxVersion = $0.maxAppVersion {
                    guard Float(maxVersion) ?? 0 >= appVersion else { return false }
                }
                if let minVersion = $0.minAppVersion {
                    guard Float(minVersion) ?? 0 <= appVersion else { return false }
                }
            }
            return searchText.isEmpty ? true : $0.name.lowercased().contains(searchText.lowercased())
        }
    }
    var filteredInstallableSources: [ExternalSourceInfo] {
        installableSources.filter {
            let showNsfw = UserDefaults.standard.bool(forKey: "Browse.showNsfwSources")
            if !showNsfw && $0.nsfw ?? 0 > 1 {
                return false
            } else if searchText.isEmpty {
                return true
            } else {
                return $0.name.lowercased().contains(searchText.lowercased())
            }
        }
    }

    var hasSources: Bool {
        !filteredSources.isEmpty
    }
    var hasUpdates: Bool {
        !filteredUpdates.isEmpty
    }
    var hasExternalSources: Bool {
        !filteredInstallableSources.isEmpty
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Browse"

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.separatorStyle = .none
        tableView.delaysContentTouches = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SourceTableViewCell.self, forCellReuseIdentifier: "SourceTableViewCell")
        tableView.register(SourceSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: "SourceSectionHeaderView")
        tableView.backgroundColor = .systemBackground
        view.addSubview(tableView)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        tableView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

        NotificationCenter.default.addObserver(forName: Notification.Name("updateSourceList"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.sources = SourceManager.shared.sources
                self.fetchUpdates()
            }
        }

        if externalSources.isEmpty {
            Task {
                var sources = (try? await URLSession.shared.object(
                    from: URL(string: "\(sourceURL)/index.min.json")!
                ) as [ExternalSourceInfo]?) ?? []
                sources.sort { $0.name < $1.name }
                externalSources = sources
                fetchUpdates()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
        navigationController?.tabBarController?.tabBar.tintColor = UITabBar.appearance().tintColor
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationItem.hidesSearchBarWhenScrolling = true
    }

    func reloadData() {
        UIView.transition(with: tableView,
                          duration: 0.3,
                          options: .transitionCrossDissolve,
                          animations: { self.tableView.reloadData() })
    }

    func fetchUpdates() {
        var newUpdates: [ExternalSourceInfo] = []
        for source in externalSources {
            if let installedSource = SourceManager.shared.source(for: source.id) {
                if source.version > installedSource.info.version {
                    newUpdates.append(source)
                }
            }
        }
        updates = newUpdates
    }
}

// MARK: - Table View Data Source
extension BrowseViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        (hasUpdates ? 1 : 0) + (hasSources ? 1 : 0) + (hasExternalSources ? 1 : 0)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        20
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        8
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SourceSectionHeaderView") as? SourceSectionHeaderView
        guard let view = view else { return nil }
        if section == 0 && hasUpdates {
            view.title.text = "Updates"
        } else if (section == 0 && hasSources && !hasUpdates) || (section == 1 && hasSources && hasUpdates) {
            view.title.text = "Installed"
        } else if (section == 0 && !hasSources && !hasUpdates)
                    || (section == 1 && hasSources && !hasUpdates)
                    || (section == 1 && !hasSources && hasUpdates)
                    || (section == 2 && hasSources && hasUpdates) {
            view.title.text = "External"
        }
        return view
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 && hasUpdates {
            return filteredUpdates.count
        } else if (section == 0 && hasSources && !hasUpdates) || (section == 1 && hasSources && hasUpdates) {
            return filteredSources.count
        } else if (section == 0 && !hasSources && !hasUpdates)
                    || (section == 1 && hasSources && !hasUpdates)
                    || (section == 1 && !hasSources && hasUpdates)
                    || (section == 2 && hasSources && hasUpdates) {
            return filteredInstallableSources.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 && hasUpdates {
            var cell = tableView.dequeueReusableCell(withIdentifier: "ExternalSourceTableViewCell") as? ExternalSourceTableViewCell
            if cell == nil {
                cell = ExternalSourceTableViewCell(style: .default,
                                                   reuseIdentifier: "ExternalSourceTableViewCell",
                                                   sourceURL: sourceURL)
            }
            guard let cell = cell else { return UITableViewCell() }

            cell.source = filteredUpdates[indexPath.row]
            cell.getButton.title = "UPDATE"
            cell.buttonWidth = 84

            return cell
        } else if (indexPath.section == 0 && hasSources && !hasUpdates) || (indexPath.section == 1 && hasSources && hasUpdates) {
            var cell = tableView.dequeueReusableCell(withIdentifier: "SourceTableViewCell") as? SourceTableViewCell
            if cell == nil {
                cell = SourceTableViewCell(style: .default, reuseIdentifier: "SourceTableViewCell")
            }
            guard let cell = cell else { return UITableViewCell() }
            if indexPath.row < filteredSources.count {
                cell.source = filteredSources[indexPath.row]
            }

            return cell
        } else if (indexPath.section == 0 && !hasSources && !hasUpdates)
                    || (indexPath.section == 1 && hasSources && !hasUpdates)
                    || (indexPath.section == 1 && !hasSources && hasUpdates)
                    || (indexPath.section == 2 && hasSources && hasUpdates) {
            var cell = tableView.dequeueReusableCell(withIdentifier: "ExternalSourceTableViewCell") as? ExternalSourceTableViewCell
            if cell == nil {
                cell = ExternalSourceTableViewCell(style: .default,
                                                   reuseIdentifier: "ExternalSourceTableViewCell",
                                                   sourceURL: sourceURL)
            }
            guard let cell = cell else { return UITableViewCell() }

            if indexPath.row < filteredInstallableSources.count {
                cell.source = filteredInstallableSources[indexPath.row]
                cell.getButton.title = "GET"
                cell.buttonWidth = 67
            }

            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        72
    }

    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        if (indexPath.section == 0 && hasSources && !hasUpdates) || (indexPath.section == 1 && hasSources && hasUpdates) {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
                let action = UIAction(title: "Uninstall", image: UIImage(systemName: "trash")) { _ in
                    SourceManager.shared.remove(source: self.sources[indexPath.row])
                    self.sources = SourceManager.shared.sources
                }
                return UIMenu(title: "", children: [action])
            }
        }
        return nil
    }
}

// MARK: - Table View Delegate
extension BrowseViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if (indexPath.section == 0 && hasSources && !hasUpdates) || (indexPath.section == 1 && hasSources && hasUpdates) {
            let vc = SourceViewController(source: sources[indexPath.row])
            navigationController?.pushViewController(vc, animated: true)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Search Results Updater
extension BrowseViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        tableView.reloadData()
    }
}
