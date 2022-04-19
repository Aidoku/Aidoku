//
//  SceneDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var navigationController: UINavigationController? {
        (UIApplication.shared.windows.first?.rootViewController as? UITabBarController)?.selectedViewController as? UINavigationController
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let tabController = UITabBarController()
        let libraryViewController = UINavigationController(rootViewController: LibraryViewController())
        let browseViewController = UINavigationController(rootViewController: BrowseViewController())
        let searchViewController = UINavigationController(rootViewController: SearchViewController())
        let settingsViewController = UINavigationController(rootViewController: SettingsViewController())
        libraryViewController.tabBarItem = UITabBarItem(title: "Library", image: UIImage(systemName: "books.vertical.fill"), tag: 0)
        browseViewController.tabBarItem = UITabBarItem(title: "Browse", image: UIImage(systemName: "globe"), tag: 1)
        searchViewController.tabBarItem = UITabBarItem(title: "Search", image: UIImage(systemName: "magnifyingglass"), tag: 2)
        settingsViewController.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gear"), tag: 3)
        tabController.viewControllers = [libraryViewController, browseViewController, searchViewController, settingsViewController]

        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = tabController
            window.tintColor = .systemPink

            if UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                window.overrideUserInterfaceStyle = .unspecified
            } else {
                if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                    window.overrideUserInterfaceStyle = .light
                } else {
                    window.overrideUserInterfaceStyle = .dark
                }
            }

            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            if url.scheme == "aidoku" { // aidoku://
                if url.host == "setSourceList" { // setSourceList?url=
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    if let listUrl = components?.queryItems?.first(where: { $0.name == "url" })?.value {
                        UserDefaults.standard.set(listUrl, forKey: "Browse.sourceListURL")
                        NotificationCenter.default.post(name: Notification.Name("Browse.sourceListURL"), object: nil)
                        sendAlert(title: "Source List Configured",
                                  message: "You can now browse external sources in the Browse tab.")
                    }
                } else if let source = SourceManager.shared.sources.first(where: { $0.id == url.host }) { // sourceId/mangaId
                    Task { @MainActor in
                        if let manga = try? await source.getMangaDetails(manga: Manga(sourceId: source.id, id: url.lastPathComponent)) {
                            navigationController?.pushViewController(
                                MangaViewController(manga: manga, chapters: []), animated: true
                            )
                        }
                    }
                } else { // deep links
                    handleDeepLink(url: url)
                }
            } else if url.pathExtension == "aix" {
                Task {
                    _ = await SourceManager.shared.importSource(from: url)
                }
            } else if url.pathExtension == "json" {
                if BackupManager.shared.importBackup(from: url) {
                    sendAlert(title: "Backup Imported",
                              message: "To restore to this backup, find it in the backups page in settings.")
                } else {
                    sendAlert(title: "Import Failed",
                              message: "Failed to save backup. Maybe try importing from a different location.")
                }
            } else {
                handleDeepLink(url: url)
            }
        }
    }

    func handleDeepLink(url: URL) {
        if let targetUrl = (url as NSURL).resourceSpecifier {
            var targetSource: Source?
            for source in SourceManager.shared.sources {
                if let sourceUrl = source.manifest.info.url,
                   let url = NSURL(string: sourceUrl)?.resourceSpecifier,
                   targetUrl.hasPrefix(url) {
                    targetSource = source
                } else if let urls = source.manifest.info.urls {
                    for sourceUrl in urls {
                        if let url = NSURL(string: sourceUrl)?.resourceSpecifier,
                           targetUrl.hasPrefix(url) {
                            targetSource = source
                        }
                    }
                }
                if targetSource != nil { break }
            }
            if let targetSource = targetSource {
                Task { @MainActor in
                    let link = try? await targetSource.handleUrl(url: url.absoluteString)
                    if let manga = link?.manga {
                        navigationController?.pushViewController(
                            MangaViewController(manga: manga, chapters: []), animated: true
                        )
                    }
                }
            }
        }
    }

    func sendAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
}
