//
//  LibrarySettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

import Foundation

struct LibrarySettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            sortOption,
            sortAscending,
            listView,
            lastUpdated,
            opensReaderView,
            resumeLastOpenedChapter,
            continueReadingOnReselect,
            unreadChapterBadges,
            downloadedChapterBadges,
            pinTitles,
            lockLibrary,
            currentCategory,
            defaultCategory,
            lockedCategories,
            showUncategorizedCategory,
            updateInterval,
            skipTitles,
            excludedUpdateCategories,
            backgroundRefresh,
            updateOnlyOnWifi,
            refreshMetadata,
            notifyNewChapters,
            filtersData
        ]
    }

    let sortOption = SettingsKey<Int>("Library.sortOption", default: LibraryViewModel.SortMethod.lastOpened.rawValue)
    let sortAscending = SettingsKey<Bool>("Library.sortAscending", default: false)
    let listView = SettingsKey<Bool>("Library.listView", default: false)

    let lastUpdated = SettingsKey<Date>("Library.lastUpdated", default: Date.distantPast)
    let opensReaderView = SettingsKey<Bool>("Library.opensReaderView", default: false)
    let resumeLastOpenedChapter = SettingsKey<Bool>("Library.resumeLastOpenedChapter", default: false)
    let continueReadingOnReselect = SettingsKey<Bool>("Library.continueReadingOnReselect", default: true)
    let unreadChapterBadges = SettingsKey<Bool>("Library.unreadChapterBadges", default: true)
    let downloadedChapterBadges = SettingsKey<Bool>("Library.downloadedChapterBadges", default: true)
    let pinTitles = SettingsKey<String>("Library.pinTitles", default: LibraryViewModel.PinType.none.rawValue)
    let lockLibrary = SettingsKey<Bool>("Library.lockLibrary", default: false)

    let currentCategory = SettingsKey<String?>("Library.currentCategory")
    let defaultCategory = SettingsKey<String?>("Library.defaultCategory")
    let lockedCategories = SettingsKey<[String]>("Library.lockedCategories", default: [])
    let showUncategorizedCategory = SettingsKey<Bool>("Library.showUncategorizedCategory", default: false)

    let updateInterval = SettingsKey<String>("Library.updateInterval", default: "daily")
    let skipTitles = SettingsKey<[String]>("Library.skipTitles", default: ["hasUnread", "completed", "notStarted"])
    let excludedUpdateCategories = SettingsKey<[String]>("Library.excludedUpdateCategories", default: [])
    let backgroundRefresh = SettingsKey<Bool>("Library.backgroundRefresh", default: true)
    let updateOnlyOnWifi = SettingsKey<Bool>("Library.updateOnlyOnWifi", default: true)
    let refreshMetadata = SettingsKey<Bool>("Library.refreshMetadata", default: false)
    let notifyNewChapters = SettingsKey<Bool>("Library.notifyNewChapters", default: false)

    let filtersData = SettingsKey<Data?>("Library.filters")
}
