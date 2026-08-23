//
//  BackupUpdate.swift
//  Aidoku
//
//  Created by Skitty on 12/21/25.
//

import CoreData

struct BackupUpdate: Codable, Hashable {
    var date: Date
    var viewed: Bool
    var sourceId: String
    var mangaId: String
    var chapterId: String

    init?(_ object: MangaUpdateObject) {
        guard
            let sourceId = object.sourceId,
            let mangaId = object.mangaId,
            let chapterId = object.chapterId
        else {
            return nil
        }
        date = object.date ?? Date.distantPast
        viewed = object.viewed
        self.sourceId = sourceId
        self.mangaId = mangaId
        self.chapterId = chapterId
    }

    func toObject(context: NSManagedObjectContext? = nil) -> MangaUpdateObject {
        let object: MangaUpdateObject
        if let context {
            object = MangaUpdateObject(context: context)
        } else {
            object = MangaUpdateObject()
        }
        object.date = date
        object.viewed = viewed
        object.sourceId = sourceId
        object.mangaId = mangaId
        object.chapterId = chapterId
        return object
    }
}
