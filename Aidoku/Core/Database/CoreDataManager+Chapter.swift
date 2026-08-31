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
    func clearChapters(context: NSManagedObjectContext) {
        clear(request: ChapterObject.fetchRequest(), context: context)
    }

    /// Gets all chapter objects.
    func getChapters(context: NSManagedObjectContext) -> [ChapterObject] {
        (try? context.fetch(ChapterObject.fetchRequest())) ?? []
    }

    /// Gets all chapter objects for a source.
    func getChapters(sourceKey: String, context: NSManagedObjectContext) -> [ChapterObject] {
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@", sourceKey)
        return (try? context.fetch(request)) ?? []
    }

    /// Get a particular chapter object.
    func getChapter(chapterId: ChapterIdentifier, context: NSManagedObjectContext) -> ChapterObject? {
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND mangaId == %@ AND sourceId == %@ ",
            chapterId.chapterKey, chapterId.mangaKey, chapterId.sourceKey
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get the chapter objects for a manga.
    func getChapters(mangaId: MangaIdentifier, context: NSManagedObjectContext) -> [ChapterObject] {
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId.mangaKey, mangaId.sourceKey
        )
        request.sortDescriptors = [NSSortDescriptor(key: "sourceOrder", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func getChapters(mangaId: MangaIdentifier) async -> [Chapter] {
        await container.performBackgroundTask { context in
            let objects = self.getChapters(mangaId: mangaId, context: context)
            return objects.map { $0.toChapter() }
        }
    }

    /// Create a chapter object.
    @discardableResult
    func createChapter(
        _ chapter: AidokuRunner.Chapter,
        mangaId: MangaIdentifier,
        sourceOrder: Int,
        mangaObject: MangaObject? = nil,
        context: NSManagedObjectContext
    ) -> ChapterObject? {
        guard let mangaObject = mangaObject ?? getManga(
            mangaId: mangaId,
            context: context
        ) else {
            return nil
        }
        let object = ChapterObject(context: context)
        object.load(
            from: chapter,
            mangaId: mangaId,
            sourceOrder: sourceOrder
        )
        object.manga = mangaObject
        object.history = getHistory(
            chapterId: .init(
                sourceKey: mangaId.sourceKey,
                mangaKey: mangaId.mangaKey,
                chapterKey: chapter.id
            ),
            context: context
        )
        return object
    }

    /// Check if a chapter exists in the data store.
    func hasChapter(chapterId: ChapterIdentifier, context: NSManagedObjectContext) -> Bool {
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND mangaId == %@ AND sourceId == %@ ",
            chapterId.chapterKey, chapterId.mangaKey, chapterId.sourceKey
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Removes chapters for manga.
    func removeChapters(mangaId: MangaIdentifier, context: NSManagedObjectContext) {
        let chapters = getChapters(mangaId: mangaId, context: context)
        for chapter in chapters where chapter.fileInfo == nil {
            context.delete(chapter)
        }
    }

    /// Set a list of chapters for a manga.
    /// - Returns: New created chapters
    @discardableResult
    func setChapters(
        _ chapters: [AidokuRunner.Chapter],
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> [ChapterObject] {
        guard let manga = getManga(mangaId: mangaId, context: context) else { return [] }

        var newChapters = Array(chapters.enumerated())

        // update existing chapter objects
        let chapterObjects = getChapters(mangaId: mangaId, context: context)
        var chapterIds: Set<String> = Set()
        for object in chapterObjects {
            if let newChapter = newChapters.first(where: { $0.element.id == object.id }) {
                let (inserted, _) = chapterIds.insert(object.id)
                if !inserted {
                    context.delete(object) // remove duplicates
                }
                let becameUnlocked = object.locked && !newChapter.element.locked
                if becameUnlocked {
                    context.delete(object) // treat unlocked chapters as new ones
                } else {
                    object.load(
                        from: newChapter.element,
                        mangaId: mangaId,
                        sourceOrder: newChapter.offset
                    )
                    object.manga = manga
                    newChapters.removeAll { $0.element.id == object.id }
                }
            } else {
                context.delete(object)
            }
        }

        // create new chapter objects
        var newChaptersCreated = [ChapterObject]()
        for (offset, chapter) in newChapters where !hasChapter(
            chapterId: .init(
                sourceKey: mangaId.sourceKey,
                mangaKey: mangaId.mangaKey,
                chapterKey: chapter.id
            ),
            context: context
        ) {
            if let chapterObject = createChapter(
                chapter,
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
        mangaId: MangaIdentifier,
        lang: String?,
        scanlators: [String]?,
        context: NSManagedObjectContext
    ) -> Int {
        let scanlators: [String]? = if scanlators?.isEmpty ?? true {
            nil
        } else {
            scanlators
        }
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
                mangaId.sourceKey, mangaId.mangaKey, lang, scanlators, scanlators
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
                mangaId.sourceKey, mangaId.mangaKey, scanlators, scanlators
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
                mangaId.sourceKey, mangaId.mangaKey, lang
            )
        } else {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND (history == nil OR history.completed == false)
                AND locked == false
                """,
                mangaId.sourceKey, mangaId.mangaKey
            )
        }
        return (try? context.count(for: request)) ?? 0
    }

    /// Get the number of read chapters for a manga.
    func readCount(
        mangaId: MangaIdentifier,
        lang: String?,
        scanlators: [String]?,
        context: NSManagedObjectContext
    ) -> Int {
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
                mangaId.sourceKey, mangaId.mangaKey, lang, scanlators, scanlators
            )
        } else if let scanlators {
            request.predicate = NSPredicate(
                format: """
                sourceId == %@
                AND mangaId == %@
                AND ((scanlator IN %@) OR (scanlator == nil AND %@ CONTAINS ''))
                AND history.completed == true
                """,
                mangaId.sourceKey, mangaId.mangaKey, scanlators, scanlators
            )
        } else if let lang {
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND history != nil AND lang == %@ AND history.completed == true",
                mangaId.sourceKey, mangaId.mangaKey, lang
            )
        } else {
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND history != nil AND history.completed == true",
                mangaId.sourceKey, mangaId.mangaKey
            )
        }
        return (try? context.count(for: request)) ?? 0
    }
}
