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
    func setProgress(
        chapter: Chapter,
        progress: Int,
        totalPages: Int? = nil,
        scrollPosition: Double? = nil,
        completed: Bool
    ) async {
        let chapterId = chapter.identifier
        let mangaId = chapterId.mangaIdentifier
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.setRead(mangaId: mangaId, context: context)
            CoreDataManager.shared.setProgress(
                progress,
                chapterId: chapterId,
                totalPages: totalPages,
                scrollPosition: scrollPosition,
                context: context
            )
            do {
                try context.save()
            } catch {
                LogManager.logger.error("HistoryManager.setProgress: \(error)")
            }
        }
        NotificationCenter.default.post(name: .historySet, object: (chapter, progress))
        if !completed {
            Task {
                // update page trackers with progress
                await TrackerManager.shared.setProgress(
                    mangaId: mangaId,
                    chapter: chapter.toNew(),
                    progress: .init(completed: false, page: progress)
                )
            }
        }
    }

    struct ReadingSessionData {
        let startDate: Date
        let endDate: Date
        let pagesRead: Int
    }

    func addSession(chapterId: ChapterIdentifier, data: ReadingSessionData) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.createSession(
                chapterId: chapterId,
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
        mangaId: MangaIdentifier,
        chapters: [AidokuRunner.Chapter],
        date: Date = Date(),
        skipTracker: Tracker? = nil
    ) async {
        // mark each manga as read
        let success = await CoreDataManager.shared.container.performBackgroundTask { context in
            // mark chapters as read
            let success = CoreDataManager.shared.setCompleted(
                chapterIds: chapters.map {
                    .init(sourceKey: mangaId.sourceKey, mangaKey: mangaId.mangaKey, chapterKey: $0.key)
                },
                date: date,
                context: context
            )
            if success {
                CoreDataManager.shared.setRead(
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
        NotificationCenter.default.post(
            name: .historyAdded,
            object: chapters.map { $0.toOld(mangaId: mangaId) }
        )
        Task {
            if UserDefaults.standard.bool(forKey: "Tracking.updateAfterReading") {
                // update tracker with chapter with largest number
                if let maxChapter = chapters.max(by: { $0.chapterNumber ?? 0 < $1.chapterNumber ?? 0 }) {
                    await TrackerManager.shared.setCompleted(
                        chapter: maxChapter.toOld(mangaId: mangaId),
                        skipTracker: skipTracker
                    )
                }
            }

            await TrackerManager.shared.setProgress(
                mangaId: mangaId,
                chapters: chapters,
                progress: .init(completed: true, page: 0)
            )
        }
    }

    func removeHistory(chapterIds: [ChapterIdentifier]) async {
        guard !chapterIds.isEmpty else { return }
        await CoreDataManager.shared.removeHistory(chapterIds: chapterIds)
        NotificationCenter.default.post(
            name: .historyRemoved,
            object: chapterIds.map {
                Chapter(
                    sourceId: $0.sourceKey,
                    id: $0.chapterKey,
                    mangaId: $0.mangaKey,
                    title: "",
                    sourceOrder: -1
                )
            }
        )
        Task {
            await TrackerManager.shared.setProgress(
                mangaId: chapterIds[0].mangaIdentifier,
                chapters: chapterIds.map { .init(key: $0.chapterKey) },
                progress: .init(completed: false, page: 0)
            )
        }
    }

    func removeHistory(mangaId: MangaIdentifier) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removeHistory(mangaId: mangaId, context: context)
            try? context.save()
        }
        NotificationCenter.default.post(name: .historyRemoved, object: Manga(sourceId: mangaId.sourceKey, id: mangaId.mangaKey))
        Task {
            let chapters = await CoreDataManager.shared.getChapters(mangaId: mangaId)
            await TrackerManager.shared.setProgress(
                mangaId: mangaId,
                chapters: chapters.map { $0.toNew() },
                progress: .init(completed: false, page: 0)
            )
        }
    }
}
