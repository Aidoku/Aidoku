//
//  HistoryManager.swift
//  Aidoku
//
//  Created by Skitty on 1/9/23.
//

import CoreData

class HistoryManager {

    static let shared = HistoryManager()
}

extension HistoryManager {

    func setProgress(chapter: Chapter, progress: Int, totalPages: Int? = nil) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.setRead(sourceId: chapter.sourceId, mangaId: chapter.mangaId, context: context)
            CoreDataManager.shared.setProgress(
                progress,
                sourceId: chapter.sourceId,
                mangaId: chapter.mangaId,
                chapterId: chapter.id,
                totalPages: totalPages,
                context: context
            )
            do {
                try context.save()
            } catch {
                LogManager.logger.error("HistoryManager.setProgress: \(error.localizedDescription)")
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name("historySet"), object: (chapter, progress))
    }

    func addHistory(chapters: [Chapter], date: Date = Date()) async {
        // get unique set of manga ids from chapters array
        let mangaItems = Set(chapters.map { MangaInfo(mangaId: $0.mangaId, sourceId: $0.sourceId) })
        // mark each manga as read
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for item in mangaItems {
                CoreDataManager.shared.setRead(
                    sourceId: item.sourceId,
                    mangaId: item.mangaId,
                    context: context
                )
            }
            // mark chapters as read
            CoreDataManager.shared.setCompleted(chapters: chapters, date: date, context: context)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("HistoryManager.addHistory: \(error.localizedDescription)")
            }
        }
        // update tracker with chapter with largest number
        if let maxChapter = chapters.max(by: { $0.chapterNum ?? 0 < $1.chapterNum ?? 0 }) {
            await TrackerManager.shared.setCompleted(chapter: maxChapter)
        }
        NotificationCenter.default.post(name: NSNotification.Name("historyAdded"), object: chapters)
    }

    func removeHistory(chapters: [Chapter]) async {
        await CoreDataManager.shared.removeHistory(chapters: chapters)
        NotificationCenter.default.post(name: NSNotification.Name("historyRemoved"), object: chapters)
    }

    func removeHistory(manga: Manga) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removeHistory(sourceId: manga.sourceId, mangaId: manga.id, context: context)
            try? context.save()
        }
        NotificationCenter.default.post(name: NSNotification.Name("historyRemoved"), object: manga)
    }
}
