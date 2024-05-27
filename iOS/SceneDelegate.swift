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
        let libraryViewController = SwiftUINavigationController(rootViewController: LibraryViewController())
        let browseViewController = UINavigationController(rootViewController: BrowseViewController())
        let historyViewController = UINavigationController(rootViewController: HistoryViewController())
        let searchViewController = UINavigationController(rootViewController: SearchViewController())
        let settingsViewController = UINavigationController(rootViewController: SettingsViewController())
        libraryViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("LIBRARY", comment: ""),
            image: UIImage(systemName: "books.vertical.fill"),
            tag: 0
        )
        browseViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("BROWSE", comment: ""),
            image: UIImage(systemName: "globe"),
            tag: 1
        )
        historyViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("HISTORY", comment: ""),
            image: UIImage(systemName: "clock.fill"),
            tag: 2
        )
        searchViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("SEARCH", comment: ""),
            image: UIImage(systemName: "magnifyingglass"),
            tag: 3
        )
        settingsViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("SETTINGS", comment: ""),
            image: UIImage(systemName: "gear"),
            tag: 4
        )
        tabController.viewControllers = [
            libraryViewController, browseViewController, historyViewController, searchViewController, settingsViewController
        ]

        let updateCount = UserDefaults.standard.integer(forKey: "Browse.updateCount")
        browseViewController.tabBarItem.badgeValue = updateCount > 0 ? String(updateCount) : nil

        // fix tab bar background flashing when performing appearance hack on manga view and source view
        if #available(iOS 15.0, *) {
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            tabController.tabBar.scrollEdgeAppearance = tabBarAppearance
        }

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

        if let url = connectionOptions.urlContexts.first?.url,
           let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.handleUrl(url: url)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url, let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.handleUrl(url: url)
        }
    }
}
