//
//  ChapterObject.swift
//  Aidoku
//
//  Created by Skitty on 1/27/22.
//

import Foundation
import CoreData


@objc(ChapterObject)
public class ChapterObject: NSManagedObject {
    func load(from chapter: Chapter) {
        sourceId = chapter.sourceId
        mangaId = chapter.mangaId
        id = chapter.id
        title = chapter.title
        scanlator = chapter.scanlator
        lang = chapter.lang
        self.chapter = chapter.chapterNum != nil ? NSNumber(value: chapter.chapterNum ?? -1) : nil
        volume = chapter.volumeNum != nil ? NSNumber(value: chapter.volumeNum ?? -1) : nil
        dateUploaded = chapter.dateUploaded
        sourceOrder = Int16(chapter.sourceOrder)
    }
    func toChapter() -> Chapter {
        Chapter(
            sourceId: sourceId,
            id: id,
            mangaId: mangaId,
            title: title,
            scanlator: scanlator,
            lang: lang,
            chapterNum: chapter?.floatValue,
            volumeNum: volume?.floatValue,
            dateUploaded: dateUploaded,
            sourceOrder: Int(sourceOrder)
        )
    }
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        progress = 0
        read = false
    }
}

extension ChapterObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChapterObject> {
        return NSFetchRequest<ChapterObject>(entityName: "Chapter")
    }

    @NSManaged public var sourceId: String
    @NSManaged public var mangaId: String
    @NSManaged public var id: String
    @NSManaged public var title: String?
    @NSManaged public var scanlator: String?
    @NSManaged public var lang: String
    @NSManaged public var chapter: NSNumber?
    @NSManaged public var volume: NSNumber?
    @NSManaged public var progress: Int16
    @NSManaged public var read: Bool
    @NSManaged public var dateUploaded: Date?
    @NSManaged public var sourceOrder: Int16
    
    @NSManaged public var manga: MangaObject?
    @NSManaged public var history: HistoryObject?
    
}

extension ChapterObject : Identifiable {

}
