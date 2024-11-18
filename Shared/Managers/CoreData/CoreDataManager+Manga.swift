//
//  CoreDataManager+Manga.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/9/22.
//

import CoreData

extension CoreDataManager {

    /// Remove all history objects.
    func clearManga(context: NSManagedObjectContext? = nil) {
        clear(request: MangaObject.fetchRequest(), context: context)
    }

    /// Gets all manga objects.
    func getManga(context: NSManagedObjectContext? = nil) -> [MangaObject] {
        (try? (context ?? self.context).fetch(MangaObject.fetchRequest())) ?? []
    }

    /// Get a particular manga object.
    func getManga(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> MangaObject? {
        let context = context ?? self.context
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@ AND id == %@", sourceId, mangaId)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Create a manga object.
    @discardableResult
    func createManga(_ manga: Manga, context: NSManagedObjectContext? = nil) -> MangaObject {
        let context = context ?? self.context
        let object = MangaObject(context: context)
        object.load(from: manga)
        return object
    }

    func getOrCreateManga(_ manga: Manga, context: NSManagedObjectContext? = nil) -> MangaObject {
        if let mangaObject = getManga(sourceId: manga.sourceId, mangaId: manga.id, context: context) {
            return mangaObject
        }
        return createManga(manga, context: context)
    }

    /// Check if a manga object exists.
    func hasManga(
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        let context = context ?? self.context
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND sourceId == %@", mangaId, sourceId)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Removes a manga object.
    func removeManga(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) {
        guard let object = getManga(sourceId: sourceId, mangaId: mangaId, context: context) else { return }
        (context ?? self.context).delete(object)
    }

    func updateMangaDetails(manga: Manga) async {
        await container.performBackgroundTask { context in
            guard let object = self.getManga(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                context: context
            ) else { return }
            object.load(from: manga)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.updateMangaDetails: \(error.localizedDescription)")
            }
        }
    }

    func getMangaSourceReadingMode(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> Int {
        let context = context ?? self.context
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND sourceId == %@", mangaId, sourceId)
        request.fetchLimit = 1
        request.propertiesToFetch = ["viewer"]
        return Int((try? context.fetch(request))?.first?.viewer ?? -1)
    }

    struct ChapterFilters {
        let flags: Int
        let language: String?
        let scanlators: [String]?
    }

    func getMangaChapterFilters(
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> ChapterFilters {
        let context = context ?? self.context
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND sourceId == %@", mangaId, sourceId)
        request.fetchLimit = 1
        request.propertiesToFetch = ["chapterFlags", "langFilter", "scanlatorFilter"]
        let object = (try? context.fetch(request))?.first
        return ChapterFilters(
            flags: Int(object?.chapterFlags ?? 0),
            language: object?.langFilter,
            scanlators: object?.scanlatorFilter
        )
    }
}
