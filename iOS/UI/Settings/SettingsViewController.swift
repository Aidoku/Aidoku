//
//  SettingsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/22.
//

import UIKit
import SafariServices
import Kingfisher

class SettingsViewController: SettingsTableViewController {

    init() {
        super.init(items: [
            SettingItem(type: "group", title: "About", items: [
                SettingItem(type: "page", key: "About.about", title: "About"),
                SettingItem(type: "link", key: "https://github.com/Aidoku/Aidoku", title: "GitHub Repository"),
                SettingItem(type: "link", key: "https://discord.gg/9U8cC5Zk3s", title: "Discord Server", external: true)
            ]),
            SettingItem(type: "group", title: "General", items: [
                SettingItem(type: "switch", key: "General.icloudSync", title: "iCloud Sync"),
                SettingItem(type: "segment", key: "General.appearance", title: "Appearance",
                            values: ["Light", "Dark"], requiresFalse: "General.useSystemAppearance"),
                SettingItem(type: "switch", key: "General.useSystemAppearance", title: "Use System Appearance")
            ]),
            SettingItem(type: "group", title: "Reader", items: [
                SettingItem(type: "switch", key: "Reader.downsampleImages", title: "Downsample Images")
            ]),
            SettingItem(type: "group", title: "Library", items: [
                SettingItem(type: "switch", key: "Library.opensReaderView", title: "Open Reader View"),
                SettingItem(type: "switch", key: "Library.unreadChapterBadges", title: "Unread Chapter Badges")
            ]),
            SettingItem(type: "group", title: "Browse", items: [
                SettingItem(type: "switch", key: "Browse.showNsfwSources", title: "Show NSFW Sources")
            ]),
            SettingItem(type: "group", title: "Backups", items: [
                SettingItem(type: "page", key: "Backups.backups", title: "Backups")
            ]),
            SettingItem(type: "group", title: "Advanced", items: [
                SettingItem(type: "button", key: "Advanced.clearChapterCache", title: "Clear Chapter Cache"),
                SettingItem(type: "button", key: "Advanced.clearMangaCache", title: "Clear Manga Cache"),
                SettingItem(type: "button", key: "Advanced.clearNetworkCache", title: "Clear Network Cache"),
                SettingItem(type: "button", key: "Advanced.clearReadHistory", title: "Clear Read History"),
                SettingItem(type: "button", key: "Advanced.reset", title: "Reset", destructive: true)
            ])
        ])

        NotificationCenter.default.addObserver(forName: NSNotification.Name("General.appearance"), object: nil, queue: nil) { _ in
            if !UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                    self.view.window?.overrideUserInterfaceStyle = .light
                } else {
                    self.view.window?.overrideUserInterfaceStyle = .dark
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("General.useSystemAppearance"), object: nil, queue: nil) { _ in
            if UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                self.view.window?.overrideUserInterfaceStyle = .unspecified
            } else {
                if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                    self.view.window?.overrideUserInterfaceStyle = .light
                } else {
                    self.view.window?.overrideUserInterfaceStyle = .dark
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
}

// MARK: - Table View Data Source
extension SettingsViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let item = items[indexPath.section].items?[indexPath.row] {
            switch item.key {
            case "About.about":
                navigationController?.pushViewController(SettingsAboutViewController(), animated: true)

            case "Backups.backups":
                navigationController?.pushViewController(BackupsViewController(), animated: true)

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
                super.tableView(tableView, didSelectRowAt: indexPath)
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
