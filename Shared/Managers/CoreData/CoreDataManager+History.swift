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

    /// Gets all history objects.
    func getHistory(context: NSManagedObjectContext? = nil) -> [HistoryObject] {
        (try? (context ?? self.context).fetch(HistoryObject.fetchRequest())) ?? []
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
            format: "chapterId == %@ AND mangaId == %@ AND sourceId == %@",
            chapterId, mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Gets sorted history objects.
    func getRecentHistory(limit: Int, offset: Int, context: NSManagedObjectContext? = nil) -> [HistoryObject] {
        let request = HistoryObject.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "dateRead", ascending: false)]
        request.fetchLimit = limit
        request.fetchOffset = offset
        return (try? (context ?? self.context).fetch(request)) ?? []
    }

    /// Check if history exists for a chapter.
    func hasHistory(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        let context = context ?? self.context
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "chapterId == %@ AND mangaId == %@ AND sourceId == %@",
            chapterId, mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Check if history exists for a manga.
    func hasHistory(
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        let context = context ?? self.context
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Removes history for manga.
    func removeHistory(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) {
        let context = context ?? self.context
        let history = getHistoryForManga(sourceId: sourceId, mangaId: mangaId, context: context)
        for item in history {
            context.delete(item)
        }
    }

    /// Removes a HistoryObject in the background.
    func removeHistory(sourceId: String, mangaId: String, chapterId: String) async {
        await container.performBackgroundTask { context in
            do {
                if let object = self.getHistory(
                    sourceId: sourceId,
                    mangaId: mangaId,
                    chapterId: chapterId,
                    context: context
                ) {
                    context.delete(object)
                    try context.save()
                }
            } catch {
                LogManager.logger.error("CoreDataManager.removeHistory: \(error.localizedDescription)")
            }
        }
    }

    /// Removes history linked to the given chapters
    func removeHistory(chapters: [Chapter]) async {
        await container.performBackgroundTask { context in
            do {
                for chapter in chapters {
                    if let object = self.getHistory(
                        sourceId: chapter.sourceId,
                        mangaId: chapter.mangaId,
                        chapterId: chapter.id,
                        context: context
                    ) {
                        context.delete(object)
                    }
                }
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.removeHistory(chapters:): \(error.localizedDescription)")
            }
        }
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
            chapterId: chapterId,
            context: context
        ) {
            historyObject.chapter = chapterObject
        }
        return historyObject
    }

    /// Get history objects for a manga.
    func getHistoryForManga(
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> [HistoryObject] {
        let context = context ?? self.context
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId, sourceId
        )
        return (try? context.fetch(request)) ?? []
    }

    // format: [chapterId: (page (-1 if completed), read date)]
    func getReadingHistory(sourceId: String, mangaId: String) async -> [String: (page: Int, date: Int)] {
        await container.performBackgroundTask { context in
            let objects = self.getHistoryForManga(sourceId: sourceId, mangaId: mangaId, context: context)

            var needsSave = false
            var historyDict: [String: (page: Int, date: Int)] = [:]

            let inLibrary = self.hasLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context)

            for history in objects {
                // remove duplicate read history objects for the same chapter
                if historyDict[history.chapterId] != nil {
                    needsSave = true
                    context.delete(history)
                    continue
                }
                // link history to chapter if link is missing
                if inLibrary && history.chapter == nil {
                    if let chapter = self.getChapter(
                        sourceId: sourceId,
                        mangaId: mangaId,
                        chapterId: history.chapterId,
                        context: context
                    ) {
                        history.chapter = chapter
                        needsSave = true
                    }
                }
                historyDict[history.chapterId] = (
                    history.completed ? -1 : Int(history.progress),
                    Int(history.dateRead?.timeIntervalSince1970 ?? -1)
                )
            }

            if needsSave {
                try? context.save()
            }

            return historyDict
        }
    }

    /// Get current completion status and page progress for chapter
    func getProgress(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> (completed: Bool, progress: Int?) {
        let historyObject = getHistory(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId, context: context)
        return (historyObject?.completed ?? false, (historyObject?.progress).flatMap(Int.init))
    }

    /// Set page progress for a chapter and creates a history object if it doesn't already exist.
    func setProgress(
        _ progress: Int,
        sourceId: String,
        mangaId: String,
        chapterId: String,
        totalPages: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) {
        let historyObject = self.getOrCreateHistory(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterId: chapterId,
            context: context
        )
        historyObject.progress = Int16(progress)
        historyObject.dateRead = Date()
        if let totalPages = totalPages {
            historyObject.total = Int16(totalPages)
        }
    }

    /// Marks chapter as completed.
    func setCompleted(
        _ completed: Bool = true,
        progress: Int? = nil,
        date: Date = Date(),
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
            historyObject.dateRead = date
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.setCompleted: \(error.localizedDescription)")
            }
        }
    }

    /// Marks chapters as completed.
    func setCompleted(chapters: [Chapter], date: Date = Date(), context: NSManagedObjectContext? = nil) {
        for chapter in chapters {
            let historyObject = self.getOrCreateHistory(
                sourceId: chapter.sourceId,
                mangaId: chapter.mangaId,
                chapterId: chapter.id,
                context: context
            )
            guard !historyObject.completed else { continue }
            historyObject.completed = true
            historyObject.dateRead = date
        }
    }

    /// Marks chapters as completed.
    func setCompleted(chapters: [Chapter], date: Date = Date()) async {
        await container.performBackgroundTask { context in
            self.setCompleted(chapters: chapters, date: date, context: context)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.setCompleted(chapters:): \(error.localizedDescription)")
            }
        }
    }

    /// Check if a chapter has been completely read.
    func isCompleted(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        let context = context ?? self.context
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "chapterId == %@ AND mangaId == %@ AND sourceId == %@ AND completed == true",
            chapterId, mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }
}
