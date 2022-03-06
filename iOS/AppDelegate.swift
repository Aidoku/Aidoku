//
//  AppDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import UIKit
import Kingfisher

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        UserDefaults.standard.register(
            defaults: [
                "General.icloudSync": false,
                "General.appearance": 0,
                "General.useSystemAppearance": true,

                "Reader.downsampleImages": true,

                "Library.opensReaderView": false,
                "Library.unreadChapterBadges": true,

                "Browse.showNsfwSources": false,
                "Browse.labelNsfwSources": true
            ]
        )

        KingfisherManager.shared.cache.memoryStorage.config.totalCostLimit = 300 * 1024 * 1024
        KingfisherManager.shared.cache.memoryStorage.config.countLimit = 150

        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
