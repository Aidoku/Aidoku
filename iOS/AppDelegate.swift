//
//  AppDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import UIKit
import Nuke

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    static let isSideloaded = Bundle.main.bundleIdentifier != "xyz.skitty.Aidoku"
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

    var navigationController: UINavigationController? {
        (UIApplication.shared.windows.first?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController
    }

    var visibleViewController: UIViewController? {
        ((UIApplication.shared.windows.first?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController)?
            .visibleViewController
    }

    var topViewController: UIViewController? {
        if var topController = UIApplication.shared.windows.first?.rootViewController {
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
                "General.useMangaTint": true,
                "General.showSourceLabel": true,
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

                "Library.defaultCategory": [""],
                "Library.lockedCategories": [String](),

                "Library.updateInterval": "daily",
                "Library.skipTitles": ["hasUnread", "completed", "notStarted"],
                "Library.excludedUpdateCategories": [String](),
                "Library.updateOnlyOnWifi": true,
                "Library.refreshMetadata": false,
                "Library.deleteDownloadAfterReading": false,

                "Browse.languages": ["multi"] + Locale.preferredLanguages.map { Locale(identifier: $0).languageCode },
                "Browse.updateCount": 0,
                "Browse.showNsfwSources": false,
                "Browse.labelNsfwSources": true,

                "History.lockHistoryTab": false,

                "Reader.readingMode": "auto",
                "Reader.skipDuplicateChapters": true,
                "Reader.downsampleImages": true,
                "Reader.cropBorders": false,
                "Reader.saveImageOption": true,
                "Reader.backgroundColor": "black",
                "Reader.pagesToPreload": 2,
                "Reader.pagedPageLayout": "auto",
                "Reader.verticalInfiniteScroll": true,
                "Reader.pillarbox": false,
                "Reader.pillarboxAmount": 15,
                "Reader.pillarboxOrientation": "both"
            ]
        )

        DataLoader.sharedUrlCache.diskCapacity = 0

        let pipeline = ImagePipeline {
            let dataLoader: DataLoader = {
                let config = URLSessionConfiguration.default
                config.urlCache = nil
                return DataLoader(configuration: config)
            }()
            let dataCache = try? DataCache(name: "xyz.skitty.Aidoku.datacache") // disk cache
            let imageCache = Nuke.ImageCache() // memory cache
            dataCache?.sizeLimit = 500 * 1024 * 1024
            imageCache.costLimit = 100 * 1024 * 1024
            $0.dataCache = dataCache
            $0.imageCache = imageCache
            $0.dataLoader = dataLoader
            $0.dataCachePolicy = .automatic
            $0.isStoringPreviewsInMemoryCache = false
        }

        ImagePipeline.shared = pipeline

        // migrate history to 0.6 format
        if UserDefaults.standard.string(forKey: "currentVersion") == "0.5" {
            Task.detached {
                await self.migrateHistory()
            }
        }

        UserDefaults.standard.set(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, forKey: "currentVersion")

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

    func migrateHistory() async {
        showLoadingIndicator(style: .progress)
        try? await Task.sleep(nanoseconds: 500 * 1000000)
        await CoreDataManager.shared.migrateChapterHistory(progress: { progress in
            Task { @MainActor in
                self.progressView.progress = progress
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

    // swiftlint:disable:next cyclomatic_complexity
    func handleUrl(url: URL) {
        if url.scheme == "aidoku" { // aidoku://
            if url.host == "addSourceList" { // addSourceList?url=
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let listUrlString = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                   let listUrl = URL(string: listUrlString) {
                    guard !SourceManager.shared.sourceLists.contains(listUrl) else { return }
                    Task {
                        let success = await SourceManager.shared.addSourceList(url: listUrl)
                        if success {
                            sendAlert(
                                title: NSLocalizedString("SOURCE_LIST_ADDED", comment: ""),
                                message: NSLocalizedString("SOURCE_LIST_ADDED_TEXT", comment: "")
                            )
                        } else {
                            sendAlert(
                                title: NSLocalizedString("SOURCE_LIST_ADD_FAIL", comment: ""),
                                message: NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT", comment: "")
                            )
                        }
                    }
                }
            } else if let host = url.host, let source = SourceManager.shared.source(for: host) {
                Task { @MainActor in
                    if url.pathComponents.count > 1 { // /sourceId/mangaId
                        if let manga = try? await source.getMangaDetails(manga: Manga(sourceId: source.id, id: url.pathComponents[1])) {
                            let scrollTo: Chapter?
                            if let chapterId = url.pathComponents[safe: 2] {
                                scrollTo = Chapter(
                                    sourceId: source.id,
                                    id: chapterId,
                                    mangaId: manga.id,
                                    title: nil,
                                    sourceOrder: 0
                                )
                            } else {
                                scrollTo = nil
                            }
                            let vc = MangaViewController(manga: manga, scrollTo: scrollTo)
                            navigationController?.pushViewController(vc, animated: true)
                        }
                    } else { // /sourceId
                        navigationController?.pushViewController(
                            SourceViewController(source: source),
                            animated: true
                        )
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
                    // deep link
                    handleDeepLink(url: url)
                }
            }
        } else if url.pathExtension == "aix" {
            Task {
                _ = await SourceManager.shared.importSource(from: url)
            }
        } else if url.pathExtension == "json" || url.pathExtension == "aib" {
            if BackupManager.shared.importBackup(from: url) {
                sendAlert(
                    title: NSLocalizedString("BACKUP_IMPORT_SUCCESS", comment: ""),
                    message: NSLocalizedString("BACKUP_IMPORT_SUCCESS_TEXT", comment: "")
                )
            } else {
                sendAlert(
                    title: NSLocalizedString("BACKUP_IMPORT_FAIL", comment: ""),
                    message: NSLocalizedString("BACKUP_IMPORT_FAIL_TEXT", comment: "")
                )
            }
        } else {
            handleDeepLink(url: url)
        }
    }

    func handleDeepLink(url: URL) {
        if let targetUrl = (url as NSURL).resourceSpecifier {
            var targetSource: Source?
            var finalUrl: String?
            for source in SourceManager.shared.sources {
                if let sourceUrl = source.manifest.info.url,
                   let url = NSURL(string: sourceUrl)?.resourceSpecifier,
                   targetUrl.hasPrefix(url) {
                    targetSource = source
                    finalUrl = "\(URL(string: url)?.scheme ?? "https"):\(targetUrl)"
                } else if let urls = source.manifest.info.urls {
                    for sourceUrl in urls {
                        if let url = NSURL(string: sourceUrl)?.resourceSpecifier,
                           targetUrl.hasPrefix(url) {
                            targetSource = source
                            finalUrl = "\(URL(string: url)?.scheme ?? "https"):\(targetUrl)"
                        }
                    }
                }
                if targetSource != nil { break }
            }
            if let targetSource = targetSource, let finalUrl = finalUrl {
                Task { @MainActor in
                    let link = try? await targetSource.handleUrl(url: finalUrl)
                    if let manga = link?.manga {
                        navigationController?.pushViewController(
                            MangaViewController(manga: manga, scrollTo: link?.chapter), animated: true
                        )
                    }
                }
            }
        }
    }

    func sendAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        topViewController?.present(alert, animated: true)
    }
}
