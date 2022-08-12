//
//  CoreDataManager+LibraryManga.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/9/22.
//

import CoreData

extension CoreDataManager {

    /// Set LibraryManga opened date to current date.
    func setOpened(sourceId: String, id: String) async {
        await container.performBackgroundTask { context in
            let request = LibraryMangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "manga.id == %@ AND manga.sourceId = %@", id, sourceId)
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
