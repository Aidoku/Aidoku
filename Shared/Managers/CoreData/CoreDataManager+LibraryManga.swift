//
//  CoreDataManager+LibraryManga.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/9/22.
//

import CoreData

extension CoreDataManager {

    /// Remove all library manga objects.
    func clearLibrary(context: NSManagedObjectContext? = nil) {
        clear(request: LibraryMangaObject.fetchRequest(), context: context)
    }

    /// Get a particular library object.
    func getLibraryManga(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> LibraryMangaObject? {
        let context = context ?? self.context
        let request = LibraryMangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", sourceId, mangaId)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get all library manga objects.
    func getLibraryManga(context: NSManagedObjectContext? = nil) -> [LibraryMangaObject] {
        let context = context ?? self.context
        let request = LibraryMangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "manga != nil")
        return (try? context.fetch(request)) ?? []
    }

    /// Check if a library object exists.
    func hasLibraryManga(
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        let context = context ?? self.context
        let request = LibraryMangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", sourceId, mangaId)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Create a new library object.
    @discardableResult
    func createLibraryManga(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> LibraryMangaObject? {
        let context = context ?? self.context
        guard let mangaObject = getManga(sourceId: sourceId, mangaId: mangaId, context: context) else {
            return nil
        }
        let object = LibraryMangaObject(context: context)
        object.manga = mangaObject
        return object
    }

    /// Set LibraryManga opened date to current date.
    func setOpened(sourceId: String, mangaId: String) async {
        await container.performBackgroundTask { context in
            let request = LibraryMangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", sourceId, mangaId)
            request.fetchLimit = 1
            do {
                if let object = (try context.fetch(request)).first {
                    object.lastOpened = Date()
                    try context.save()
                }
            } catch {
                LogManager.logger.error("setOpened: \(error.localizedDescription)")
            }
        }
    }

    /// Set LibraryManga last read date to current date.
    func setRead(sourceId: String, mangaId: String) async {
        await container.performBackgroundTask { context in
            let request = LibraryMangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", sourceId, mangaId)
            request.fetchLimit = 1
            do {
                if let object = (try context.fetch(request)).first {
                    object.lastRead = Date()
                    try context.save()
                }
            } catch {
                LogManager.logger.error("setRead: \(error.localizedDescription)")
            }
        }
    }

    /// Add a manga with the specified chapters to the library.
    func addToLibrary(manga: Manga, chapters: [Chapter]) async {
        await container.performBackgroundTask { context in
            let mangaObject = self.getOrCreateManga(manga, context: context)
            let libraryObject = LibraryMangaObject(context: context)
            libraryObject.manga = mangaObject
            self.setChapters(chapters, sourceId: manga.sourceId, mangaId: manga.id, context: context)
//            DataManager.shared.libraryManga.append(manga) // temporary
            do {
                try context.save()
            } catch {
                LogManager.logger.error("addToLibrary: \(error.localizedDescription)")
            }
        }
    }
}
