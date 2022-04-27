//
//  BrowseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import SafariServices

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
            title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}

class BrowseViewController: UIViewController {

    let tableView = UITableView(frame: .zero, style: .grouped)

    var sourceLists: [URL] = SourceManager.shared.sourceLists

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
        sources.filter { searchText.isEmpty ? true : $0.manifest.info.name.lowercased().contains(searchText.lowercased()) }
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
        let showNsfw = UserDefaults.standard.bool(forKey: "Browse.showNsfwSources")
        return installableSources.filter {
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

    let emptyTextStackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("BROWSE", comment: "")

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

        emptyTextStackView.isHidden = true
        emptyTextStackView.axis = .vertical
        emptyTextStackView.distribution = .fill
        emptyTextStackView.spacing = 5
        emptyTextStackView.alignment = .center

        let emptyTitleLabel = UILabel()
        emptyTitleLabel.text = NSLocalizedString("BROWSE_NO_SOURCES", comment: "")
        emptyTitleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        emptyTitleLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTitleLabel)

        let emptyTextLabel = UILabel()
        let attributedString = NSMutableAttributedString(string: NSLocalizedString("BROWSE_NO_SOURCES_TEXT", comment: ""))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.8
        attributedString.addAttribute(NSAttributedString.Key.paragraphStyle, value: paragraphStyle, range: NSRange(0..<attributedString.length))
        emptyTextLabel.attributedText = attributedString
        emptyTextLabel.font = .systemFont(ofSize: 15)
        emptyTextLabel.textColor = .secondaryLabel
        emptyTextLabel.numberOfLines = 2
        emptyTextLabel.textAlignment = .center
        emptyTextStackView.addArrangedSubview(emptyTextLabel)
        emptyTextStackView.setCustomSpacing(3, after: emptyTextLabel)

        let emptyGuideButton = UIButton(type: .roundedRect)
        emptyGuideButton.setTitle(NSLocalizedString("ADDING_SOURCES_GUIDE_BUTTON", comment: ""), for: .normal)
        emptyGuideButton.addTarget(self, action: #selector(openGuidePage), for: .touchUpInside)
        emptyTextStackView.addArrangedSubview(emptyGuideButton)

        emptyTextStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyTextStackView)

        emptyTextStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        emptyTextStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        if externalSources.isEmpty {
            Task {
                await updateSourceLists()
            }
        }

        NotificationCenter.default.addObserver(forName: Notification.Name("Browse.showNsfwSources"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.reloadData()
            }
        }

        NotificationCenter.default.addObserver(forName: Notification.Name("updateSourceLists"), object: nil, queue: nil) { _ in
            Task {
                self.sourceLists = SourceManager.shared.sourceLists
                await self.updateSourceLists()
            }
        }

        NotificationCenter.default.addObserver(forName: Notification.Name("updateSourceList"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.sources = SourceManager.shared.sources
                self.fetchUpdates()
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
                          animations: { self.tableView.reloadData() },
                          completion: { _ in
            self.emptyTextStackView.isHidden = self.tableView.numberOfSections != 0
        })
    }

    func fetchUpdates() {
        var newUpdates: [ExternalSourceInfo] = []
        for source in externalSources {
            if let installedSource = SourceManager.shared.source(for: source.id) {
                if source.version > installedSource.manifest.info.version {
                    newUpdates.append(source)
                }
            }
        }
        updates = newUpdates
    }

    @MainActor
    func updateSourceLists() async {
        externalSources = []

        for url in sourceLists {
            var sources = (try? await URLSession.shared.object(
                from: url.appendingPathComponent("index.min.json")
            ) as [ExternalSourceInfo]?) ?? []
            for index in sources.indices {
                sources[index].sourceUrl = url
            }
            externalSources.append(contentsOf: sources)
        }

        externalSources.sort { $0.name < $1.name }
        fetchUpdates()
    }

    @objc func openGuidePage() {
        let safariViewController = SFSafariViewController(url: URL(string: "https://aidoku.app/help/guides/getting-started/#installing-a-source")!)
        present(safariViewController, animated: true)
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
            view.title.text = NSLocalizedString("UPDATES", comment: "")
        } else if (section == 0 && hasSources && !hasUpdates) || (section == 1 && hasSources && hasUpdates) {
            view.title.text = NSLocalizedString("INSTALLED", comment: "")
        } else if (section == 0 && !hasSources && !hasUpdates)
                    || (section == 1 && hasSources && !hasUpdates)
                    || (section == 1 && !hasSources && hasUpdates)
                    || (section == 2 && hasSources && hasUpdates) {
            view.title.text = NSLocalizedString("EXTERNAL", comment: "")
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
                cell = ExternalSourceTableViewCell(style: .default, reuseIdentifier: "ExternalSourceTableViewCell")
            }
            guard let cell = cell else { return UITableViewCell() }

            cell.source = filteredUpdates[indexPath.row]
            cell.getButton.title = NSLocalizedString("BUTTON_UPDATE", comment: "")

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
                cell = ExternalSourceTableViewCell(style: .default, reuseIdentifier: "ExternalSourceTableViewCell")
            }
            guard let cell = cell else { return UITableViewCell() }

            if indexPath.row < filteredInstallableSources.count {
                cell.source = filteredInstallableSources[indexPath.row]
                cell.getButton.title = NSLocalizedString("BUTTON_GET", comment: "")
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
                let action = UIAction(title: NSLocalizedString("UNINSTALL", comment: ""), image: UIImage(systemName: "trash")) { _ in
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
