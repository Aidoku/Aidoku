//
//  CoreDataManager+Updates.swift
//  Aidoku
//
//  Created by axiel7 on 09/02/2024.
//

import CoreData

extension CoreDataManager {
    /// Remove all update objects.
    func clearUpdates(context: NSManagedObjectContext) {
        clear(request: MangaUpdateObject.fetchRequest(), context: context)
    }

    /// Gets all update objects.
    func getUpdates(context: NSManagedObjectContext) -> [MangaUpdateObject] {
        (try? context.fetch(MangaUpdateObject.fetchRequest())) ?? []
    }

    /// Get a particular manga update object.
    func getMangaUpdate(
        chapterId: ChapterIdentifier,
        context: NSManagedObjectContext
    ) -> MangaUpdateObject? {
        let request = MangaUpdateObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "chapterId == %@ AND mangaId == %@ AND sourceId == %@ ",
            chapterId.chapterKey, chapterId.mangaKey, chapterId.sourceKey
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Gets sorted manga update objects.
    func getRecentMangaUpdates(limit: Int, offset: Int, context: NSManagedObjectContext) -> [MangaUpdateObject] {
        let request = MangaUpdateObject.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = limit
        request.fetchOffset = offset
        return (try? context.fetch(request)) ?? []
    }

    func hasMangaUpdate(
        chapterId: ChapterIdentifier,
        context: NSManagedObjectContext
    ) -> Bool {
        getMangaUpdate(
            chapterId: chapterId,
            context: context
        ) != nil
    }

    /// Creates a new manga update object if does not exist
    func createMangaUpdate(
        mangaId: MangaIdentifier,
        chapterObject: ChapterObject,
        context: NSManagedObjectContext
    ) {
        if hasMangaUpdate(
            chapterId: .init(
                sourceKey: mangaId.sourceKey,
                mangaKey: mangaId.mangaKey,
                chapterKey: chapterObject.id
            ),
            context: context
        ) {
            return
        }
        let mangaUpdateObject = MangaUpdateObject(context: context)
        mangaUpdateObject.sourceId = mangaId.sourceKey
        mangaUpdateObject.mangaId = mangaId.mangaKey
        mangaUpdateObject.chapterId = chapterObject.id
        mangaUpdateObject.date = Date()
        mangaUpdateObject.chapter = chapterObject
    }

    /// Removes manga update objects by their composite keys
    func removeMangaUpdates(
        updates: [ChapterIdentifier],
        context: NSManagedObjectContext
    ) {
        let request = MangaUpdateObject.fetchRequest()

        var predicates: [NSPredicate] = []
        for update in updates {
            predicates.append(NSPredicate(
                format: "sourceId == %@ AND chapterId == %@ AND mangaId == %@",
                update.sourceKey, update.chapterKey, update.mangaKey
            ))
        }
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)

        if let fetchedUpdates = try? context.fetch(request) {
            for update in fetchedUpdates {
                context.delete(update)
            }
        }
    }

    /// Gets all unviewed updates of a manga
    func getUnviewedMangaUpdates(
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> [MangaUpdateObject] {
        let request = MangaUpdateObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ AND viewed == false",
            mangaId.mangaKey, mangaId.sourceKey
        )
        return (try? context.fetch(request)) ?? []
    }

    /// Mark all updates of a manga as viewed
    /// - Returns: The Manga Updates marked as read
    @discardableResult
    func setMangaUpdatesViewed(
        viewed: Bool = true,
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> [MangaUpdateObject] {
        let unviewedUpdates = getUnviewedMangaUpdates(mangaId: mangaId, context: context)
        if unviewedUpdates.isEmpty { return [] }
        for update in unviewedUpdates {
            update.viewed = viewed
        }
        do {
            try context.save()
            return unviewedUpdates
        } catch {
            LogManager.logger.error("CoreDataManager.setMangaUpdatesViewed: \(error.localizedDescription)")
            return []
        }
    }
}
