//
//  VocabEntry.swift
//  Aidoku
//
//  Created by skitty on 7/25/26.
//

import Foundation

struct VocabEntry: Hashable {
    let chapterId: ChapterIdentifier
    let word: String
    var reading: String?
    var sentence: String?
    var page: Int?
    var createdDate: Date = .now
}

extension VocabEntry: Identifiable {
    var id: Int { hashValue }
}
