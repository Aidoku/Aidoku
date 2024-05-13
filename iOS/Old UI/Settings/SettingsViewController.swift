//
//  SettingsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/22.
//

import UIKit
import SafariServices
import Nuke
import WebKit

class SettingsViewController: SettingsTableViewController {

    var loadingAlert: UIAlertController?
    var progressView: UIProgressView?

    // swiftlint:disable:next function_body_length
    init() {
        let categories = CoreDataManager.shared.getCategoryTitles()
        super.init(items: [
            // MARK: About
            SettingItem(type: "group", title: NSLocalizedString("ABOUT", comment: ""), items: [
                SettingItem(type: "page", key: "About.about", title: NSLocalizedString("ABOUT", comment: "")),
                SettingItem(type: "link", title: NSLocalizedString("GITHUB_REPO", comment: ""), url: "https://github.com/Aidoku/Aidoku"),
                SettingItem(type: "link", title: NSLocalizedString("DISCORD_SERVER", comment: ""), url: "https://discord.gg/9U8cC5Zk3s", external: true),
                SettingItem(type: "link", title: NSLocalizedString("SUPPORT_VIA_KOFI", comment: ""), url: "https://ko-fi.com/skittyblock", external: true)
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
                    SettingItem(
                        type: "switch",
                        key: "General.icloudSync",
                        title: NSLocalizedString("ICLOUD_SYNC", comment: ""),
                        requiresFalse: "isSideloaded"
                    ),
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
//                footer: NSLocalizedString("USE_MANGA_TINT_INFO", comment: ""),
                items: [
                    SettingItem(
                        type: "switch",
                        key: "General.showSourceLabel",
                        title: NSLocalizedString("SHOW_SOURCE_LABEL", comment: "")
//                    ),
//                    SettingItem(
//                        type: "switch",
//                        key: "General.useMangaTint",
//                        title: NSLocalizedString("USE_MANGA_TINT", comment: "")
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
                    values: ["", "none"] + categories,
                    titles: [
                        NSLocalizedString("ALWAYS_ASK", comment: ""), NSLocalizedString("NONE", comment: "")
                    ] + categories
                ),
                SettingItem(
                    type: "multi-select",
                    key: "Library.lockedCategories",
                    title: NSLocalizedString("LOCKED_CATEGORIES", comment: ""),
                    values: categories,
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
                    values: categories
                ),
                SettingItem(
                    type: "switch",
                    key: "Library.updateOnlyOnWifi",
                    title: NSLocalizedString("ONLY_UPDATE_ON_WIFI", comment: "")
                ),
                SettingItem(
                    type: "switch",
                    key: "Library.downloadOnlyOnWifi",
                    title: NSLocalizedString("ONLY_DOWNLOAD_ON_WIFI", comment: "")
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
                    type: "select",
                    key: "Reader.readingMode",
                    title: NSLocalizedString("DEFAULT_READING_MODE", comment: ""),
                    values: ["auto", "rtl", "ltr", "vertical", "webtoon"],
                    titles: [
                        NSLocalizedString("AUTOMATIC", comment: ""),
                        NSLocalizedString("RTL", comment: ""),
                        NSLocalizedString("LTR", comment: ""),
                        NSLocalizedString("VERTICAL", comment: ""),
                        NSLocalizedString("WEBTOON", comment: "")
                    ],
                    notification: "Reader.readingMode"
                ),
                SettingItem(
                    type: "switch",
                    key: "Reader.skipDuplicateChapters",
                    title: NSLocalizedString("SKIP_DUPLICATE_CHAPTERS", comment: "")
                ),
                SettingItem(type: "switch", key: "Reader.downsampleImages", title: NSLocalizedString("DOWNSAMPLE_IMAGES", comment: "")),
                SettingItem(type: "switch", key: "Reader.cropBorders", title: NSLocalizedString("CROP_BORDERS", comment: "")),
                SettingItem(type: "switch", key: "Reader.saveImageOption", title: NSLocalizedString("SAVE_IMAGE_OPTION", comment: "")),
                SettingItem(
                    type: "select",
                    key: "Reader.backgroundColor",
                    title: NSLocalizedString("READER_BG_COLOR", comment: ""),
                    values: ["system", "white", "black"],
                    titles: [
                        NSLocalizedString("READER_BG_COLOR_SYSTEM", comment: ""),
                        NSLocalizedString("READER_BG_COLOR_WHITE", comment: ""),
                        NSLocalizedString("READER_BG_COLOR_BLACK", comment: "")
                    ]
                )
            ]),
            ReaderPagedViewModel.settings,
            ReaderWebtoonViewModel.settings,
            // MARK: Backups
            SettingItem(type: "group", title: NSLocalizedString("BACKUPS", comment: ""), items: [
                SettingItem(type: "page", key: "Backups.backups", title: NSLocalizedString("BACKUPS", comment: ""))
            ]),
            // MARK: Trackers
            SettingItem(type: "group", title: NSLocalizedString("TRACKERS", comment: ""), items: [
                SettingItem(type: "page", key: "Trackers.trackers", title: NSLocalizedString("TRACKERS", comment: ""))
            ]),
            // MARK: Logging
            SettingItem(type: "group", title: NSLocalizedString("LOGGING", comment: ""), items: [
                SettingItem(
                    type: "text",
                    key: "Logs.logServer",
                    placeholder: NSLocalizedString("LOG_SERVER", comment: ""),
                    notification: "Logs.logServer",
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
//                SettingItem(type: "button", key: "Advanced.clearChapterCache", title: NSLocalizedString("CLEAR_CHAPTER_CACHE", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearTrackedManga", title: NSLocalizedString("CLEAR_TRACKED_MANGA", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearNetworkCache", title: NSLocalizedString("CLEAR_NETWORK_CACHE", comment: "")),
                SettingItem(type: "button", key: "Advanced.clearReadHistory", title: NSLocalizedString("CLEAR_READ_HISTORY", comment: "")),
                SettingItem(type: "button", key: "Advanced.migrateHistory", title: "Migrate Chapter History"),
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
            } else {
                self?.view.window?.overrideUserInterfaceStyle = .unspecified
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
                let categories = CoreDataManager.shared.getCategoryTitles()
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

    func showLoadingIndicator() {
        if loadingAlert == nil {
            loadingAlert = UIAlertController(title: nil, message: NSLocalizedString("LOADING_ELLIPSIS", comment: ""), preferredStyle: .alert)
            progressView = UIProgressView(frame: .zero)
            progressView!.progress = 0
            progressView!.tintColor = view.tintColor
            progressView!.translatesAutoresizingMaskIntoConstraints = false
            loadingAlert!.view.addSubview(self.progressView!)
            NSLayoutConstraint.activate([
                progressView!.centerXAnchor.constraint(equalTo: loadingAlert!.view.centerXAnchor),
                progressView!.bottomAnchor.constraint(equalTo: loadingAlert!.view.bottomAnchor, constant: -8),
                progressView!.widthAnchor.constraint(equalTo: loadingAlert!.view.widthAnchor, constant: -30)
            ])
        }
        present(loadingAlert!, animated: true)
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

            case "Trackers.trackers":
                navigationController?.pushViewController(TrackersViewController(), animated: true)

            case "Logs.export":
                let url = LogManager.export()
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                vc.popoverPresentationController?.sourceView = tableView
                vc.popoverPresentationController?.sourceRect = tableView.cellForRow(at: indexPath)!.frame
                present(vc, animated: true)

            case "Logs.display":
                navigationController?.pushViewController(LogViewController(), animated: true)

//            case "Advanced.clearChapterCache":
//                confirmAction(
//                    title: NSLocalizedString("CLEAR_CHAPTER_CACHE", comment: ""),
//                    message: NSLocalizedString("CLEAR_CHAPTER_CACHE_TEXT", comment: "")
//                ) {
//                    DataManager.shared.clearChapters()
//                    Task {
//                        await DataManager.shared.updateLibrary()
//                    }
//                }
            case "Advanced.clearTrackedManga":
                confirmAction(
                    title: NSLocalizedString("CLEAR_TRACKED_MANGA", comment: ""),
                    message: NSLocalizedString("CLEAR_TRACKED_MANGA_TEXT", comment: "")
                ) {
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearTracks(context: context)
                            try? context.save()
                        }
                    }
                }
            case "Advanced.clearNetworkCache":
                var totalCacheSize = URLCache.shared.currentDiskUsage
                if let nukeCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
                    totalCacheSize += nukeCache.totalSize
                }
                let message = NSLocalizedString("CLEAR_NETWORK_CACHE_TEXT", comment: "")
                    + "\n\n"
                    + String(
                        format: NSLocalizedString("CACHE_SIZE_%@", comment: ""),
                        ByteCountFormatter.string(fromByteCount: Int64(totalCacheSize), countStyle: .file)
                    )

                confirmAction(
                    title: NSLocalizedString("CLEAR_NETWORK_CACHE", comment: ""),
                    message: message
                ) {
                    self.clearNetworkCache()
                }
            case "Advanced.clearReadHistory":
                confirmAction(
                    title: NSLocalizedString("CLEAR_READ_HISTORY", comment: ""),
                    message: NSLocalizedString("CLEAR_READ_HISTORY_TEXT", comment: "")
                ) {
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearHistory(context: context)
                            try? context.save()
                        }
                    }
                }
            case "Advanced.migrateHistory":
                confirmAction(
                    title: "Migrate Chapter History",
                    // swiftlint:disable:next line_length
                    message: "This will migrate leftover reading history from old versions that are not currently linked with stored chapters in the local database. This should've happened automatically upon updating, but if it didn't complete, it can be re-executed this way."
                ) {
                    Task {
                        self.showLoadingIndicator()
                        await CoreDataManager.shared.migrateChapterHistory(progress: { progress in
                            Task { @MainActor in
                                self.progressView?.progress = progress
                            }
                        })
                        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
                        self.loadingAlert?.dismiss(animated: true)
                    }
                }
            case "Advanced.resetSettings":
                confirmAction(
                    title: NSLocalizedString("RESET_SETTINGS", comment: ""),
                    message: NSLocalizedString("RESET_SETTINGS_TEXT", comment: "")
                ) {
                    self.resetSettings()
                }
            case "Advanced.reset":
                confirmAction(
                    title: NSLocalizedString("RESET", comment: ""),
                    message: NSLocalizedString("RESET_TEXT", comment: "")
                ) {
                    (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
                    self.clearNetworkCache()
                    self.resetSettings()
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearLibrary(context: context)
                            CoreDataManager.shared.clearHistory(context: context)
                            CoreDataManager.shared.clearChapters(context: context)
                            CoreDataManager.shared.clearCategories(context: context)
                            CoreDataManager.shared.clearTracks(context: context)
                            CoreDataManager.shared.clearTracks(context: context)
                            try? context.save()
                        }
                        SourceManager.shared.clearSources()
                        SourceManager.shared.clearSourceLists()
                        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateTrackers"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
                        (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
                    }
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
        // clear disk cache
        if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
            dataCache.removeAll()
        }
        // clear memory cache
        if let imageCache = ImagePipeline.shared.configuration.imageCache as? Nuke.ImageCache {
            imageCache.removeAll()
        }
    }

    func resetSettings() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }
}
