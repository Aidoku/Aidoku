//
//  BrowseSettings.swift
//  Aidoku
//
//  Created by skitty on 8/25/26.
//

import AidokuRunner
import Foundation

struct BrowseSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            languages,
            contentRatings,
            updateCount,
            pinnedList,
            disabledSources,
            sourceLists
        ]
    }

    let languages = SettingsKey<Set<String>>("Browse.languages", default: SourceLanguage.preferredCodes())
    let contentRatings = SettingsKey<Set<AidokuRunner.SourceContentRating>>("Browse.contentRatings", default: [.safe, .containsNsfw])
    let updateCount = SettingsKey<Int>("Browse.updateCount", default: 0)
    let pinnedList = SettingsKey<[String]>("Browse.pinnedList", default: [])
    let disabledSources = SettingsKey<Set<String>>("Browse.disabledSources", default: [])
    let sourceLists = SettingsKey<Set<URL>>("Browse.sourceLists", default: [])
}
