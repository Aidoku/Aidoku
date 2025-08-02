//
//  TabBarController.swift
//  Aidoku
//
//  Created by Skitty on 7/26/25.
//

import SwiftUI

class TabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let libraryViewController = SwiftUINavigationController(rootViewController: LibraryViewController())
        let browseViewController = UINavigationController(rootViewController: BrowseViewController())
        let historyPath = NavigationCoordinator(rootViewController: nil)
        let historyHostingController = UIHostingController(rootView: HistoryView()
            .environmentObject(historyPath))
        historyPath.rootViewController = historyHostingController
        let historyViewController = UINavigationController(rootViewController: historyHostingController)
        let searchViewController = UINavigationController(rootViewController: SearchViewController())
        let settingsViewController = UINavigationController(rootViewController: SettingsViewController())

        libraryViewController.navigationBar.prefersLargeTitles = true
        browseViewController.navigationBar.prefersLargeTitles = true
        historyViewController.navigationBar.prefersLargeTitles = true
        searchViewController.navigationBar.prefersLargeTitles = true
        settingsViewController.navigationBar.prefersLargeTitles = true

    
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
            tabBarSystemItem: .history,
            tag: 2
        )
        searchViewController.tabBarItem = UITabBarItem(
            tabBarSystemItem: .search,
            tag: 3
        )
        settingsViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("SETTINGS", comment: ""),
            image: UIImage(systemName: "gear"),
            tag: 4
        )
        viewControllers = [
            libraryViewController,
            browseViewController,
            historyViewController,
            searchViewController,
            settingsViewController
        ]
    

        let updateCount = UserDefaults.standard.integer(forKey: "Browse.updateCount")
        browseViewController.tabBarItem.badgeValue = updateCount > 0 ? String(updateCount) : nil

        // fix tab bar background flashing when performing appearance hack on manga view and source view
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBar.scrollEdgeAppearance = tabBarAppearance
    }
}

// MARK: - Keyboard Shortcuts
extension TabBarController {
    override var keyCommands: [UIKeyCommand]? {
        tabBar.items?.enumerated().map { index, item in
            UIKeyCommand(
                title: item.title ?? "Tab \(index + 1)",
                action: #selector(selectTab),
                input: "\(index + 1)",
                modifierFlags: .shiftOrCommand,
                alternates: [],
                attributes: [],
                state: .off
            )
        }
    }

    @objc private func selectTab(sender: UIKeyCommand) {
        guard
            let input = sender.input,
            let newIndex = Int(input),
            newIndex >= 1 && newIndex <= (tabBar.items?.count ?? 0)
        else { return }
        selectedIndex = newIndex - 1
    }

    override var canBecomeFirstResponder: Bool { true }
}
