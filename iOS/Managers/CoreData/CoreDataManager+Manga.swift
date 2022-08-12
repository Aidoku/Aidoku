//
//  CoreDataManager+Manga.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/9/22.
//

import CoreData

extension CoreDataManager {

    /// Remove a MangaObject in the background.
    func removeManga(sourceId: String, id: String) {
        container.performBackgroundTask { context in
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
}
