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
        libraryViewController.tabBarItem = UITabBarItem(title: NSLocalizedString("LIBRARY", comment: ""),
                                                        image: UIImage(systemName: "books.vertical.fill"), tag: 0)
        browseViewController.tabBarItem = UITabBarItem(title: NSLocalizedString("BROWSE", comment: ""),
                                                       image: UIImage(systemName: "globe"), tag: 1)
        searchViewController.tabBarItem = UITabBarItem(title: NSLocalizedString("SEARCH", comment: ""),
                                                       image: UIImage(systemName: "magnifyingglass"), tag: 2)
        settingsViewController.tabBarItem = UITabBarItem(title: NSLocalizedString("SETTINGS", comment: ""),
                                                         image: UIImage(systemName: "gear"), tag: 3)
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
                if url.host == "addSourceList" { // addSourceList?url=
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    if let listUrlString = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                       let listUrl = URL(string: listUrlString) {
                        guard !SourceManager.shared.sourceLists.contains(listUrl) else { return }
                        Task {
                            let success = await SourceManager.shared.addSourceList(url: listUrl)
                            if success {
                                sendAlert(title: NSLocalizedString("SOURCE_LIST_ADDED", comment: ""),
                                          message: NSLocalizedString("SOURCE_LIST_ADDED_TEXT", comment: ""))
                            } else {
                                sendAlert(title: NSLocalizedString("SOURCE_LIST_ADD_FAIL", comment: ""),
                                          message: NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT", comment: ""))
                            }
                        }
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
                    sendAlert(title: NSLocalizedString("BACKUP_IMPORT_SUCCESS", comment: ""),
                              message: NSLocalizedString("BACKUP_IMPORT_SUCCESS_TEXT", comment: ""))
                } else {
                    sendAlert(title: NSLocalizedString("BACKUP_IMPORT_FAIL", comment: ""),
                              message: NSLocalizedString("BACKUP_IMPORT_FAIL_TEXT", comment: ""))
                }
            } else {
                handleDeepLink(url: url)
            }
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
                            MangaViewController(manga: manga, chapters: []), animated: true
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
