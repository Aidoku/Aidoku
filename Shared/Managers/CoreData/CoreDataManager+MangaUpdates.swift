//
//  CoreDataManager+Updates.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 09/02/2024.
//

import CoreData

extension CoreDataManager {

    /// Remove all manga update objects.
    func clearMangaUpdates(context: NSManagedObjectContext? = nil) {
        clear(request: MangaUpdateObject.fetchRequest(), context: context)
    }

    /// Get a particular manga update object.
    func getMangaUpdate(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> MangaUpdateObject? {
        let context = context ?? self.context
        let request = MangaUpdateObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "chapterId == %@ AND mangaId == %@ AND sourceId == %@ ",
            chapterId, mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Gets sorted manga update objects.
    func getRecentMangaUpdates(limit: Int, offset: Int, context: NSManagedObjectContext? = nil) -> [MangaUpdateObject] {
        let request = MangaUpdateObject.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = limit
        request.fetchOffset = offset
        return (try? (context ?? self.context).fetch(request)) ?? []
    }

    func hasMangaUpdate(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        getMangaUpdate(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterId: chapterId,
            context: context
        ) != nil
    }

    /// Creates a new manga update object if does not exist
    func createMangaUpdate(
        sourceId: String,
        mangaId: String,
        chapterObject: ChapterObject,
        context: NSManagedObjectContext? = nil
    ) {
        if hasMangaUpdate(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterId: chapterObject.id,
            context: context
        ) {
            return
        }
        let mangaUpdateObject = MangaUpdateObject(context: context ?? self.context)
        mangaUpdateObject.sourceId = sourceId
        mangaUpdateObject.mangaId = mangaId
        mangaUpdateObject.chapterId = chapterObject.id
        mangaUpdateObject.date = Date()
        mangaUpdateObject.chapter = chapterObject
    }

    /// Gets all unviewed updates of a manga
    func getUnviewedMangaUpdates(
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> [MangaUpdateObject] {
        let context = context ?? self.context
        let request = MangaUpdateObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ AND viewed == false",
            mangaId, sourceId
        )
        return (try? context.fetch(request)) ?? []
    }

    /// Mark all updates of a manga as viewed
    /// - Returns: The Manga Updates marked as read
    @discardableResult
    func setMangaUpdatesViewed(
        viewed: Bool = true,
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> [MangaUpdateObject] {
        let context = context ?? self.context
        let unviewedUpdates = getUnviewedMangaUpdates(sourceId: sourceId, mangaId: mangaId, context: context)
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
