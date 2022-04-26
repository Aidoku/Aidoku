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
                "General.portraitRows": UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2,
                "General.landscapeRows": UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4,

                "Library.opensReaderView": false,
                "Library.unreadChapterBadges": true,
                "Library.pinManga": false,
                "Library.pinMangaType": 0,
                "Library.sortOption": 1,
                "Library.sortAscending": false,

                "Browse.showNsfwSources": false,
                "Browse.labelNsfwSources": true,

                "Reader.readingMode": "default",
                "Reader.downsampleImages": false,
                "Reader.verticalInfiniteScroll": false
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
