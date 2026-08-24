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
    func clearManga(context: NSManagedObjectContext) {
        clear(request: MangaObject.fetchRequest(), context: context)
    }

    /// Gets all manga objects.
    func getManga(context: NSManagedObjectContext) -> [MangaObject] {
        (try? context.fetch(MangaObject.fetchRequest())) ?? []
    }

    @MainActor
    func getManga(mangaId: MangaIdentifier) -> MangaObject? {
        getManga(mangaId: mangaId, context: context)
    }

    /// Get a particular manga object.
    func getManga(
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> MangaObject? {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@ AND id == %@", mangaId.sourceKey, mangaId.mangaKey)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Create a manga object.
    @discardableResult
    func createManga(
        _ manga: AidokuRunner.Manga,
        context: NSManagedObjectContext
    ) -> MangaObject {
        let object = MangaObject(context: context)
        object.load(from: manga, sourceId: manga.sourceKey)
        return object
    }

    func getOrCreateManga(
        _ manga: AidokuRunner.Manga,
        context: NSManagedObjectContext
    ) -> MangaObject {
        if let mangaObject = getManga(mangaId: manga.identifier, context: context) {
            return mangaObject
        }
        return createManga(manga, context: context)
    }

    @MainActor
    func hasManga(mangaId: MangaIdentifier) -> Bool {
        hasManga(mangaId: mangaId, context: context)
    }

    /// Check if a manga object exists.
    func hasManga(
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> Bool {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND sourceId == %@", mangaId.mangaKey, mangaId.sourceKey)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Removes a manga object.
    func removeManga(mangaId: MangaIdentifier, context: NSManagedObjectContext) {
        guard let object = getManga(mangaId: mangaId, context: context) else { return }
        if object.fileInfo != nil {
            if let libraryObject = object.libraryObject {
                context.delete(libraryObject)
            }
        } else {
            context.delete(object)
        }
    }

    /// Set the cover image for a manga object.
    @discardableResult
    func setCover(
        mangaId: MangaIdentifier,
        coverUrl: String?,
        original: Bool = false,
    ) async -> String? {
        await container.performBackgroundTask { context in
            guard let object = self.getManga(
                mangaId: mangaId,
                context: context
            ) else {
                return nil
            }
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
        mangaId: MangaIdentifier,
        key: EditedKeys,
        context: NSManagedObjectContext
    ) -> Bool {
        guard let object = self.getManga(
            mangaId: mangaId,
            context: context
        ) else { return false }
        let editedKeys = EditedKeys(rawValue: object.editedKeys)
        return editedKeys.contains(key)
    }

    // set the override flag to force update for already edited keys
    @discardableResult
    func updateMangaDetails(manga: Manga, override: Bool = false) async -> Manga? {
        await container.performBackgroundTask { context in
            guard let object = self.getManga(
                mangaId: manga.identifier,
                context: context
            ) else {
                return nil
            }
            object.load(from: manga, override: override)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.updateMangaDetails: \(error)")
            }
            return object.toManga()
        }
    }

    @MainActor
    func getMangaSourceReadingMode(mangaId: MangaIdentifier) -> Int {
        getMangaSourceReadingMode(mangaId: mangaId, context: context)
    }

    func getMangaSourceReadingMode(mangaId: MangaIdentifier, context: NSManagedObjectContext) -> Int {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND sourceId == %@", mangaId.mangaKey, mangaId.sourceKey)
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
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> ChapterFilters {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND sourceId == %@", mangaId.mangaKey, mangaId.sourceKey)
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
