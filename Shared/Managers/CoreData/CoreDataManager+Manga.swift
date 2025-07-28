//
//  CoreDataManager+Manga.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/9/22.
//

import CoreData
import AidokuRunner

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
    func getManga(
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> MangaObject? {
        let context = context ?? self.context
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@ AND id == %@", sourceId, mangaId)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Create a manga object.
    @discardableResult
    func createManga(
        _ manga: AidokuRunner.Manga,
        sourceId: String,
        context: NSManagedObjectContext? = nil
    ) -> MangaObject {
        let context = context ?? self.context
        let object = MangaObject(context: context)
        object.load(from: manga, sourceId: sourceId)
        return object
    }

    func getOrCreateManga(
        _ manga: AidokuRunner.Manga,
        sourceId: String,
        context: NSManagedObjectContext? = nil
    ) -> MangaObject {
        if let mangaObject = getManga(sourceId: sourceId, mangaId: manga.key, context: context) {
            return mangaObject
        }
        return createManga(manga, sourceId: sourceId, context: context)
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
        if object.fileInfo != nil {
            if let libraryObject = object.libraryObject {
                (context ?? self.context).delete(libraryObject)
            }
        } else {
            (context ?? self.context).delete(object)
        }
    }

    /// Set the cover image for a manga object.
    @discardableResult
    func setCover(
        sourceId: String,
        mangaId: String,
        coverUrl: String?,
        original: Bool = false,
    ) async -> String? {
        await container.performBackgroundTask { context in
            guard let object = self.getManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            ) else { return nil }
            let originalCover = object.cover
            object.cover = coverUrl
            var editedKeys = EditedKeys(rawValue: object.editedKeys)
            if original {
                // if the cover is set to original, remove the cover edited key
                editedKeys.remove(.cover)
            } else {
                // otherwise, set the cover edited key
                editedKeys.insert(.cover)
            }
            object.editedKeys = editedKeys.rawValue
            do {
                try context.save()
                return originalCover
            } catch {
                LogManager.logger.error("CoreDataManager.setCover: \(error.localizedDescription)")
                return nil
            }
        }
    }

    func hasEditedKey(
        sourceId: String,
        mangaId: String,
        key: EditedKeys,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        guard let object = self.getManga(
            sourceId: sourceId,
            mangaId: mangaId,
            context: context ?? self.context
        ) else { return false }
        let editedKeys = EditedKeys(rawValue: object.editedKeys)
        return editedKeys.contains(key)
    }

    // set the override flag to force update for already edited keys
    @discardableResult
    func updateMangaDetails(manga: Manga, override: Bool = false) async -> Manga? {
        await container.performBackgroundTask { context in
            guard let object = self.getManga(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                context: context
            ) else {
                return nil
            }
            object.load(from: manga, override: override)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.updateMangaDetails: \(error.localizedDescription)")
            }
            return object.toManga()
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
