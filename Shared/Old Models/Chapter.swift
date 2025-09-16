//
//  Chapter.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation
import AidokuRunner

class Chapter: Codable, Identifiable {

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
    var thumbnail: String?
    var locked: Bool = false
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
        thumbnail: String? = nil,
        locked: Bool = false,
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
        self.thumbnail = thumbnail
        self.locked = locked
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

extension Chapter {
    func toNew() -> AidokuRunner.Chapter {
        AidokuRunner.Chapter(
            key: id,
            title: title,
            chapterNumber: chapterNum,
            volumeNumber: volumeNum,
            dateUploaded: dateUploaded,
            scanlators: scanlator?.components(separatedBy: ", "),
            url: url.flatMap({ URL(string: $0) }),
            language: lang,
            thumbnail: thumbnail,
            locked: locked
        )
    }

    /// Returns a formatted title for this chapter.
    /// `Vol.X Ch.X - Title`
    func makeTitle() -> String {
        if volumeNum == nil && title == nil, let chapterNum = chapterNum {
            // Chapter X
            return String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
        } else {
            var components: [String] = []
            // Vol.X
            if let volumeNum = volumeNum {
                components.append(
                    String(format: NSLocalizedString("VOL_X", comment: ""), volumeNum)
                )
            }
            // Ch.X
            if let chapterNum = chapterNum {
                components.append(
                    String(format: NSLocalizedString("CH_X", comment: ""), chapterNum)
                )
            }
            // title
            if let title = title {
                if !components.isEmpty {
                    components.append("-")
                }
                components.append(title)
            }
            return components.joined(separator: " ")
        }
    }
}
