//
//  Chapter.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation

class Chapter: Identifiable {

    let sourceId: String
    let id: String
    var mangaId: String
    var title: String?
    var scanlator: String?
    var url: String?
    var lang: String
    var chapterNum: Float?
    var volumeNum: Float?
    var dateUploaded: Date?
    var sourceOrder: Int

    init(
        sourceId: String,
        id: String,
        mangaId: String,
        title: String?,
        scanlator: String? = nil,
        url: String? = nil,
        lang: String = "en",
        chapterNum: Float? = nil,
        volumeNum: Float? = nil,
        dateUploaded: Date? = nil,
        sourceOrder: Int
    ) {
        self.sourceId = sourceId
        self.id = id
        self.mangaId = mangaId
        self.title = title == "" ? nil : title
        self.scanlator = scanlator == "" ? nil : scanlator
        self.url = url == "" ? nil : url
        self.lang = lang
        self.chapterNum = chapterNum
        self.volumeNum = volumeNum
        self.dateUploaded = dateUploaded
        self.sourceOrder = sourceOrder
    }
}

extension Chapter: KVCObject {
    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "id": return id
        case "mangaId": return mangaId
        case "title": return title
        case "scanlator": return scanlator
        case "chapterNum": return chapterNum
        case "volumeNum": return volumeNum
        default: return nil
        }
    }
}

extension Chapter: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(sourceId)
        hasher.combine(mangaId)
        hasher.combine(id)
    }
}

extension Chapter: Equatable {
    static func == (lhs: Chapter, rhs: Chapter) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}
