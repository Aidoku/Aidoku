//
//  BackupManga.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import CoreData

struct BackupManga: Codable, Hashable {
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
    var neverUpdate: Bool?
    var nextUpdateTime: Date?
    var chapterFlags: Int?
    var langFilter: String?
    var scanlatorFilter: [String]?
    var editedKeys: Int?

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
        neverUpdate = mangaObject.neverUpdate
        nextUpdateTime = mangaObject.nextUpdateTime
        chapterFlags = Int(mangaObject.chapterFlags)
        langFilter = mangaObject.langFilter
        scanlatorFilter = mangaObject.scanlatorFilter
        editedKeys = Int(mangaObject.editedKeys)
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
        obj.neverUpdate = neverUpdate ?? false
        obj.nextUpdateTime = nextUpdateTime
        obj.chapterFlags = Int16(chapterFlags ?? 0)
        obj.langFilter = langFilter
        obj.scanlatorFilter = scanlatorFilter
        obj.editedKeys = Int32(editedKeys ?? 0)
        return obj
    }
}
