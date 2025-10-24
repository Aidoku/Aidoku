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
        let loadingAlert = UIAlertController(title: nil, message: NSLocalizedString("LOADING_ELLIPSIS", comment: ""), preferredStyle: .alert)
        progressView.tintColor = loadingAlert.view.tintColor
        loadingAlert.view.addSubview(progressView)
        loadingAlert.view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            progressView.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
            progressView.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -8),
            progressView.widthAnchor.constraint(equalTo: loadingAlert.view.widthAnchor, constant: -30)
        ])
        return loadingAlert
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.style = .medium
        loadingIndicator.tag = 3
        return loadingIndicator
    }()

    private lazy var progressView: UIProgressView = {
        let progressView = UIProgressView(frame: .zero)
        progressView.progress = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false
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
                "isSideloaded": Self.isSideloaded, // for icloud sync setting

                "General.incognitoMode": false,
                "General.icloudSync": false,
                "General.appearance": 0,
                "General.useSystemAppearance": true,
                "General.portraitRows": UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2,
                "General.landscapeRows": UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4,

                "Library.sortOption": 2, // lastOpened
                "Library.sortAscending": false,

                "Library.lastUpdated": Date.distantPast.timeIntervalSince1970,

                "Library.opensReaderView": false,
                "Library.unreadChapterBadges": true,
                "Library.pinManga": false,
                "Library.pinMangaType": 0,
                "Library.lockLibrary": false,

                "Library.lockedCategories": [String](),

                "Library.updateInterval": "daily",
                "Library.skipTitles": ["hasUnread", "completed", "notStarted"],
                "Library.excludedUpdateCategories": [String](),
                "Library.updateOnlyOnWifi": true,
                "Library.refreshMetadata": false,
                "Library.deleteDownloadAfterReading": false,

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

                "Tracking.updateAfterReading": true,
                "Tracking.autoSyncFromTracker": false
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
                UserDefaults.standard.register(defaults: ["isiCloudAvailable": isiCloudAvailable])
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

        networkObserverId = Reachability.registerConnectionTypeObserver { connectionType in
            switch connectionType {
            case .wifi:
                if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
                    DownloadManager.shared.ignoreConnectionType = false
                    DownloadManager.shared.resumeDownloads()
                }
            case .cellular, .none:
                if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") && !DownloadManager.shared.ignoreConnectionType {
                    DownloadManager.shared.pauseDownloads()
                }
            }
        }

        application.applicationSupportsShakeToEdit = true

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        handleUrl(url: url)
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        guard let networkObserverId else { return }
        Reachability.unregisterConnectionTypeObserver(networkObserverId)
    }

    func performMigration() {
        // migrate history to 0.6 format
        if UserDefaults.standard.string(forKey: "currentVersion") == "0.5" {
            Task.detached {
                await self.migrateHistory()
            }
        }

        // migrate showNsfwSources setting
        if UserDefaults.standard.bool(forKey: "Browse.showNsfwSources") {
            UserDefaults.standard.setValue(["safe", "containsNsfw", "primarilyNsfw"], forKey: "Browse.contentRatings")
            UserDefaults.standard.removeObject(forKey: "Browse.showNsfwSources")
        }

        UserDefaults.standard.set(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, forKey: "currentVersion")
    }

    func migrateHistory() async {
        showLoadingIndicator(style: .progress)
        try? await Task.sleep(nanoseconds: 500 * 1000000)
        await CoreDataManager.shared.migrateChapterHistory(progress: { progress in
            Task { @MainActor in
                self.indicatorProgress = progress
            }
        })
        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
        hideLoadingIndicator()
    }

    enum LoadingStyle {
        case indefinite
        case progress
    }

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
        visibleViewController?.present(loadingAlert, animated: true, completion: completion)
    }

    func hideLoadingIndicator(completion: (() -> Void)? = nil) {
        loadingAlert.dismiss(animated: true) {
            self.loadingIndicator.stopAnimating()
            completion?()
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
                Task { @MainActor in
                    if url.pathComponents.count > 1 { // /sourceId/mangaId
                        if let manga = try? await source.getMangaUpdate(
                            manga: AidokuRunner.Manga(sourceKey: source.id, key: url.pathComponents[1], title: ""),
                            needsDetails: true,
                            needsChapters: false
                        ) {
                            if let navigationController {
                                navigationController.pushViewController(
                                    MangaViewController(
                                        source: source,
                                        manga: manga,
                                        parent: navigationController.topViewController,
                                        scrollToChapterKey: url.pathComponents[safe: 2] // /sourceId/mangaId/chapterId
                                    ),
                                    animated: true
                                )
                            }
                        }
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
                if let tracker = TrackerManager.shared.trackers.first(where: {
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
                let result = try? await SourceManager.shared.importSource(from: url)
                if result == nil {
                    presentAlert(
                        title: NSLocalizedString("IMPORT_FAIL", comment: ""),
                        message: NSLocalizedString("SOURCE_IMPORT_FAIL_TEXT", comment: "")
                    )
                }
            }
        } else if url.pathExtension == "json" || url.pathExtension == "aib" {
            if BackupManager.shared.importBackup(from: url) {
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
        await SourceManager.shared.loadSources()

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
                    ) else { return false }

                    navigationController.pushViewController(
                        MangaViewController(
                            source: targetSource,
                            manga: manga,
                            parent: navigationController.topViewController,
                            scrollToChapterKey: link?.chapterKey
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
                            await CoreDataManager.shared.container.performBackgroundTask { context in
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

                            self.hideLoadingIndicator()
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
        completion: (() -> Void)? = nil
    ) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        for handler in textFieldHandlers {
            alertController.addTextField { textField in
                handler(textField)
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
    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        if context.request.userInfo[.processesKey] as? Bool == true {
            // when using a page processor, don't decode data as an image since it may be invalid
            ImageDecoders.Empty.init()
        } else {
            pipeline.configuration.makeImageDecoder(context)
        }
    }
}
