//
//  ChapterObject.swift
//  Aidoku
//
//  Created by Skitty on 1/27/22.
//

import Foundation
import CoreData
import AidokuRunner

@objc(ChapterObject)
public class ChapterObject: NSManagedObject {
    func load(
        from chapter: AidokuRunner.Chapter,
        sourceId: String,
        mangaId: String,
        sourceOrder: Int? = nil
    ) {
        self.sourceId = sourceId
        self.mangaId = mangaId
        id = chapter.key
        title = chapter.title
        scanlator = chapter.scanlators.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }
        url = chapter.url?.absoluteString
        lang = chapter.language ?? ""
        self.chapter = chapter.chapterNumber != nil ? NSNumber(value: chapter.chapterNumber ?? -1) : nil
        volume = chapter.volumeNumber != nil ? NSNumber(value: chapter.volumeNumber ?? -1) : nil
        dateUploaded = chapter.dateUploaded
        thumbnail = chapter.thumbnail
        locked = chapter.locked
        if let sourceOrder {
            self.sourceOrder = Int16(sourceOrder)
        }
    }

    func toChapter() -> Chapter {
        Chapter(
            sourceId: sourceId,
            id: id,
            mangaId: mangaId,
            title: title,
            scanlator: scanlator,
            url: url,
            lang: lang,
            chapterNum: chapter == -1 ? nil : chapter?.floatValue,
            volumeNum: volume == -1 ? nil : volume?.floatValue,
            dateUploaded: dateUploaded,
            thumbnail: thumbnail,
            locked: locked,
            sourceOrder: Int(sourceOrder)
        )
    }

    func toNewChapter() -> AidokuRunner.Chapter {
        .init(
            key: id,
            title: title,
            chapterNumber: chapter == -1 ? nil : chapter?.floatValue,
            volumeNumber: volume == -1 ? nil : volume?.floatValue,
            dateUploaded: dateUploaded,
            scanlators: scanlator?.components(separatedBy: ", "),
            url: url.flatMap({ URL(string: $0) }),
            language: lang,
            thumbnail: thumbnail,
            locked: locked
        )
    }
}

extension ChapterObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChapterObject> {
        NSFetchRequest<ChapterObject>(entityName: "Chapter")
    }

    @NSManaged public var sourceId: String
    @NSManaged public var mangaId: String
    @NSManaged public var id: String
    @NSManaged public var title: String?
    @NSManaged public var scanlator: String?
    @NSManaged public var url: String?
    @NSManaged public var lang: String
    @NSManaged public var chapter: NSNumber?
    @NSManaged public var volume: NSNumber?
    @NSManaged public var dateUploaded: Date?
    @NSManaged public var thumbnail: String?
    @NSManaged public var locked: Bool
    @NSManaged public var sourceOrder: Int16

    @NSManaged public var manga: MangaObject?
    @NSManaged public var history: HistoryObject?
    @NSManaged public var mangaUpdate: MangaUpdateObject?
    @NSManaged public var fileInfo: LocalFileInfoObject?
}

extension ChapterObject: Identifiable {

}
