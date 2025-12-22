//
//  BackupReadingSession.swift
//  Aidoku
//
//  Created by Skitty on 12/21/25.
//

import CoreData

struct BackupReadingSession: Codable, Hashable {
    var pagesRead: Int
    var startDate: Date
    var endDate: Date
    var sourceId: String
    var mangaId: String
    var chapterId: String

    init?(_ object: ReadingSessionObject) {
        guard
            let history = object.history,
            let startDate = object.startDate,
            let endDate = object.endDate
        else {
            return nil
        }
        pagesRead = Int(object.pagesRead)
        self.startDate = startDate
        self.endDate = endDate
        sourceId = history.sourceId
        chapterId = history.chapterId
        mangaId = history.mangaId
    }

    func toObject(context: NSManagedObjectContext? = nil) -> ReadingSessionObject {
        let object: ReadingSessionObject
        if let context {
            object = ReadingSessionObject(context: context)
        } else {
            object = ReadingSessionObject()
        }
        object.pagesRead = Int16(pagesRead)
        object.startDate = startDate
        object.endDate = endDate
        return object
    }
}
