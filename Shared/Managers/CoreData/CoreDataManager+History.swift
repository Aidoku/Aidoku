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

    /// Get a particular history object.
    func getHistory(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> HistoryObject? {
        let context = context ?? self.context
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@ AND chapterId == %@",
            sourceId, mangaId, chapterId
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get current page progress for chapter, returns -1 if not started.
    func getProgress(sourceId: String, mangaId: String, chapterId: String, context: NSManagedObjectContext? = nil) -> Int {
        let historyObject = getHistory(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId, context: context)
        return Int(historyObject?.progress ?? -1)
    }

    /// Set page progress for a chapter.
    func setProgress(_ progress: Int, sourceId: String, mangaId: String, chapterId: String) async {
        await container.performBackgroundTask { context in
            guard let historyObject = self.getHistory(
                sourceId: sourceId,
                mangaId: mangaId,
                chapterId: chapterId,
                context: context
            ) else { return } // TODO: create if doesn't exist?
            historyObject.progress = Int16(progress)
            historyObject.dateRead = Date()
            do {
                try context.save()
            } catch {
                LogManager.logger.error("setProgress: \(error.localizedDescription)")
            }
        }
    }
}
