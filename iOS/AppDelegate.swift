//
//  AppDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import AidokuRunner
import CloudKit
import Nuke
import SwiftUI

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
#if CANONICAL_BUILD          // true only for App-Store scheme
    static let canonicalID = "app.aidoku.Aidoku"
#else
    static let canonicalID = Bundle.main.bundleIdentifier ?? ""
#endif

    static let isSideloaded = Bundle.main.bundleIdentifier != canonicalID

    private var networkObserverId: UUID?

    private lazy var loadingAlert: UIAlertController = {
        let loadingAlert = UIAlertController(
            title: nil,
            message: NSLocalizedString("LOADING_ELLIPSIS"),
            preferredStyle: .alert
        )
        progressView.tintColor = loadingAlert.view.tintColor
        loadingAlert.view.addSubview(progressView)
        loadingAlert.view.addSubview(loadingIndicator)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        let progressViewSidePadding: CGFloat
        let progressViewBottomPadding: CGFloat
        let indicatorViewSidePadding: CGFloat
        if #available(iOS 26.0, *) {
            progressViewSidePadding = 32
            progressViewBottomPadding = 16
            indicatorViewSidePadding = 16
        } else {
            progressViewSidePadding = 16
            progressViewBottomPadding = 8
            indicatorViewSidePadding = 10
        }

        NSLayoutConstraint.activate([
            progressView.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
            progressView.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -progressViewBottomPadding),
            progressView.widthAnchor.constraint(equalTo: loadingAlert.view.widthAnchor, constant: -(progressViewSidePadding * 2)),

            loadingIndicator.centerYAnchor.constraint(equalTo: loadingAlert.view.centerYAnchor),
            loadingIndicator.leadingAnchor.constraint(equalTo: loadingAlert.view.leadingAnchor, constant: indicatorViewSidePadding),
            loadingIndicator.widthAnchor.constraint(equalToConstant: 50),
            loadingIndicator.heightAnchor.constraint(equalToConstant: 50)
        ])
        return loadingAlert
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let loadingIndicator = UIActivityIndicatorView(frame: .zero)
        loadingIndicator.style = .medium
        loadingIndicator.tag = 3
        return loadingIndicator
    }()

    private lazy var progressView: UIProgressView = {
        let progressView = UIProgressView(frame: .zero)
        progressView.progress = 0
        return progressView
    }()

    var indicatorProgress: Float {
        get { progressView.progress }
        set { progressView.progress = newValue }
    }

    var navigationController: UINavigationController? {
        (UIApplication.shared.firstKeyWindow?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController
    }

    var visibleViewController: UIViewController? {
        ((UIApplication.shared.firstKeyWindow?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController)?
            .visibleViewController
    }

    var topViewController: UIViewController? {
        if var topController = UIApplication.shared.firstKeyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            return topController
        } else {
            return nil
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UserDefaults.standard.register(
            defaults: [
                "Flag.isSideloaded": Self.isSideloaded, // for icloud sync setting
                "Flag.showedLegacySourceListNotice": false,

                "General.incognitoMode": false,
                "General.icloudSync": false,
                "General.appearance": 0,
                "General.useSystemAppearance": true,
                "General.portraitRows": UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2,
                "General.landscapeRows": UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4,

                "Library.sortOption": 2, // lastOpened
                "Library.sortAscending": false,
                "Library.listView": false,

                "Library.lastUpdated": Date.distantPast.timeIntervalSince1970,

                "Library.opensReaderView": false,
                "Library.resumeLastOpenedChapter": false,
                "Library.unreadChapterBadges": true,
                "Library.downloadedChapterBadges": true,
                "Library.pinTitles": LibraryViewModel.PinType.none.rawValue,
                "Library.lockLibrary": false,

                "Library.lockedCategories": [String](),
                "Library.showUncategorizedCategory": false,

                "Library.updateInterval": "daily",
                "Library.skipTitles": ["hasUnread", "completed", "notStarted"],
                "Library.excludedUpdateCategories": [String](),
                "Library.backgroundRefresh": true,
                "Library.updateOnlyOnWifi": true,
                "Library.refreshMetadata": false,

                "Browse.languages": ["multi"] + Locale.preferredLanguages.map { Locale(identifier: $0).languageCode },
                "Browse.contentRatings": ["safe", "containsNsfw"],
                "Browse.updateCount": 0,

                "History.lockHistoryTab": false,

                "Reader.readingMode": "auto",
                "Reader.skipDuplicateChapters": true,
                "Reader.markDuplicateChapters": true,
                "Reader.downsampleImages": false,
                "Reader.upscaleImages": false,
                "Reader.upscaleMaxHeight": 2000,
                "Reader.cropBorders": false,
                "Reader.disableQuickActions": false,
                "Reader.liveText": false,
                "Reader.hideBarsOnSwipe": false,
                "Reader.tapZones": "disabled",
                "Reader.invertTapZones": false,
                "Reader.animatePageTransitions": true,
                "Reader.backgroundColor": "black",
                "Reader.pagesToPreload": 2,
                "Reader.pagedPageLayout": "auto",
                "Reader.pagedIsolateFirstPage": false,
                "Reader.splitWideImages": false,
                "Reader.reverseSplitOrder": false,
                "Reader.verticalInfiniteScroll": true,
                "Reader.pillarbox": false,
                "Reader.pillarboxAmount": 15,
                "Reader.pillarboxOrientation": "both",
                "Reader.orientation": "device",

                // Text Reader defaults
                "Reader.textReaderStyle": "scroll",
                "Reader.textFontFamily": "System",
                "Reader.textFontSize": 18,
                "Reader.textLineSpacing": 8,
                "Reader.textHorizontalPadding": 24,

                "Tracking.updateAfterReading": true,
                "Tracking.autoSyncFromTracker": false,

                "AutomaticBackups.enabled": true,
                "AutomaticBackups.interval": "daily",
                "AutomaticBackups.lastBackup": Date.distantPast.timeIntervalSince1970,
                "AutomaticBackups.libraryEntries": true,
                "AutomaticBackups.chapters": true,
                "AutomaticBackups.tracking": true,
                "AutomaticBackups.history": true,
                "AutomaticBackups.categories": true,
                "AutomaticBackups.readingSessions": true,
                "AutomaticBackups.updates": false,
                "AutomaticBackups.settings": true,
                "AutomaticBackups.sourceLists": true,
                "AutomaticBackups.sensitiveSettings": false,

                "Library.downloadOnlyOnWifi": false,
                "Library.deleteDownloadAfterReading": false,
                "Downloads.compress": true,
                "Downloads.parallel": true,
                "Downloads.background": true
            ]
        )

        // check for icloud availability
        // https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)
        // Do not call this method from your app’s main thread. Because this method might take a nontrivial amount of
        // time to set up iCloud and return the requested URL, you should always call it from a secondary thread.
        Task.detached {
            let isiCloudAvailable = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
            await MainActor.run {
                if !isiCloudAvailable {
                    LogManager.logger.info("iCloud unavailable")
                }
                UserDefaults.standard.register(defaults: ["Flag.isiCloudAvailable": isiCloudAvailable])
            }
        }

        DataLoader.sharedUrlCache.diskCapacity = 0

        let pipeline = ImagePipeline(delegate: self) {
            let dataLoader: DataLoader = {
                let config = URLSessionConfiguration.default
                config.urlCache = nil
                return DataLoader(configuration: config)
            }()
            let dataCache = try? DataCache(name: "app.aidoku.Aidoku.datacache") // disk cache
            let imageCache = Nuke.ImageCache() // memory cache
            dataCache?.sizeLimit = 500 * 1024 * 1024
            imageCache.costLimit = 100 * 1024 * 1024
            $0.dataCache = dataCache
            $0.imageCache = imageCache
            $0.dataLoader = dataLoader
            $0.dataCachePolicy = .storeOriginalData
            $0.isStoringPreviewsInMemoryCache = false
        }

        ImagePipeline.shared = pipeline

        performMigration()
        handleChaptersToBeDeleted()

        networkObserverId = Reachability.registerConnectionTypeObserver { connectionType in
            switch connectionType {
                case .wifi:
                    if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
                        Task {
                            await DownloadManager.shared.resumeDownloads()
                        }
                    }
                case .cellular, .none:
                    if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
                        Task {
                            await DownloadManager.shared.pauseDownloads()
                        }
                    }
            }
        }

        application.applicationSupportsShakeToEdit = true

        BackupManager.shared.register()
        MangaManager.shared.register()

        Task {
            await BackupManager.shared.scheduleAutoBackup()
            await MangaManager.shared.scheduleLibraryRefresh()
        }

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        guard let networkObserverId else { return }
        Reachability.unregisterConnectionTypeObserver(networkObserverId)
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        InterfaceOrientationCoordinator.shared.supportedOrientations
    }
}

extension AppDelegate {
    func performMigration() {
        var settingsVersion = UserDefaults.standard.string(forKey: "Flag.currentVersion")
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        if let oldSettingsVersion = UserDefaults.standard.string(forKey: "currentVersion") {
            settingsVersion = settingsVersion ?? oldSettingsVersion
            UserDefaults.standard.removeObject(forKey: "currentVersion")
        }

        guard currentVersion != settingsVersion else {
            return
        }

        LogManager.logger.info("Migrating settings from version \(settingsVersion ?? "none") to \(currentVersion ?? "unknown")")

        // migrate history to 0.6 format
        if settingsVersion == "0.5" {
            Task.detached {
                await self.migrateHistory()
            }
        }

        // migrate showNsfwSources setting
        if UserDefaults.standard.bool(forKey: "Browse.showNsfwSources") {
            UserDefaults.standard.setValue(["safe", "containsNsfw", "primarilyNsfw"], forKey: "Browse.contentRatings")
            UserDefaults.standard.removeObject(forKey: "Browse.showNsfwSources")
        }

        // migrate pin settings
        if UserDefaults.standard.bool(forKey: "Library.pinManga") {
            let newValue = switch UserDefaults.standard.integer(forKey: "Library.pinMangaType") {
                case 0: LibraryViewModel.PinType.unread.rawValue
                case 1: LibraryViewModel.PinType.updatedChapters.rawValue
                default: LibraryViewModel.PinType.none.rawValue
            }
            UserDefaults.standard.set(newValue, forKey: "Library.pinTitles")
            UserDefaults.standard.removeObject(forKey: "Library.pinManga")
            UserDefaults.standard.removeObject(forKey: "Library.pinMangaType")
        }

        // migration for 0.8.2
        if SourceManager.oldDirectory.exists {
            Task.detached {
                await self.migrateSources()
            }
        }

        // migrate unprefixed settings
        if UserDefaults.standard.bool(forKey: "downloadChapterSortAscending") {
            UserDefaults.standard.set(true, forKey: "Flag.downloadChapterSortAscending")
            UserDefaults.standard.removeObject(forKey: "downloadChapterSortAscending")
        }
        if let enabledModelFile = UserDefaults.standard.string(forKey: "enabledModelFile") {
            UserDefaults.standard.set(enabledModelFile, forKey: "Data.enabledModelFile")
            UserDefaults.standard.removeObject(forKey: "enabledModelFile")
        }
        if let downloadQueueState = UserDefaults.standard.data(forKey: "downloadQueueState") {
            UserDefaults.standard.set(downloadQueueState, forKey: "Data.downloadQueueState")
            UserDefaults.standard.removeObject(forKey: "downloadQueueState")
        }
        if let chaptersToBeDeleted = UserDefaults.standard.data(forKey: "chaptersToBeDeleted") {
            UserDefaults.standard.set(chaptersToBeDeleted, forKey: "Data.chaptersToBeDeleted")
            UserDefaults.standard.removeObject(forKey: "chaptersToBeDeleted")
        }

        UserDefaults.standard.set(currentVersion, forKey: "Flag.currentVersion")
    }

    private func migrateHistory() async {
        showLoadingIndicator(style: .progress)
        try? await Task.sleep(nanoseconds: 500 * 1_000_000)
        await CoreDataManager.shared.migrateChapterHistory(progress: { @Sendable progress in
            Task { @MainActor in
                self.indicatorProgress = progress
            }
        })
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
        await hideLoadingIndicator()
    }

    // migration for 0.8.2
    private func migrateSources() async {
        showLoadingIndicator(style: .indefinite)

        try? await Task.sleep(nanoseconds: 500 * 1_000_000)

        // migrate tracker token settings
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("Token.") {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.set(value, forKey: key.replacingOccurrences(of: "Token.", with: "Tracker."))
        }

        // handle lastUpdatedChapters addition
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let items = CoreDataManager.shared.getLibraryManga(context: context)
            // if lastUpdatedChapters is set to the default value, update default to lastUpdated
            for item in items where item.lastUpdatedChapters.timeIntervalSince1970 == 21600 {
                item.lastUpdatedChapters = item.lastUpdated
            }
        }

        // move all sources in old sources directory to the new one
        FileManager.default.moveFiles(in: SourceManager.oldDirectory, to: SourceManager.directory)
        SourceManager.oldDirectory.removeItem()
        await SourceManager.shared.reloadSources()

        await hideLoadingIndicator()
    }

    // delete chapters queued for deletion in last launch
    func handleChaptersToBeDeleted() {
        guard
            let data = UserDefaults.standard.data(forKey: "Data.chaptersToBeDeleted"),
            let chapterKeys = try? JSONDecoder().decode([ChapterIdentifier].self, from: data)
        else {
            return
        }
        Task {
            await DownloadManager.shared.delete(chapters: chapterKeys.map {
                .init(sourceKey: $0.sourceKey, mangaKey: $0.mangaKey, chapterKey: $0.chapterKey)
            })
            UserDefaults.standard.removeObject(forKey: "Data.chaptersToBeDeleted")
        }
    }

    enum LoadingStyle {
        case indefinite
        case progress
    }

    /// Shows a non-interactive loading indicator.
    func showLoadingIndicator(style: LoadingStyle = .indefinite, completion: (() -> Void)? = nil) {
        switch style {
            case .indefinite:
                loadingIndicator.startAnimating()
                loadingIndicator.isHidden = false
                progressView.isHidden = true
            case .progress:
                progressView.progress = 0
                loadingIndicator.isHidden = true
                progressView.isHidden = false
        }
        topViewController?.present(loadingAlert, animated: true, completion: completion)
    }

    /// Dismisses a shown loading indicator.
    func hideLoadingIndicator(completion: (() -> Void)? = nil) async {
        await withCheckedContinuation { continuation in
            loadingAlert.dismiss(animated: true) {
                self.loadingIndicator.stopAnimating()
                continuation.resume()
            }
        }
    }

    func handleUrl(url: URL) {
        if url.scheme == "aidoku" { // aidoku://
            if url.host == "addSourceList" { // addSourceList?url=
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let listUrlString = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                   let listUrl = URL(string: listUrlString) {
                    guard !SourceManager.shared.sourceListURLs.contains(listUrl) else { return }
                    Task {
                        let success = await SourceManager.shared.addSourceList(url: listUrl)
                        if success {
                            presentAlert(
                                title: NSLocalizedString("SOURCE_LIST_ADDED", comment: ""),
                                message: NSLocalizedString("SOURCE_LIST_ADDED_TEXT", comment: "")
                            )
                        } else {
                            presentAlert(
                                title: NSLocalizedString("SOURCE_LIST_ADD_FAIL", comment: ""),
                                message: NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT", comment: "")
                            )
                        }
                    }
                }
            } else if let host = url.host, let source = SourceManager.shared.source(for: host) {
                // todo: we should support opening items in library even if the source isn't installed
                Task { @MainActor in
                    // support percent encoding characters like "/" for manga and chapter keys
                    let pathComponents = url.percentEncodedPath
                        .split(separator: "/")
                        .map { String($0).removingPercentEncoding ?? String($0) }

                    if !pathComponents.isEmpty { // /sourceId/mangaId
                        let mangaKey = pathComponents[0].removingPercentEncoding ?? url.pathComponents[1]
                        guard
                            let navigationController,
                            let manga = try? await source.getMangaUpdate(
                                manga: AidokuRunner.Manga(sourceKey: source.id, key: mangaKey, title: ""),
                                needsDetails: true,
                                needsChapters: false
                            )
                        else {
                            return
                        }
                        let chapterKey = pathComponents[safe: 1]?.removingPercentEncoding ?? pathComponents[safe: 1]
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let action = components?.queryItems?.first(where: { $0.name == "action" })?.value.flatMap(MangaView.OpenAction.init)

                        navigationController.pushViewController(
                            MangaViewController(
                                source: source,
                                manga: manga,
                                parent: navigationController.topViewController,
                                chapterKey: chapterKey, // /sourceId/mangaId/chapterId
                                openAction: action // ?action={read,readNext,readLatest}
                            ),
                            animated: true
                        )
                    } else { // /sourceId
                        let vc: UIViewController = if let legacySource = source.legacySource {
                            SourceViewController(source: legacySource)
                        } else {
                            NewSourceViewController(source: source)
                        }
                        navigationController?.pushViewController(vc, animated: true)
                    }
                }
            } else {
                // check for tracker auth callback
                // this shouldn't really be called since authentication should be performed within the app
                if let tracker = TrackerManager.trackers.first(where: {
                    ($0 as? OAuthTracker)?.callbackHost == url.host
                }) as? OAuthTracker {
                    Task {
                        await tracker.handleAuthenticationCallback(url: url)
                    }
                } else {
                    Task {
                        await handleDeepLink(url: url)
                    }
                }
            }
        } else if url.pathExtension == "aix" {
            Task {
                let result = await SourceManager.shared.importSource(from: url)
                if result == nil {
                    presentAlert(
                        title: NSLocalizedString("IMPORT_FAIL", comment: ""),
                        message: NSLocalizedString("SOURCE_IMPORT_FAIL_TEXT", comment: "")
                    )
                }
            }
        } else if url.pathExtension == "json" || url.pathExtension == "aib" {
            Task {
                if await BackupManager.shared.importBackup(from: url) {
                    presentAlert(
                        title: NSLocalizedString("BACKUP_IMPORT_SUCCESS", comment: ""),
                        message: NSLocalizedString("BACKUP_IMPORT_SUCCESS_TEXT", comment: "")
                    )
                } else {
                    presentAlert(
                        title: NSLocalizedString("IMPORT_FAIL", comment: ""),
                        message: NSLocalizedString("BACKUP_IMPORT_FAIL_TEXT", comment: "")
                    )
                }
            }
        } else if
            SourceManager.shared.localSourceInstalled
                && (url.pathExtension == "cbz" || url.pathExtension == "zip")
        {
            Task {
                let fileInfo = await LocalFileManager.shared.loadImportFileInfo(url: url)
                if let fileInfo {
                    navigationController?.present(
                        UIHostingController(rootView: LocalFileImportView(fileInfo: fileInfo)),
                        animated: true
                    )
                } else {
                    presentAlert(
                        title: NSLocalizedString("IMPORT_FAIL", comment: ""),
                        message: NSLocalizedString("FILE_IMPORT_FAIL_TEXT", comment: "")
                    )
                }
            }
        } else {
            Task {
                await handleDeepLink(url: url)
            }
        }
    }

    func handleDeepLink(url: URL) async -> Bool {
        guard
            let navigationController,
            let targetUrl = (url as NSURL).resourceSpecifier
        else { return false }

        // ensure sources are loaded
        await SourceManager.shared.waitForSourcesLoad()

        // find source that uses the given url
        var targetSource: AidokuRunner.Source?
        var finalUrl: String?
        for source in SourceManager.shared.sources {
            for sourceUrl in source.urls {
                if let url = (sourceUrl as NSURL).resourceSpecifier, targetUrl.hasPrefix(url) {
                    targetSource = source
                    finalUrl = "\(URL(string: url)?.scheme ?? "https"):\(targetUrl)"
                    break
                }
            }
            if targetSource != nil { break }
        }

        guard let targetSource, let finalUrl else { return false }

        let task = Task { @MainActor in
            do {
                let link = try await targetSource.handleDeepLink(url: finalUrl)

                if let mangaId = link?.mangaKey {
                    // open manga view and scroll to chapter if given
                    guard let manga = try? await targetSource.getMangaUpdate(
                        manga: AidokuRunner.Manga(
                            sourceKey: targetSource.id,
                            key: mangaId,
                            title: ""
                        ),
                        needsDetails: true,
                        needsChapters: false
                    ) else {
                        return false
                    }

                    navigationController.pushViewController(
                        MangaViewController(
                            source: targetSource,
                            manga: manga,
                            parent: navigationController.topViewController,
                            chapterKey: link?.chapterKey,
                            openAction: .read
                        ),
                        animated: true
                    )

                    return true
                } else if let listing = link?.listing {
                    // open source listing
                    let viewController = SourceListingViewController(source: targetSource, listing: listing)
                    navigationController.pushViewController(viewController, animated: true)

                    return true
                }
            } catch {
                LogManager.logger.error("Failed to handle source deep link: \(error.localizedDescription)")
            }

            return false
        }

        return await task.value
    }

    func handleSourceMigration(source: AidokuRunner.Source) {
        presentAlert(
            title: NSLocalizedString("SOURCE_BREAKING_CHANGE"),
            message: NSLocalizedString("SOURCE_BREAKING_CHANGE_TEXT"),
            actions: [
                .init(title: NSLocalizedString("MIGRATE"), style: .default) { _ in
                    if source.features.handlesMigration {
                        // if the source handles the migration, we can migrate all the db ids
                        self.showLoadingIndicator()
                        Task {
                            let (
                                libraryMangaIds,
                                libraryChaptersIds,
                                historyMangaIds,
                                historyChapterIds,
                            ) = await CoreDataManager.shared.container.performBackgroundTask { context in
                                let historyObjects = CoreDataManager.shared.getHistory(sourceId: source.id, context: context)
                                return (
                                    CoreDataManager.shared.getLibraryManga(sourceId: source.id, context: context)
                                        .compactMap { $0.manga?.id },
                                    CoreDataManager.shared.getChapters(sourceId: source.id, context: context)
                                        .map { ($0.mangaId, $0.id) },
                                    historyObjects.map { $0.mangaId },
                                    historyObjects.map { ($0.mangaId, $0.chapterId) },
                                )
                            }
                            var newMangaIds: [String: String] = [:]
                            var newChapterIds: [String: String] = [:]
                            if source.features.handlesNotifications {
                                try? await source.handleNotification(notification: "system.startMigration")
                            }
                            for oldId in libraryMangaIds {
                                newMangaIds[oldId] = try? await source.handleMigration(kind: .manga, mangaKey: oldId, chapterKey: nil)
                            }
                            for oldId in historyMangaIds where newMangaIds[oldId] == nil  {
                                newMangaIds[oldId] = try? await source.handleMigration(kind: .manga, mangaKey: oldId, chapterKey: nil)
                            }
                            for (mangaId, oldId) in libraryChaptersIds {
                                newChapterIds[oldId] = try? await source.handleMigration(kind: .chapter, mangaKey: mangaId, chapterKey: oldId)
                            }
                            if source.features.handlesNotifications {
                                try? await source.handleNotification(notification: "system.endMigration")
                            }
                            for (mangaId, oldId) in historyChapterIds where newChapterIds[oldId] == nil  {
                                newChapterIds[oldId] = try? await source.handleMigration(kind: .chapter, mangaKey: mangaId, chapterKey: oldId)
                            }
                            await CoreDataManager.shared.container.performBackgroundTask { [newMangaIds, newChapterIds] context in
                                let libraryObjects = CoreDataManager.shared.getLibraryManga(sourceId: source.id, context: context)
                                let chapterObjects = CoreDataManager.shared.getChapters(sourceId: source.id, context: context)
                                let historyObjects = CoreDataManager.shared.getHistory(sourceId: source.id, context: context)
                                for object in libraryObjects {
                                    guard
                                        let oldId = object.manga?.id,
                                        let newId = newMangaIds[oldId]
                                    else { continue }
                                    object.manga?.id = newId
                                }
                                for object in chapterObjects {
                                    object.mangaId = newMangaIds[object.mangaId] ?? object.mangaId
                                    object.id = newChapterIds[object.id] ?? object.id
                                }
                                for object in historyObjects {
                                    object.mangaId = newMangaIds[object.mangaId] ?? object.mangaId
                                    object.chapterId = newChapterIds[object.chapterId] ?? object.chapterId
                                }
                                do {
                                    try context.save()
                                } catch {
                                    LogManager.logger.error("Failed to save id migration: \(error)")
                                }
                            }

                            NotificationCenter.default.post(name: .updateLibrary, object: nil)
                            NotificationCenter.default.post(name: .updateHistory, object: nil)

                            await self.hideLoadingIndicator()
                        }
                    } else {
                        // otherwise, we just show the migration view and let the user do it
                        Task {
                            let sourceManga = await CoreDataManager.shared.container.performBackgroundTask { context in
                                let objects = CoreDataManager.shared.getLibraryManga(sourceId: source.id, context: context)
                                return objects.compactMap { $0.manga?.toManga() }
                            }
                            let migrateView = MigrateMangaView(manga: sourceManga, destination: source.id)
                            self.topViewController?.present(
                                UIHostingController(rootView: SwiftUINavigationView(rootView: migrateView)),
                                animated: true
                            )
                        }
                    }
                }
            ]
        )
    }

    func presentAlert(
        title: String,
        message: String? = nil,
        actions: [UIAlertAction] = [],
        textFieldHandlers: [((UITextField) -> Void)] = [],
        textFieldDisablesLastActionWhenEmpty: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        for handler in textFieldHandlers {
            alertController.addTextField { textField in
                handler(textField)

                if textFieldDisablesLastActionWhenEmpty && textFieldHandlers.count == 1 {
                    actions.last?.isEnabled = !(textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                    NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: textField, queue: .main) { _ in
                        Task { @MainActor in
                            let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            actions.last?.isEnabled = !text.isEmpty
                        }
                    }
                }
            }
        }

        // if no actions are provided, add a default 'OK' action
        if actions.isEmpty {
            let okAction = UIAlertAction(title: NSLocalizedString("OK"), style: .cancel)
            alertController.addAction(okAction)
        } else {
            for action in actions {
                alertController.addAction(action)
            }
        }

        topViewController?.present(alertController, animated: true, completion: completion)
    }
}

extension AppDelegate: ImagePipelineDelegate {
    nonisolated func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        if context.request.userInfo[.processesKey] as? Bool == true {
            // when using a page processor, don't decode data as an image since it may be invalid
            ImageDecoders.Empty.init()
        } else {
            pipeline.configuration.makeImageDecoder(context)
        }
    }
}
