//
//  HistoryManager.swift
//  Aidoku
//
//  Created by Skitty on 1/9/23.
//

import CoreData
import AidokuRunner

final class HistoryManager: Sendable {
    static let shared = HistoryManager()
}

extension HistoryManager {
    func setProgress(chapter: Chapter, progress: Int, totalPages: Int? = nil, completed: Bool) async {
        let identifier = chapter.identifier
        let chapter = chapter.toNew()
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.setRead(sourceId: identifier.sourceKey, mangaId: identifier.mangaKey, context: context)
            CoreDataManager.shared.setProgress(
                progress,
                sourceId: identifier.sourceKey,
                mangaId: identifier.mangaKey,
                chapterId: identifier.chapterKey,
                totalPages: totalPages,
                context: context
            )
            do {
                try context.save()
            } catch {
                LogManager.logger.error("HistoryManager.setProgress: \(error)")
            }
        }
        if !completed && UserDefaults.standard.bool(forKey: "Tracking.updateAfterReading") {
            // update page trackers with progress
            await TrackerManager.shared.setProgress(
                sourceKey: identifier.sourceKey,
                mangaKey: identifier.mangaKey,
                chapter: chapter,
                progress: .init(completed: false, page: progress)
            )
        }
        NotificationCenter.default.post(name: .historySet, object: (chapter, progress))
    }

    struct ReadingSessionData {
        let startDate: Date
        let endDate: Date
        let pagesRead: Int
    }

    func addSession(chapterIdentifier: ChapterIdentifier, data: ReadingSessionData) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.createSession(
                chapterIdentifier: chapterIdentifier,
                data: data,
                context: context
            )
            do {
                try context.save()
            } catch {
                LogManager.logger.error("HistoryManager.addSession: \(error)")
            }
        }
    }

    func addHistory(
        sourceId: String,
        mangaId: String,
        chapters: [AidokuRunner.Chapter],
        date: Date = Date(),
        skipTracker: Tracker? = nil
    ) async {
        // mark each manga as read
        let success = await CoreDataManager.shared.container.performBackgroundTask { context in
            // mark chapters as read
            let success = CoreDataManager.shared.setCompleted(
                sourceId: sourceId,
                mangaId: mangaId,
                chapterIds: chapters.map { $0.key },
                date: date,
                context: context
            )
            if success {
                CoreDataManager.shared.setRead(
                    sourceId: sourceId,
                    mangaId: mangaId,
                    date: date,
                    context: context
                )
                do {
                    try context.save()
                } catch {
                    LogManager.logger.error("HistoryManager.addHistory: \(error.localizedDescription)")
                }
            }
            return success
        }
        guard success else { return }
        if UserDefaults.standard.bool(forKey: "Tracking.updateAfterReading") {
            // update tracker with chapter with largest number
            if let maxChapter = chapters.max(by: { $0.chapterNumber ?? 0 < $1.chapterNumber ?? 0 }) {
                await TrackerManager.shared.setCompleted(
                    chapter: maxChapter.toOld(
                        sourceId: sourceId,
                        mangaId: mangaId
                    ),
                    skipTracker: skipTracker
                )
            }
            await TrackerManager.shared.setProgress(
                sourceKey: sourceId,
                mangaKey: mangaId,
                chapters: chapters,
                progress: .init(completed: true, page: 0)
            )
        }
        NotificationCenter.default.post(
            name: .historyAdded,
            object: chapters.map { $0.toOld(sourceId: sourceId, mangaId: mangaId) }
        )
    }

    func removeHistory(
        sourceId: String,
        mangaId: String,
        chapterIds: [String]
    ) async {
        await CoreDataManager.shared.removeHistory(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterIds: chapterIds
        )
        if UserDefaults.standard.bool(forKey: "Tracking.updateAfterReading") {
            await TrackerManager.shared.setProgress(
                sourceKey: sourceId,
                mangaKey: mangaId,
                chapters: chapterIds.map { .init(key: $0) },
                progress: .init(completed: false, page: 0)
            )
        }
        NotificationCenter.default.post(
            name: .historyRemoved,
            object: chapterIds.map {
                Chapter(
                    sourceId: sourceId,
                    id: $0,
                    mangaId: mangaId,
                    title: "",
                    sourceOrder: -1
                )
            }
        )
    }

    func removeHistory(sourceId: String, mangaId: String) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removeHistory(sourceId: sourceId, mangaId: mangaId, context: context)
            try? context.save()
        }
        if UserDefaults.standard.bool(forKey: "Tracking.updateAfterReading") {
            let chapters = await CoreDataManager.shared.getChapters(sourceId: sourceId, mangaId: mangaId)
            await TrackerManager.shared.setProgress(
                sourceKey: sourceId,
                mangaKey: mangaId,
                chapters: chapters.map { $0.toNew() },
                progress: .init(completed: false, page: 0)
            )
        }
        NotificationCenter.default.post(name: .historyRemoved, object: Manga(sourceId: sourceId, id: mangaId))
    }
}
