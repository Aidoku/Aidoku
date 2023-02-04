//
//  BackupChapter.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import CoreData

struct BackupChapter: Codable {
    var sourceId: String
    var mangaId: String
    var id: String
    var title: String?
    var scanlator: String?
    var lang: String
    var chapter: Float?
    var volume: Float?
    var dateUploaded: Date?
    var sourceOrder: Int

    init(chapterObject: ChapterObject) {
        sourceId = chapterObject.sourceId
        mangaId = chapterObject.mangaId
        id = chapterObject.id
        title = chapterObject.title
        scanlator = chapterObject.scanlator
        lang = chapterObject.lang
        chapter = chapterObject.chapter?.floatValue
        volume = chapterObject.volume?.floatValue
        dateUploaded = chapterObject.dateUploaded
        sourceOrder = Int(chapterObject.sourceOrder)
    }

    func toObject(context: NSManagedObjectContext? = nil) -> ChapterObject {
        let obj: ChapterObject
        if let context = context {
            obj = ChapterObject(context: context)
        } else {
            obj = ChapterObject(context: CoreDataManager.shared.context)
        }
        obj.sourceId = sourceId
        obj.mangaId = mangaId
        obj.id = id
        obj.title = title
        obj.scanlator = scanlator
        obj.lang = lang
        if let chapter = chapter {
            obj.chapter = NSNumber(value: chapter)
        } else {
            obj.chapter = nil
        }
        if let volume = volume {
            obj.volume = NSNumber(value: volume)
        } else {
            obj.volume = nil
        }
        obj.dateUploaded = dateUploaded
        obj.sourceOrder = Int16(sourceOrder)
        return obj
    }
}
