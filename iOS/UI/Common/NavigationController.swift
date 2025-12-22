//
//  NavigationController.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 11/02/2024.
//

import UIKit

class NavigationController: UINavigationController {
    // This is a workaround to fix an iOS bug that occurs when mixing UIKit with SwiftUI,
    // that causes the current TabBarItem title to be lost when navigating inside SwiftUI views.
    // See: https://stackoverflow.com/questions/62662313/uitabbar-containing-swiftui-view
    private var storedTabBarItem: UITabBarItem?
    override var tabBarItem: UITabBarItem! {
        get { storedTabBarItem ?? super.tabBarItem }
        set { storedTabBarItem = newValue }
    }

    // fix for incognito mode banner status bar text being the wrong color sometimes on ios 26+
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            traitCollection.userInterfaceStyle == .light ? .darkContent : .lightContent
        } else {
            .default
        }
    }
}
