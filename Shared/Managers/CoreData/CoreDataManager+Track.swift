//
//  CoreDataManager+Track.swift
//  Aidoku
//
//  Created by Skitty on 8/15/22.
//

import CoreData

extension CoreDataManager {

    /// Remove all track objects.
    func clearTracks(context: NSManagedObjectContext? = nil) {
        clear(request: TrackObject.fetchRequest(), context: context)
    }

    /// Check if a tracker exists in the data store for a manga.
    func hasTracker(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ ",
            mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }
}
