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

    /// Remove a MangaObject in the background.
    func removeManga(sourceId: String, id: String) async {
        await container.performBackgroundTask { context in
            let request = MangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND sourceId == %@", id, sourceId)
            request.fetchLimit = 1
            do {
                if let object = (try context.fetch(request)).first {
                    context.delete(object)
                    try context.save()
                }
            } catch {
                LogManager.logger.error("Removing manga \(error.localizedDescription)")
            }
        }
    }

    func getMangaSourceReadingMode(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> Int {
        let context = context ?? self.context
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@ AND id == %@", sourceId, mangaId)
        request.fetchLimit = 1
        request.propertiesToFetch = ["viewer"]
        return Int((try? context.fetch(request))?.first?.viewer ?? -1)
    }
}
