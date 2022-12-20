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

    /// Check if history exists for a chapter
    func hasHistory(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        getHistory(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId, context: context) != nil
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

    func getOrCreateHistory(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> HistoryObject {
        if let historyObject = getHistory(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterId: chapterId,
            context: context
        ) {
            return historyObject
        }
        let historyObject = HistoryObject(context: context ?? self.context)
        historyObject.sourceId = sourceId
        historyObject.mangaId = mangaId
        historyObject.chapterId = chapterId
        if let chapterObject = self.getChapter(
            sourceId: sourceId,
            mangaId: mangaId,
            id: chapterId,
            context: context
        ) {
            historyObject.chapter = chapterObject
        }
        return historyObject
    }

    /// Get current page progress for chapter, returns -1 if not started.
    func getProgress(sourceId: String, mangaId: String, chapterId: String, context: NSManagedObjectContext? = nil) -> Int {
        let historyObject = getHistory(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId, context: context)
        return Int(historyObject?.progress ?? -1)
    }

    /// Set page progress for a chapter and creates a history object if it doesn't already exist.
    func setProgress(_ progress: Int, sourceId: String, mangaId: String, chapterId: String) async {
        await container.performBackgroundTask { context in
            let historyObject = self.getOrCreateHistory(
                sourceId: sourceId,
                mangaId: mangaId,
                chapterId: chapterId,
                context: context
            )
            historyObject.progress = Int16(progress)
            historyObject.dateRead = Date()
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.setProgress: \(error.localizedDescription)")
            }
        }
    }

    func setCompleted(
        _ completed: Bool = true,
        progress: Int? = nil,
        sourceId: String,
        mangaId: String,
        chapterId: String
    ) async {
        await container.performBackgroundTask { context in
            let historyObject = self.getOrCreateHistory(
                sourceId: sourceId,
                mangaId: mangaId,
                chapterId: chapterId,
                context: context
            )
            guard historyObject.completed != completed else { return }
            historyObject.completed = completed
            if let progress = progress {
                historyObject.progress = Int16(progress)
            }
            historyObject.dateRead = Date()
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.setCompleted: \(error.localizedDescription)")
            }
        }
    }
}
