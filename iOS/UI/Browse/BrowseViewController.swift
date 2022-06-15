//
//  BrowseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import SafariServices

class BrowseViewController: UIViewController {

    let tableView = UITableView(frame: .zero, style: .grouped)

    var hoveredIndexPath: IndexPath?
    var hovering = false

    var sourceLists: [URL] = SourceManager.shared.sourceLists

    var sources = SourceManager.shared.sources {
        didSet {
            reloadData()
        }
    }
    var updates: [ExternalSourceInfo] = [] {
        didSet {
            reloadData()
            checkUpdateCount()
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
            } else {
                if let appVersion = Float(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
                    if let maxVersion = $0.maxAppVersion {
                        guard Float(maxVersion) ?? 0 >= appVersion else { return false }
                    }
                    if let minVersion = $0.minAppVersion {
                        guard Float(minVersion) ?? 0 <= appVersion else { return false }
                    }
                }
                let languages = UserDefaults.standard.stringArray(forKey: "Browse.languages") ?? []
                if !languages.contains($0.lang) {
                    return false
                } else if !searchText.isEmpty {
                    return $0.name.lowercased().contains(searchText.lowercased())
                } else {
                    return true
                }
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

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("BROWSE", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        if #available(iOS 15.0, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "globe.americas.fill"),
                style: .plain,
                target: self,
                action: #selector(openLanguageSelectPage)
            )
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "globe"),
                style: .plain,
                target: self,
                action: #selector(openLanguageSelectPage)
            )
        }

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

        // no sources text
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

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("Browse.languages"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.reloadData()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("Browse.showNsfwSources"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.reloadData()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateSourceLists"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.sourceLists = SourceManager.shared.sourceLists
                await self.updateSourceLists()
                self.reloadData()
                self.checkUpdateCount()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateSourceList"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.sources = SourceManager.shared.sources
                self.fetchUpdates()
            }
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        becomeFirstResponder()

        navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
        navigationController?.tabBarController?.tabBar.tintColor = UITabBar.appearance().tintColor
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationItem.hidesSearchBarWhenScrolling = true
    }

    func reloadData() {
        UIView.transition(
            with: tableView,
            duration: 0.3,
            options: .transitionCrossDissolve,
            animations: { self.tableView.reloadData() },
            completion: { _ in
                self.emptyTextStackView.isHidden = self.tableView.numberOfSections != 0
            }
        )
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

    func checkUpdateCount() {
        // store update count and display badge
        let updateCount = filteredUpdates.count
        UserDefaults.standard.set(updateCount, forKey: "Browse.updateCount")
        tabBarController?.tabBar.items?[1].badgeValue = updateCount > 0 ? String(updateCount) : nil
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
        externalSources.sort {
            SourceManager.shared.languageCodes.firstIndex(of: $0.lang) ?? 0 < SourceManager.shared.languageCodes.firstIndex(of: $1.lang) ?? 0
        }
        fetchUpdates()
    }

    @objc func openGuidePage() {
        let safariViewController = SFSafariViewController(url: URL(string: "https://aidoku.app/help/guides/getting-started/#installing-a-source")!)
        present(safariViewController, animated: true)
    }

    @objc func openLanguageSelectPage() {
        present(UINavigationController(rootViewController: LanguageSelectViewController()), animated: true)
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

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
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

// MARK: - Key Handler
extension BrowseViewController {
    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                title: "Select Previous Item in List",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Select Next Item in List",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Confirm Selection",
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

    @objc func arrowKeyPressed(_ sender: UIKeyCommand) {
        if !hovering {
            hovering = true
            if hoveredIndexPath == nil { hoveredIndexPath = IndexPath(row: 0, section: 0) }
            tableView.cellForRow(at: hoveredIndexPath!)?.setHighlighted(true, animated: true)
            return
        }
        guard let hoveredIndexPath = hoveredIndexPath else { return }
        var position = hoveredIndexPath.row
        var section = hoveredIndexPath.section
        switch sender.input {
        case UIKeyCommand.inputUpArrow: position -= 1
        case UIKeyCommand.inputDownArrow: position += 1
        default: return
        }
        if position < 0 {
            guard section > 0 else { return }
            section -= 1
            position = tableView.numberOfRows(inSection: section) - 1
        } else if position >= tableView.numberOfRows(inSection: section) {
            guard section < tableView.numberOfSections - 1 else { return }
            section += 1
            position = 0
        }
        let newHoveredIndexPath = IndexPath(row: position, section: section)
        tableView.cellForRow(at: hoveredIndexPath)?.setHighlighted(false, animated: true)
        tableView.cellForRow(at: newHoveredIndexPath)?.setHighlighted(true, animated: true)
        tableView.scrollToRow(at: newHoveredIndexPath, at: .middle, animated: true)
        self.hoveredIndexPath = newHoveredIndexPath
    }

    @objc func enterKeyPressed() {
        guard !tableView.isEditing, hovering, let hoveredIndexPath = hoveredIndexPath else { return }
        tableView(tableView, didSelectRowAt: hoveredIndexPath)
    }

    @objc func escKeyPressed() {
        guard !tableView.isEditing, hovering, let hoveredIndexPath = hoveredIndexPath else { return }
        tableView.cellForRow(at: hoveredIndexPath)?.setHighlighted(false, animated: true)
        hovering = false
        self.hoveredIndexPath = nil
    }
}
