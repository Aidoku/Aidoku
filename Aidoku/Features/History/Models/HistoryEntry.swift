//
//  HistoryEntry.swift
//  Aidoku
//
//  Created by Skitty on 7/31/25.
//

import Foundation

struct HistoryEntry: Hashable {
    let chapterId: ChapterIdentifier

    var date: Date
    var currentPage: Int?
    var totalPages: Int?
    var additionalEntryCount: Int?
}
