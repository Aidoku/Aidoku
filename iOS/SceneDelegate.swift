//
//  SceneDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

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
            if url.pathExtension == "aix" {
                Task {
                    _ = await SourceManager.shared.importSource(from: url)
                }
            } else if url.pathExtension == "json" {
                let success = BackupManager.shared.importBackup(from: url)
                let title: String
                let message: String
                if success {
                    title = "Backup Imported"
                    message = "To restore to this backup, find it in the backups page in settings."
                } else {
                    title = "Import Failed"
                    message = "Failed to save backup. Maybe try importing from a different location."
                }
                let importAlert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                importAlert.addAction(UIAlertAction(title: "OK", style: .cancel))
                UIApplication.shared.windows.first?.rootViewController?.present(importAlert, animated: true)
            }
        }
    }
}
