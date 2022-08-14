//
//  CoreDataManager+LibraryManga.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/9/22.
//

import CoreData

extension CoreDataManager {

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
}
