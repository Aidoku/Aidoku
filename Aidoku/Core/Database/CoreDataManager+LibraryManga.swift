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

    func removeFromLibrary(ids: [MangaIdentifier], context: NSManagedObjectContext) {
        // coredata has a predicate limit (1000?) so potentially large requests need to be batched
        let batchSize = 100

        for start in stride(from: 0, to: ids.count, by: batchSize) {
            let end = min(start + batchSize, ids.count)
            let batch = Array(ids[start..<end])

            removeFromLibraryBatch(ids: batch, context: context)
        }
    }

    private func removeFromLibraryBatch(ids: [MangaIdentifier], context: NSManagedObjectContext) {
        guard !ids.isEmpty else { return }

        let mangaRequest = MangaObject.fetchRequest()
        mangaRequest.predicate = mangaIdentifierPredicate(ids: ids, mangaKeyPath: "id")
        let mangaObjects = (try? context.fetch(mangaRequest)) ?? []

        for manga in mangaObjects {
            if manga.fileInfo != nil {
                if let libraryObject = manga.libraryObject {
                    context.delete(libraryObject)
                }
            } else {
                context.delete(manga)
            }
        }

        let chapterRequest = ChapterObject.fetchRequest()
        chapterRequest.predicate = mangaIdentifierPredicate(
            ids: ids,
            mangaKeyPath: "mangaId",
            extraPredicates: [NSPredicate(format: "fileInfo == nil")]
        )
        queueClear(request: chapterRequest, context: context)

        let trackRequest = TrackObject.fetchRequest()
        trackRequest.predicate = mangaIdentifierPredicate(ids: ids, mangaKeyPath: "mangaId")
        queueClear(request: trackRequest, context: context)
    }

    private func mangaIdentifierPredicate(
        ids: [MangaIdentifier],
        mangaKeyPath: String,
        extraPredicates: [NSPredicate] = []
    ) -> NSPredicate {
        let identifiers = NSCompoundPredicate(
            orPredicateWithSubpredicates: ids.map { id in
                NSCompoundPredicate(
                    andPredicateWithSubpredicates: [
                        NSPredicate(format: "sourceId == %@", id.sourceKey),
                        NSPredicate(format: "\(mangaKeyPath) == %@", id.mangaKey)
                    ]
                )
            }
        )
        guard !extraPredicates.isEmpty else {
            return identifiers
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [identifiers] + extraPredicates)
    }
}
