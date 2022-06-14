//
//  SettingsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/22.
//

import UIKit
import SafariServices
import Kingfisher
import WebKit

class SettingsViewController: SettingsTableViewController {

    // swiftlint:disable:next function_body_length
    init() {
        super.init(items: [
            // MARK: About
            SettingItem(type: "group", title: NSLocalizedString("ABOUT", comment: ""), items: [
                SettingItem(type: "page", key: "About.about", title: NSLocalizedString("ABOUT", comment: "")),
                SettingItem(type: "link", key: "https://github.com/Aidoku/Aidoku", title: NSLocalizedString("GITHUB_REPO", comment: "")),
                SettingItem(type: "link", key: "https://discord.gg/9U8cC5Zk3s", title: NSLocalizedString("DISCORD_SERVER", comment: ""), external: true)
            ]),
            // MARK: General
            SettingItem(
                type: "group",
                title: NSLocalizedString("GENERAL", comment: ""),
                items: [
                    SettingItem(
                        type: "switch",
                        key: "General.incognitoMode",
                        title: NSLocalizedString("INCOGNITO_MODE", comment: "")
//                        subtitle: NSLocalizedString("INCOGNITO_MODE_TEXT", comment: "")
                    ),
                    SettingItem(type: "switch", key: "General.icloudSync", title: NSLocalizedString("ICLOUD_SYNC", comment: "")),
                    SettingItem(
                        type: "segment",
                        key: "General.appearance",
                        title: NSLocalizedString("APPEARANCE", comment: ""),
                        values: [
                            NSLocalizedString("APPEARANCE_LIGHT", comment: ""),
                            NSLocalizedString("APPEARANCE_DARK", comment: "")
                        ],
                        requiresFalse: "General.useSystemAppearance"
                    ),
                    SettingItem(
                        type: "switch",
                        key: "General.useSystemAppearance",
                        title: NSLocalizedString("USE_SYSTEM_APPEARANCE", comment: "")
                    )
                ]
            ),
            // MARK: Manga page
            SettingItem(
                type: "group",
                title: NSLocalizedString("MANGA_PAGE", comment: ""),
                footer: NSLocalizedString("USE_MANGA_TINT_INFO", comment: ""),
                items: [
                    SettingItem(
                        type: "switch",
                        key: "General.showSourceLabel",
                        title: NSLocalizedString("SHOW_SOURCE_LABEL", comment: "")
                    ),
                    SettingItem(
                        type: "switch",
                        key: "General.useMangaTint",
                        title: NSLocalizedString("USE_MANGA_TINT", comment: "")
                    )
                ]
            ),
            // MARK: Manga per row
            SettingItem(type: "group", title: NSLocalizedString("MANGA_PER_ROW", comment: ""), items: [
                SettingItem(
                    type: "stepper",
                    key: "General.portraitRows",
                    title: NSLocalizedString("PORTRAIT", comment: ""),
                    minimumValue: 1, maximumValue: 15
                ),
                SettingItem(
                    type: "stepper",
                    key: "General.landscapeRows",
                    title: NSLocalizedString("LANDSCAPE", comment: ""),
                    minimumValue: 1, maximumValue: 15
                )
            ]),
            // MARK: Library
            SettingItem(type: "group", title: NSLocalizedString("LIBRARY", comment: ""), items: [
                SettingItem(
                    type: "switch",
                    key: "Library.opensReaderView",
                    title: NSLocalizedString("OPEN_READER_VIEW", comment: "")
                ),
                SettingItem(
                    type: "switch",
                    key: "Library.unreadChapterBadges",
                    title: NSLocalizedString("UNREAD_CHAPTER_BADGES", comment: "")
                ),
                SettingItem(
                    type: "switch",
                    key: "Library.pinManga",
                    title: NSLocalizedString("PIN_MANGA", comment: "")
                ),
                SettingItem(
                    type: "segment",
                    key: "Library.pinMangaType",
                    title: NSLocalizedString("PIN_MANGA_TYPE", comment: ""),
                    values: [
                        NSLocalizedString("PIN_MANGA_UNREAD", comment: ""),
                        NSLocalizedString("PIN_MANGA_UPDATED", comment: "")
                    ],
                   requires: "Library.pinManga"
                ),
                SettingItem(
                    type: "switch",
                    key: "Library.lockLibrary",
                    title: NSLocalizedString("LOCK_LIBRARY", comment: ""),
                    notification: "updateLibraryLock",
                    authToEnable: true,
                    authToDisable: true
                )
            ]),
            // MARK: Categories
            SettingItem(type: "group", title: NSLocalizedString("CATEGORIES", comment: ""), items: [
                SettingItem(type: "page", key: "Library.categories", title: NSLocalizedString("CATEGORIES", comment: "")),
                SettingItem(
                    type: "multi-single-select",
                    key: "Library.defaultCategory",
                    title: NSLocalizedString("DEFAULT_CATEGORY", comment: ""),
                    values: ["", "none"] + DataManager.shared.getCategories(),
                    titles: [
                        NSLocalizedString("ALWAYS_ASK", comment: ""), NSLocalizedString("NONE", comment: "")
                    ] + DataManager.shared.getCategories()
                ),
                SettingItem(
                    type: "multi-select",
                    key: "Library.lockedCategories",
                    title: NSLocalizedString("LOCKED_CATEGORIES", comment: ""),
                    values: DataManager.shared.getCategories(),
                    notification: "updateLibraryLock",
                    requires: "Library.lockLibrary",
                    authToOpen: true
                )
            ]),
            // MARK: Library updating
            SettingItem(type: "group", title: NSLocalizedString("LIBRARY_UPDATING", comment: ""), items: [
                SettingItem(
                    type: "select",
                    key: "Library.updateInterval",
                    title: NSLocalizedString("UPDATE_INTERVAL", comment: ""),
                    values: ["never", "12hours", "daily", "2days", "weekly"],
                    titles: [
                        NSLocalizedString("NEVER", comment: ""),
                        NSLocalizedString("EVERY_12_HOURS", comment: ""),
                        NSLocalizedString("DAILY", comment: ""),
                        NSLocalizedString("EVERY_2_DAYS", comment: ""),
                        NSLocalizedString("WEEKLY", comment: "")
                    ]
                ),
                SettingItem(
                    type: "multi-select",
                    key: "Library.skipTitles",
                    title: NSLocalizedString("SKIP_TITLES", comment: ""),
                    values: ["hasUnread", "completed", "notStarted"],
                    titles: [
                        NSLocalizedString("WITH_UNREAD_CHAPTERS", comment: ""),
                        NSLocalizedString("WITH_COMPLETED_STATUS", comment: ""),
                        NSLocalizedString("THAT_HAVENT_BEEN_READ", comment: "")
                    ]
                ),
                SettingItem(
                    type: "multi-select",
                    key: "Library.excludedUpdateCategories",
                    title: NSLocalizedString("EXCLUDED_CATEGORIES", comment: ""),
                    values: DataManager.shared.getCategories()
                ),
                SettingItem(
                    type: "switch",
                    key: "Library.updateOnlyOnWifi",
                    title: NSLocalizedString("ONLY_UPDATE_ON_WIFI", comment: "")
                ),
                SettingItem(
                    type: "switch",
                    key: "Library.refreshMetadata",
                    title: NSLocalizedString("REFRESH_METADATA", comment: "")
                )
            ]),
            // MARK: Browse
            SettingItem(type: "group", title: NSLocalizedString("BROWSE", comment: ""), items: [
                SettingItem(type: "page", key: "Browse.sourceLists", title: NSLocalizedString("SOURCE_LISTS", comment: "")),
                SettingItem(
                    type: "switch",
                    key: "Browse.showNsfwSources",
                    title: NSLocalizedString("SHOW_NSFW_SOURCES", comment: "")
                )
            ]),
            // MARK: History
            SettingItem(type: "group", title: NSLocalizedString("HISTORY", comment: ""), items: [
                SettingItem(
                    type: "switch",
                    key: "History.lockHistoryTab",
                    title: NSLocalizedString("LOCK_HISTORY_TAB", comment: ""),
                    authToEnable: true,
                    authToDisable: true
                )
            ]),
            // MARK: Reader
            SettingItem(type: "group", title: NSLocalizedString("READER", comment: ""), items: [
                SettingItem(
                    type: "switch",
                    key: "Reader.downsampleImages",
                    title: NSLocalizedString("DOWNSAMPLE_IMAGES", comment: "")
                ),
                SettingItem(
                    type: "stepper",
                    key: "Reader.pagesToPreload",
                    title: NSLocalizedString("PAGES_TO_PRELOAD", comment: ""),
                    minimumValue: 1,
                    maximumValue: 10
                ),
                SettingItem(
                    type: "select",
                    key: "Reader.pagedPageLayout",
                    title: NSLocalizedString("PAGE_LAYOUT", comment: ""),
                    values: ["single", "double", "auto"],
                    titles: [
                        NSLocalizedString("SINGLE_PAGE", comment: ""),
                        NSLocalizedString("DOUBLE_PAGE", comment: ""),
                        NSLocalizedString("AUTOMATIC", comment: "")
                    ]
                )
            ]),
            // MARK: Backups
            SettingItem(type: "group", title: NSLocalizedString("BACKUPS", comment: ""), items: [
                SettingItem(type: "page", key: "Backups.backups", title: NSLocalizedString("BACKUPS", comment: ""))
            ]),
            // MARK: Logging
            SettingItem(type: "group", title: NSLocalizedString("LOGGING", comment: ""), items: [
                SettingItem(
                    type: "text",
                    key: "Logs.logServer",
                    placeholder: NSLocalizedString("LOG_SERVER", comment: ""),
                    autocapitalizationType: 0,
                    autocorrectionType: 1,
                    spellCheckingType: 1,
                    keyboardType: 3
                ),
                SettingItem(type: "button", key: "Logs.export", title: NSLocalizedString("EXPORT_LOGS", comment: "")),
                SettingItem(type: "button", key: "Logs.display", title: NSLocalizedString("DISPLAY_LOGS", comment: ""))
            ]),
            // MARK: Advanced
            SettingItem(type: "group", title: NSLocalizedString("ADVANCED", comment: ""), items: [
                SettingItem(type: "button", key: "Advanced.clearChapterCache", title: NSLocalizedString("CLEAR_CHAPTER_CACHE", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearMangaCache", title: NSLocalizedString("CLEAR_MANGA_CACHE", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearNetworkCache", title: NSLocalizedString("CLEAR_NETWORK_CACHE", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearReadHistory", title: NSLocalizedString("CLEAR_READ_HISTORY", comment: "")),
                SettingItem(type: "button", key: "Advanced.resetSettings", title: NSLocalizedString("RESET_SETTINGS", comment: "")),
                SettingItem(type: "button", key: "Advanced.reset", title: NSLocalizedString("RESET", comment: ""), destructive: true)
            ])
        ])

        let updateAppearanceBlock: (Notification) -> Void = { [weak self] _ in
            if !UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                    self?.view.window?.overrideUserInterfaceStyle = .light
                } else {
                    self?.view.window?.overrideUserInterfaceStyle = .dark
                }
            }
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("General.appearance"), object: nil, queue: nil, using: updateAppearanceBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("General.useSystemAppearance"), object: nil, queue: nil, using: updateAppearanceBlock
        ))
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name("Logs.logServer"), object: nil, queue: nil) { _ in
            LogManager.logger.streamUrl = URL(string: UserDefaults.standard.string(forKey: "Logs.logServer") ?? "")
        })

        // update default category select and settings that list categories setting when categories change
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("updateCategories"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            if let categoryPrefsIndex = self.items.firstIndex(where: { $0.title == NSLocalizedString("CATEGORIES", comment: "") }),
               let categoryIndex = self.items[categoryPrefsIndex].items?.firstIndex(where: { $0.key == "Library.defaultCategory" }),
               let lockedCategoriesIndex = self.items[categoryPrefsIndex].items?.firstIndex(where: { $0.key == "Library.lockedCategories" }),
               let updatePrefsIndex = self.items.firstIndex(where: { $0.title == NSLocalizedString("LIBRARY_UPDATING", comment: "") }),
               let excludedCategoriesIndex = self.items[updatePrefsIndex].items?.firstIndex(where: { $0.key == "Library.excludedUpdateCategories" }) {
                let categories = DataManager.shared.getCategories()
                self.items[categoryPrefsIndex].items?[categoryIndex].values = ["", "none"] + categories
                self.items[categoryPrefsIndex].items?[categoryIndex].titles = [
                    NSLocalizedString("ALWAYS_ASK", comment: ""), NSLocalizedString("NONE", comment: "")
                ] + categories
                self.items[categoryPrefsIndex].items?[lockedCategoriesIndex].values = categories
                self.items[updatePrefsIndex].items?[excludedCategoriesIndex].values = categories
                // if a deleted category was selected, reset to always ask
                if let selected = UserDefaults.standard.stringArray(forKey: "Library.defaultCategory")?.first,
                   !selected.isEmpty && selected != "none" && !categories.contains(selected) {
                    UserDefaults.standard.set([""], forKey: "Library.defaultCategory")
                }
            }
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // needed to update the selected value text for select settings
        tableView.reloadData()
    }

    func confirmAction(
        title: String,
        message: String,
        continueActionName: String = NSLocalizedString("CONTINUE", comment: ""),
        destructive: Bool = true,
        proceed: @escaping () -> Void
    ) {
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

    // swiftlint:disable:next cyclomatic_complexity
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let item = items[indexPath.section].items?[indexPath.row] {
            switch item.key {
            case "About.about":
                navigationController?.pushViewController(SettingsAboutViewController(), animated: true)

            case "Library.categories":
                navigationController?.pushViewController(CategoriesViewController(), animated: true)

            case "Browse.sourceLists":
                navigationController?.pushViewController(SourceListsViewController(), animated: true)

            case "Backups.backups":
                navigationController?.pushViewController(BackupsViewController(), animated: true)

            case "Logs.export":
                let url = LogManager.export()
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                vc.popoverPresentationController?.sourceView = tableView
                vc.popoverPresentationController?.sourceRect = tableView.cellForRow(at: indexPath)!.frame
                present(vc, animated: true)

            case "Logs.display":
                navigationController?.pushViewController(LogViewController(), animated: true)

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
                    self.clearNetworkCache()
                }
            case "Advanced.clearReadHistory":
                confirmAction(title: NSLocalizedString("CLEAR_READ_HISTORY", comment: ""),
                              message: NSLocalizedString("CLEAR_READ_HISTORY_TEXT", comment: "")) {
                    DataManager.shared.clearHistory()
                }
            case "Advanced.resetSettings":
                confirmAction(title: NSLocalizedString("RESET_SETTINGS", comment: ""),
                              message: NSLocalizedString("RESET_SETTINGS_TEXT", comment: "")) {
                    self.resetSettings()
                }
            case "Advanced.reset":
                confirmAction(title: NSLocalizedString("RESET", comment: ""),
                              message: NSLocalizedString("RESET_TEXT", comment: "")) {
                    self.clearNetworkCache()
                    DataManager.shared.clearLibrary()
                    DataManager.shared.clearHistory()
                    DataManager.shared.clearManga()
                    DataManager.shared.clearChapters()
                    DataManager.shared.clearCategories()
                    SourceManager.shared.clearSources()
                    SourceManager.shared.clearSourceLists()
                    self.resetSettings()
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

// MARK: - Data Clearing Methods
extension SettingsViewController {

    func clearNetworkCache() {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
          records.forEach { record in
              WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {})
          }
        }
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache()
        KingfisherManager.shared.cache.cleanExpiredDiskCache()
    }

    func resetSettings() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }
}
