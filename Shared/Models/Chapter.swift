//
//  Chapter.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation

struct Chapter: KVCObject, Identifiable, Hashable {

    let sourceId: String
    let id: String
    let mangaId: String
    let title: String?
    let scanlator: String?
    let lang: String
    let chapterNum: Float?
    let volumeNum: Float?
    let dateUploaded: Date?
    let sourceOrder: Int

    init(
        sourceId: String,
        id: String,
        mangaId: String,
        title: String?,
        scanlator: String? = nil,
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
        self.lang = lang
        self.chapterNum = chapterNum
        self.volumeNum = volumeNum
        self.dateUploaded = dateUploaded
        self.sourceOrder = sourceOrder
    }

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
