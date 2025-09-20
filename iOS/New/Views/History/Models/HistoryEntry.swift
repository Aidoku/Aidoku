//
//  HistoryEntry.swift
//  Aidoku
//
//  Created by Skitty on 7/31/25.
//

import Foundation

struct HistoryEntry: Hashable {
    let sourceKey: String
    let mangaKey: String
    let chapterKey: String

    var date: Date
    var currentPage: Int?
    var totalPages: Int?
    var additionalEntryCount: Int?

    var mangaCacheKey: String {
        "\(sourceKey).\(mangaKey)"
    }
    var chapterCacheKey: String {
        "\(mangaCacheKey).\(chapterKey)"
    }
}
