//
//  CoreDataManager+History.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import CoreData

extension CoreDataManager {

    /// Remove all history objects.
    func clearHistory(context: NSManagedObjectContext? = nil) {
        clear(request: HistoryObject.fetchRequest(), context: context)
    }

    func getHistory(sourceId: String, mangaId: String, chapterId: String, context: NSManagedObjectContext? = nil) -> HistoryObject? {
        let context = context ?? self.context
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@ AND chapterId == %@",
            sourceId, mangaId, chapterId
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }
}
