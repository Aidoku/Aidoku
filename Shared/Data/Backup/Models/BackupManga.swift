//
//  BackupManga.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import CoreData

struct BackupManga: Codable {
    var id: String
    var sourceId: String
    var title: String
    var author: String?
    var artist: String?
    var desc: String?
    var tags: [String]?
    var cover: String?
    var url: String?
    var status: Int
    var nsfw: Int
    var viewer: Int
    var chapterFlags: Int?
    var langFilter: String?

    init(mangaObject: MangaObject) {
        id = mangaObject.id
        sourceId = mangaObject.sourceId
        title = mangaObject.title
        author = mangaObject.author
        artist = mangaObject.artist
        desc = mangaObject.desc
        tags = mangaObject.tags
        cover = mangaObject.cover
        url = mangaObject.url
        status = Int(mangaObject.status)
        nsfw = Int(mangaObject.nsfw)
        viewer = Int(mangaObject.viewer)
        chapterFlags = Int(mangaObject.chapterFlags)
        langFilter = mangaObject.langFilter
    }

    func toObject(context: NSManagedObjectContext? = nil) -> MangaObject {
        let obj: MangaObject
        if let context = context {
            obj = MangaObject(context: context)
        } else {
            obj = MangaObject()
        }
        obj.id = id
        obj.sourceId = sourceId
        obj.title = title
        obj.author = author
        obj.artist = artist
        obj.desc = desc
        obj.tags = tags
        obj.cover = cover
        obj.url = url
        obj.status = Int16(status)
        obj.nsfw = Int16(nsfw)
        obj.viewer = Int16(viewer)
        obj.chapterFlags = Int16(chapterFlags ?? 0)
        obj.langFilter = langFilter
        return obj
    }
}
