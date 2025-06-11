//
//  NotificationName.swift
//  Aidoku
//
//  Created by Skitty on 4/29/25.
//

import Foundation

extension Notification.Name {
    static let updateSourceLists = Self("updateSourceLists")

    // manga
    static let addToLibrary = Self("addToLibrary")
    static let migratedManga = Self("migratedManga")

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

    // browse
    static let browseLanguages = Self("Browse.languages")

    // settings
    static let portraitRowsSetting = Self("General.portraitRows")
    static let landscapeRowsSetting = Self("General.landscapeRows")
}
