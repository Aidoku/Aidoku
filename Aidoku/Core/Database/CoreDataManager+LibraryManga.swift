//
//  CoreDataManager+LibraryManga.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/9/22.
//

import CoreData
import AidokuRunner

extension CoreDataManager {
    /// Remove all library manga objects.
    func clearLibrary(context: NSManagedObjectContext) {
        clear(request: LibraryMangaObject.fetchRequest(), context: context)
    }

    /// Get library objects from a particular source.
    func getLibraryManga(sourceKey: String, context: NSManagedObjectContext) -> [LibraryMangaObject] {
        let request = LibraryMangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "manga.sourceId == %@", sourceKey)
        return (try? context.fetch(request)) ?? []
    }

    /// Get a particular library object.
    func getLibraryManga(mangaId: MangaIdentifier, context: NSManagedObjectContext) -> LibraryMangaObject? {
        let request = LibraryMangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", mangaId.sourceKey, mangaId.mangaKey)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get all library manga objects.
    func getLibraryManga(category: String? = nil, context: NSManagedObjectContext) -> [LibraryMangaObject] {
        let request = LibraryMangaObject.fetchRequest()
        if let category = category {
            request.predicate = NSPredicate(format: "manga != nil AND any categories.title = %@", category)
        } else {
            request.predicate = NSPredicate(format: "manga != nil")
        }
        return (try? context.fetch(request)) ?? []
    }

    /// Check if a library object exists.
    func hasLibraryManga(
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> Bool {
        let request = LibraryMangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", mangaId.sourceKey, mangaId.mangaKey)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Set LibraryManga opened date to current date.
    func setOpened(mangaId: MangaIdentifier) async {
        await container.performBackgroundTask { context in
            let request = LibraryMangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", mangaId.sourceKey, mangaId.mangaKey)
            request.fetchLimit = 1
            do {
                if let object = (try context.fetch(request)).first {
                    object.lastOpened = Date()
                    try context.save()
                }
            } catch {
                LogManager.logger.error("setOpened: \(error)")
            }
        }
    }

    /// Set LibraryManga last read date to current date.
    func setRead(mangaId: MangaIdentifier, date: Date? = nil, context: NSManagedObjectContext) {
        let request = LibraryMangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", mangaId.sourceKey, mangaId.mangaKey)
        request.fetchLimit = 1
        do {
            if let object = try context.fetch(request).first {
                object.lastRead = date ?? Date.now
            }
        } catch {
            LogManager.logger.error("setRead: \(error)")
        }
    }

    /// Add a manga with the specified chapters to the library.
    func addToLibrary(
        manga: AidokuRunner.Manga,
        chapters: [AidokuRunner.Chapter],
        context: NSManagedObjectContext
    ) {
        let mangaObject = self.getOrCreateManga(manga, context: context)
        let libraryObject = LibraryMangaObject(context: context)
        libraryObject.manga = mangaObject
        libraryObject.lastChapter = chapters.compactMap { $0.dateUploaded }.max()
        self.setChapters(chapters, mangaId: manga.identifier, context: context)
    }
}
