//
//  BackupVocabEntry.swift
//  Aidoku
//
//  Created by skitty on 7/25/26.
//

import CoreData

struct BackupVocabEntry: Codable, Hashable {
    var sourceId: String
    var mangaId: String
    var chapterId: String
    var word: String
    var reading: String?
    var sentence: String?
    var clozeOffset: Int?
    var clozeText: String?
    var page: Int
    var createdDate: Date

    var identifier: ChapterIdentifier {
        .init(sourceKey: sourceId, mangaKey: mangaId, chapterKey: chapterId)
    }

    init(entry: VocabEntry) {
        self.sourceId = entry.chapterId.sourceKey
        self.mangaId = entry.chapterId.mangaKey
        self.chapterId = entry.chapterId.chapterKey
        self.word = entry.word
        self.reading = entry.reading
        self.sentence = entry.sentence
        self.clozeOffset = entry.clozeOffset
        self.clozeText = entry.clozeText
        self.page = entry.page ?? 0
        self.createdDate = entry.createdDate
    }

    init?(_ object: VocabObject) {
        guard
            let sourceId = object.sourceId,
            let mangaId = object.mangaId,
            let chapterId = object.chapterId,
            let word = object.word,
            let createdDate = object.createdDate
        else {
            return nil
        }
        self.sourceId = sourceId
        self.mangaId = mangaId
        self.chapterId = chapterId
        self.word = word
        self.reading = object.reading
        self.sentence = object.sentence
        self.clozeOffset = Int(object.clozeOffset)
        self.clozeText = object.clozeText
        self.page = Int(object.page)
        self.createdDate = createdDate
    }

    func toObject(context: NSManagedObjectContext? = nil) -> VocabObject {
        let object: VocabObject
        if let context {
            object = VocabObject(context: context)
        } else {
            object = VocabObject()
        }
        object.sourceId = sourceId
        object.mangaId = mangaId
        object.chapterId = chapterId
        object.word = word
        object.reading = reading
        object.sentence = sentence
        object.clozeOffset = clozeOffset.map(Int16.init) ?? 0
        object.clozeText = clozeText
        object.page = Int16(page)
        object.createdDate = createdDate
        return object
    }
}
