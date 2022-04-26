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
            SettingItem(type: "group", title: NSLocalizedString("ABOUT", comment: ""), items: [
                SettingItem(type: "page", key: "About.about", title: NSLocalizedString("ABOUT", comment: "")),
                SettingItem(type: "link", key: "https://github.com/Aidoku/Aidoku", title: NSLocalizedString("GITHUB_REPO", comment: "")),
                SettingItem(type: "link", key: "https://discord.gg/9U8cC5Zk3s", title: NSLocalizedString("DISCORD_SERVER", comment: ""), external: true)
            ]),
            SettingItem(type: "group", title: NSLocalizedString("GENERAL", comment: ""), items: [
                SettingItem(type: "switch", key: "General.icloudSync", title: NSLocalizedString("ICLOUD_SYNC", comment: "")),
                SettingItem(type: "segment",
                            key: "General.appearance",
                            title: NSLocalizedString("APPEARANCE", comment: ""),
                            values: [
                                NSLocalizedString("APPEARANCE_LIGHT", comment: ""),
                                NSLocalizedString("APPEARANCE_DARK", comment: "")
                            ],
                            requiresFalse: "General.useSystemAppearance"),
                SettingItem(type: "switch",
                            key: "General.useSystemAppearance",
                            title: NSLocalizedString("USE_SYSTEM_APPEARANCE", comment: ""))
            ]),
            SettingItem(type: "group", title: NSLocalizedString("MANGA_PER_ROW", comment: ""), items: [
                SettingItem(type: "stepper",
                            key: "General.portraitRows",
                            title: NSLocalizedString("PORTRAIT", comment: ""), maximumValue: 15, minimumValue: 1),
                SettingItem(type: "stepper", key: "General.landscapeRows", title: NSLocalizedString("LANDSCAPE", comment: ""))
            ]),
            SettingItem(type: "group", title: NSLocalizedString("LIBRARY", comment: ""), items: [
                SettingItem(type: "switch",
                            key: "Library.opensReaderView",
                            title: NSLocalizedString("OPEN_READER_VIEW", comment: "")),
                SettingItem(type: "switch",
                            key: "Library.unreadChapterBadges",
                            title: NSLocalizedString("UNREAD_CHAPTER_BADGES", comment: "")),
                SettingItem(type: "switch",
                            key: "Library.pinManga",
                            title: NSLocalizedString("PIN_MANGA", comment: "")),
                SettingItem(type: "segment",
                            key: "Library.pinMangaType",
                            title: NSLocalizedString("PIN_MANGA_TYPE", comment: ""),
                            values: [
                                NSLocalizedString("PIN_MANGA_UNREAD", comment: ""),
                                NSLocalizedString("PIN_MANGA_UPDATED", comment: "")
                            ],
                           requires: "Library.pinManga")
            ]),
            SettingItem(type: "group", title: NSLocalizedString("BROWSE", comment: ""), items: [
                SettingItem(type: "page", key: "Browse.sourceLists", title: NSLocalizedString("SOURCE_LISTS", comment: "")),
                SettingItem(type: "switch",
                            key: "Browse.showNsfwSources",
                            title: NSLocalizedString("SHOW_NSFW_SOURCES", comment: ""))
            ]),
            SettingItem(type: "group", title: NSLocalizedString("READER", comment: ""), items: [
                SettingItem(type: "switch",
                            key: "Reader.downsampleImages",
                            title: NSLocalizedString("DOWNSAMPLE_IMAGES", comment: ""))
            ]),
            SettingItem(type: "group", title: NSLocalizedString("BACKUPS", comment: ""), items: [
                SettingItem(type: "page", key: "Backups.backups", title: NSLocalizedString("BACKUPS", comment: ""))
            ]),
            SettingItem(type: "group", title: NSLocalizedString("ADVANCED", comment: ""), items: [
                SettingItem(type: "button", key: "Advanced.clearChapterCache", title: NSLocalizedString("CLEAR_CHAPTER_CACHE", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearMangaCache", title: NSLocalizedString("CLEAR_MANGA_CACHE", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearNetworkCache", title: NSLocalizedString("CLEAR_NETWORK_CACHE", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearReadHistory", title: NSLocalizedString("CLEAR_READ_HISTORY", comment: "")),
                SettingItem(type: "button", key: "Advanced.reset", title: NSLocalizedString("RESET", comment: ""), destructive: true)
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
                       continueActionName: String = NSLocalizedString("CONTINUE", comment: ""),
                       destructive: Bool = true,
                       proceed: @escaping () -> Void) {
        let alertView = UIAlertController(
            title: title,
            message: message,
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        )

        let action = UIAlertAction(title: continueActionName, style: destructive ? .destructive : .default) { _ in proceed() }
        alertView.addAction(action)

        alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel))
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

            case "Browse.sourceLists":
                navigationController?.pushViewController(SourceListsViewController(), animated: true)

            case "Backups.backups":
                navigationController?.pushViewController(BackupsViewController(), animated: true)

            case "Advanced.clearChapterCache":
                confirmAction(title: NSLocalizedString("CLEAR_CHAPTER_CACHE", comment: ""),
                              message: NSLocalizedString("CLEAR_CHAPTER_CACHE_TEXT", comment: "")) {
                    DataManager.shared.clearChapters()
                    Task {
                        await DataManager.shared.updateLibrary()
                    }
                }
            case "Advanced.clearMangaCache":
                confirmAction(title: NSLocalizedString("CLEAR_MANGA_CACHE", comment: ""),
                              message: NSLocalizedString("CLEAR_MANGA_CACHE_TEXT", comment: "")) {
                    DataManager.shared.purgeManga()
                }
            case "Advanced.clearNetworkCache":
                confirmAction(title: NSLocalizedString("CLEAR_NETWORK_CACHE", comment: ""),
                              message: NSLocalizedString("CLEAR_NETWORK_CACHE_TEXT", comment: "")) {
                    URLCache.shared.removeAllCachedResponses()
                    KingfisherManager.shared.cache.clearMemoryCache()
                    KingfisherManager.shared.cache.clearDiskCache()
                    KingfisherManager.shared.cache.cleanExpiredDiskCache()
                }
            case "Advanced.clearReadHistory":
                confirmAction(title: NSLocalizedString("CLEAR_READ_HISTORY", comment: ""),
                              message: NSLocalizedString("CLEAR_READ_HISTORY_TEXT", comment: "")) {
                    DataManager.shared.clearHistory()
                }
            case "Advanced.reset":
                confirmAction(title: NSLocalizedString("RESET", comment: ""),
                              message: NSLocalizedString("RESET_TEXT", comment: "")) {
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

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        44
    }
}
