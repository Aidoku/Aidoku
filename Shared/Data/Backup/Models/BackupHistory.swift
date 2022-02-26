//
//  BackupHistory.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import CoreData

struct BackupHistory: Codable {
    var dateRead: Date
    var sourceId: String
    var chapterId: String
    var mangaId: String
    var progress: Int
    var completed: Bool

    init(historyObject: HistoryObject) {
        dateRead = historyObject.dateRead
        sourceId = historyObject.sourceId
        chapterId = historyObject.chapterId
        mangaId = historyObject.mangaId
        progress = Int(historyObject.progress)
        completed = historyObject.completed
    }

    func toObject(context: NSManagedObjectContext? = nil) -> HistoryObject {
        let obj: HistoryObject
        if let context = context {
            obj = HistoryObject(context: context)
        } else {
            obj = HistoryObject()
        }
        obj.dateRead = dateRead
        obj.sourceId = sourceId
        obj.chapterId = chapterId
        obj.mangaId = mangaId
        obj.progress = Int16(progress)
        obj.completed = completed
        return obj
    }
}
