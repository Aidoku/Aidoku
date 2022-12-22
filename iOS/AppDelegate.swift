//
//  AppDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import UIKit
import Kingfisher
import Nuke

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var loadingAlert: UIAlertController?

    var navigationController: UINavigationController? {
        (UIApplication.shared.windows.first?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController
    }

    var visibleViewController: UIViewController? {
        ((UIApplication.shared.windows.first?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController)?
            .visibleViewController
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UserDefaults.standard.register(
            defaults: [
//                "currentVersion": "0.6", // uncomment next update

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
                "Library.lockedCategories": [],

                "Library.updateInterval": "daily",
                "Library.skipTitles": ["hasUnread", "completed", "notStarted"],
                "Library.excludedUpdateCategories": [],
                "Library.updateOnlyOnWifi": true,
                "Library.refreshMetadata": false,

                "Browse.languages": ["multi"] + Locale.preferredLanguages.map { Locale(identifier: $0).languageCode },
                "Browse.updateCount": 0,
                "Browse.showNsfwSources": false,
                "Browse.labelNsfwSources": true,

                "History.lockHistoryTab": false,

                "Reader.readingMode": "default",
                "Reader.downsampleImages": true,
                "Reader.saveImageOption": true,
                "Reader.verticalInfiniteScroll": false,
                "Reader.pagesToPreload": 2,
                "Reader.pagedPageLayout": "auto"
            ]
        )

        KingfisherManager.shared.cache.memoryStorage.config.totalCostLimit = 300 * 1024 * 1024
        KingfisherManager.shared.cache.memoryStorage.config.countLimit = 150
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = 1000 * 1024 * 1024

        DataLoader.sharedUrlCache.diskCapacity = 0

        let pipeline = ImagePipeline {
            let dataCache = try? DataCache(name: "xyz.skitty.Aidoku.datacache")
            dataCache?.sizeLimit = 300 * 1024 * 1024
            $0.dataCache = dataCache
        }

        ImagePipeline.shared = pipeline

        // migrate history to 0.6 format
        if UserDefaults.standard.string(forKey: "currentVersion") == "0.5" {
            Task.detached {
                await self.migrateHistory()
            }
        }

        UserDefaults.standard.set(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, forKey: "currentVersion")

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

    func migrateHistory() async {
        showLoadingIndicator()
        try? await Task.sleep(nanoseconds: 500 * 1000000)
        await CoreDataManager.shared.migrateChapterHistory()
        loadingAlert?.dismiss(animated: true)
    }

    func showLoadingIndicator() {
        if loadingAlert == nil {
            loadingAlert = UIAlertController(title: nil, message: NSLocalizedString("LOADING_ELLIPSIS", comment: ""), preferredStyle: .alert)
            let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
            loadingIndicator.hidesWhenStopped = true
            loadingIndicator.style = .medium
            loadingIndicator.startAnimating()
            loadingAlert?.view.addSubview(loadingIndicator)
        }
        navigationController?.present(loadingAlert!, animated: true, completion: nil)
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
                            let vc = MangaViewController(manga: manga, chapters: [])
                            if let chapterId = url.pathComponents[safe: 2] {
                                vc.scrollToChapter = Chapter(
                                    sourceId: source.id,
                                    id: chapterId,
                                    mangaId: manga.id,
                                    title: nil,
                                    sourceOrder: 0
                                )
                            }
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
                            MangaViewController(manga: manga, chapters: [], scrollTo: link?.chapter), animated: true
                        )
                    }
                }
            }
        }
    }

    func sendAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
}
