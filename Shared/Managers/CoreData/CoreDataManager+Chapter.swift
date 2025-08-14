//
//  CoreDataManager+Chapter.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/13/22.
//

import CoreData
import AidokuRunner

extension CoreDataManager {

    /// Remove all chapter objects.
    func clearChapters(context: NSManagedObjectContext? = nil) {
        clear(request: ChapterObject.fetchRequest(), context: context)
    }

    /// Gets all chapter objects.
    func getChapters(context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        (try? (context ?? self.context).fetch(ChapterObject.fetchRequest())) ?? []
    }

    /// Gets all chapter objects for a source.
    func getChapters(sourceId: String, context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@", sourceId)
        return (try? context.fetch(request)) ?? []
    }

    /// Get a particular chapter object.
    func getChapter(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> ChapterObject? {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND mangaId == %@ AND sourceId == %@ ",
            chapterId, mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get the chapter objects for a manga.
    func getChapters(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId, sourceId
        )
        request.sortDescriptors = [NSSortDescriptor(key: "sourceOrder", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func getChapters(sourceId: String, mangaId: String) async -> [Chapter] {
        await container.performBackgroundTask { context in
            let objects = self.getChapters(sourceId: sourceId, mangaId: mangaId, context: context)
            return objects.map { $0.toChapter() }
        }
    }

    /// Create a chapter object.
    @discardableResult
    func createChapter(
        _ chapter: AidokuRunner.Chapter,
        sourceId: String,
        mangaId: String,
        sourceOrder: Int,
        mangaObject: MangaObject? = nil,
        context: NSManagedObjectContext? = nil
    ) -> ChapterObject? {
        let context = context ?? self.context
        guard let mangaObject = mangaObject ?? getManga(
            sourceId: sourceId,
            mangaId: mangaId,
            context: context
        ) else {
            return nil
        }
        let object = ChapterObject(context: context)
        object.load(
            from: chapter,
            sourceId: sourceId,
            mangaId: mangaId,
            sourceOrder: sourceOrder
        )
        object.manga = mangaObject
        object.history = getHistory(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterId: chapter.id,
            context: context
        )
        return object
    }

    /// Check if a chapter exists in the data store.
    func hasChapter(sourceId: String, mangaId: String, chapterId: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND mangaId == %@ AND sourceId == %@ ",
            chapterId, mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Removes chapters for manga.
    func removeChapters(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) {
        let context = context ?? self.context
        let chapters = getChapters(sourceId: sourceId, mangaId: mangaId, context: context)
        for chapter in chapters where chapter.fileInfo == nil {
            context.delete(chapter)
        }
    }

    /// Set a list of chapters for a manga.
    /// - Returns: New created chapters
    @discardableResult
    func setChapters(
        _ chapters: [AidokuRunner.Chapter],
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> [ChapterObject] {
        let context = context ?? self.context
        var newChapters = Array(chapters.enumerated())

        guard let manga = self.getManga(sourceId: sourceId, mangaId: mangaId, context: context) else { return [] }

        // update existing chapter objects
        let chapterObjects = getChapters(sourceId: sourceId, mangaId: mangaId, context: context)
        var chapterIds: Set<String> = Set()
        for object in chapterObjects {
            if let newChapter = newChapters.first(where: { $0.element.id == object.id }) {
                let (inserted, _) = chapterIds.insert(object.id)
                if !inserted {
                    context.delete(object) // remove duplicates
                }
                object.load(
                    from: newChapter.element,
                    sourceId: sourceId,
                    mangaId: mangaId,
                    sourceOrder: newChapter.offset
                )
                object.manga = manga
                newChapters.removeAll { $0.element.id == object.id }
            } else {
                context.delete(object)
            }
        }

        // create new chapter objects
        var newChaptersCreated = [ChapterObject]()
        for (offset, chapter) in newChapters where !hasChapter(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterId: chapter.id,
            context: context
        ) {
            if let chapterObject = createChapter(
                chapter,
                sourceId: sourceId,
                mangaId: mangaId,
                sourceOrder: offset,
                mangaObject: manga,
                context: context
            ) {
                newChaptersCreated.append(chapterObject)
            }
        }
        return newChaptersCreated
    }

    /// Get the number of unread chapters for a manga.
    func unreadCount(
        sourceId: String,
        mangaId: String,
        lang: String?,
        scanlators: [String]?,
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let scanlators: [String]? = if scanlators?.isEmpty ?? true {
            nil
        } else {
            scanlators
        }
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        if let scanlators, let lang {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND lang == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                sourceId, mangaId, lang, scanlators, scanlators
            )
        } else if let scanlators {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                sourceId, mangaId, scanlators, scanlators
            )
        } else if let lang {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND lang == %@
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                sourceId, mangaId, lang
            )
        } else {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                sourceId, mangaId
            )
        }
        return (try? context.count(for: request)) ?? 0
    }

    /// Get the number of read chapters for a manga.
    func readCount(
        sourceId: String,
        mangaId: String,
        lang: String?,
        scanlators: [String]?,
        context: NSManagedObjectContext? = nil
    ) -> Int {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        if let scanlators, let lang {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND lang == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND history.completed == true
                """,
                sourceId, mangaId, lang, scanlators, scanlators
            )
        } else if let scanlators {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND history.completed == true
                """,
                sourceId, mangaId, scanlators, scanlators
            )
        } else if let lang {
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND history != nil AND lang == %@ AND history.completed == true",
                sourceId, mangaId, lang
            )
        } else {
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND history != nil AND history.completed == true",
                sourceId, mangaId
            )
        }
        return (try? context.count(for: request)) ?? 0
    }
}
