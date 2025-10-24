//
//  NotificationName.swift
//  Aidoku
//
//  Created by Skitty on 4/29/25.
//

import Foundation

extension Notification.Name {
    static let updateSourceLists = Self("updateSourceLists")
    static let updateBackupList = Self("updateBackupList")

    // library
    static let updateLibrary = Self("updateLibrary")
    static let addToLibrary = Self("addToLibrary")
    static let removeFromLibrary = Self("removeFromLibrary")
    static let migratedManga = Self("migratedManga")
    static let updateMangaDetails = Self("updateMangaDetails")
    static let updateCategories = Self("updateCategories")

    // history
    static let updateHistory = Self("updateHistory")
    static let historyAdded = Self("historyAdded")
    static let historyRemoved = Self("historyRemoved")
    static let historySet = Self("historySet")

    // trackers
    static let updateTrackers = Self("updateTrackers")
    static let trackItemAdded = Self("trackItemAdded")
    static let syncTrackItem = Self("syncTrackItem")

    // downloads
    static let downloadProgressed = Self("downloadProgressed")
    static let downloadFinished = Self("downloadFinished")
    static let downloadRemoved = Self("downloadRemoved")
    static let downloadCancelled = Self("downloadCancelled")
    static let downloadsRemoved = Self("downloadsRemoved")
    static let downloadsCancelled = Self("downloadsCancelled")
    static let downloadsQueued = Self("downloadsQueued")
    static let downloadsPaused = Self("downloadsPaused")
    static let downloadsResumed = Self("downloadsResumed")

    // browse
    static let filterExternalSources = Self("filterExternalSources")

    // reader
    static let readerReadingMode = Self("Reader.readingMode")
    static let readerTapZones = Self("Reader.tapZones")

    // settings
    static let portraitRowsSetting = Self("General.portraitRows")
    static let landscapeRowsSetting = Self("General.landscapeRows")
    static let historyLockTabSetting = Self("History.lockHistoryTab")
}
