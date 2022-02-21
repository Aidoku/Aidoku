//
//  SettingsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/22.
//

import UIKit
import SafariServices
import Kingfisher

class SettingsViewController: UITableViewController {

    enum SettingsCellType {
        case pageLink
        case link
        case action
        case actionDestructive
        case toggle
        case select
    }

    struct SettingsCell {
        var type: SettingsCellType
        var title: String
        var subtitle: String?
        var target: String?
        var bool: Bool?
    }

    let sections = [
        "About",
        "General",
        "Library",
        "Browse",
        "Advanced"
    ]

    let cells: [[SettingsCell]] = [
        [
            SettingsCell(type: .pageLink, title: "About", target: "About.about"),
            SettingsCell(type: .link, title: "GitHub Repository", target: "https://github.com/Aidoku/Aidoku", bool: true),
            SettingsCell(type: .link, title: "Discord Server", target: "https://discord.gg/9U8cC5Zk3s")
        ],
        [
            SettingsCell(type: .toggle, title: "iCloud Sync", target: "General.icloudSync")
        ],
        [
            SettingsCell(type: .toggle, title: "Open Reader View", target: "Library.opensReaderView"),
            SettingsCell(type: .toggle, title: "Unread Chapter Badges", target: "Library.unreadChapterBadges")
        ],
        [
            SettingsCell(type: .toggle, title: "Show NSFW Sources", target: "Browse.showNsfwSources")
//            SettingsCell(type: .toggle, title: "Label NSFW Sources", target: "Browse.labelNsfwSources"),
        ],
        [
            SettingsCell(type: .action, title: "Clear Chapter Cache", target: "Advanced.clearChapterCache"),
            SettingsCell(type: .action, title: "Clear Manga Cache", target: "Advanced.clearMangaCache"),
            SettingsCell(type: .action, title: "Clear Network Cache", target: "Advanced.clearNetworkCache"),
            SettingsCell(type: .action, title: "Clear Read History", target: "Advanced.clearReadHistory"),
            SettingsCell(type: .actionDestructive, title: "Reset", target: "Advanced.reset")
        ]
    ]

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Settings"
        navigationController?.navigationBar.prefersLargeTitles = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
    }

    func confirmAction(title: String,
                       message: String,
                       continueActionName: String = "Continue",
                       destructive: Bool = true,
                       proceed: @escaping () -> Void) {
        let alertView = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)

        let action = UIAlertAction(title: continueActionName, style: destructive ? .destructive : .default) { _ in proceed() }
        alertView.addAction(action)

        alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alertView, animated: true)
    }

    @objc func close() {
        dismiss(animated: true)
    }
}

// MARK: - Table View Data Source
extension SettingsViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cells[section].count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)

        let config = cells[indexPath.section][indexPath.row]
        cell.textLabel?.text = config.title

        switch config.type {
        case .pageLink:
            cell.accessoryType = .disclosureIndicator
        case .link, .action:
            cell.textLabel?.textColor = cell.tintColor
        case .actionDestructive:
            cell.textLabel?.textColor = .systemRed
        case .toggle:
            let switchView = UISwitch()
            switchView.defaultsKey = config.target
            cell.accessoryView = switchView
            cell.selectionStyle = .none
        default:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let config = cells[indexPath.section][indexPath.row]
        if let target = config.target {
            switch target {
            case "About.about":
                navigationController?.pushViewController(SettingsAboutViewController(), animated: true)

            case "Advanced.clearChapterCache":
                confirmAction(title: "Clear Chapter Cache",
                              message: "This action is irreversible. Cached chapters will be cleared and redownloaded.") {
                    DataManager.shared.clearChapters()
                    Task {
                        await DataManager.shared.updateLibrary()
                    }
                }
            case "Advanced.clearMangaCache":
                confirmAction(title: "Clear Manga Cache",
                              message: "This action is irreversible. Cached Manga not in your library will be removed.") {
                    DataManager.shared.purgeManga()
                }
            case "Advanced.clearNetworkCache":
                confirmAction(title: "Clear Network Cache",
                              message: "This action is irreversible. Cached network requests and images will be cleared.") {
                    URLCache.shared.removeAllCachedResponses()
                    KingfisherManager.shared.cache.clearMemoryCache()
                    KingfisherManager.shared.cache.clearDiskCache()
                    KingfisherManager.shared.cache.cleanExpiredDiskCache()
                }
            case "Advanced.clearReadHistory":
                confirmAction(title: "Clear Read History", message: "This action is irreversible. All read history will be removed.") {
                    DataManager.shared.clearHistory()
                }
            case "Advanced.reset":
                confirmAction(title: "Reset",
                              message: "This action is irreversible. All data, settings, and caches will be cleared and reset.") {
                    KingfisherManager.shared.cache.clearMemoryCache()
                    KingfisherManager.shared.cache.clearDiskCache()
                    KingfisherManager.shared.cache.cleanExpiredDiskCache()
                    DataManager.shared.clearLibrary()
                    DataManager.shared.clearHistory()
                    DataManager.shared.clearManga()
                    DataManager.shared.clearChapters()
                    SourceManager.shared.clearSources()
                    UserDefaults.resetStandardUserDefaults()
                }

            default:
                if config.type == .link {
                    if let url = URL(string: target) {
                        if let inline = config.bool, inline {
                            let safariViewController = SFSafariViewController(url: URL(string: target)!)
                            present(safariViewController, animated: true)
                        } else {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
