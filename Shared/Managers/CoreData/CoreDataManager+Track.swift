//
//  CoreDataManager+Track.swift
//  Aidoku
//
//  Created by Skitty on 8/15/22.
//

import CoreData

extension CoreDataManager {

    /// Removes all track objects.
    func clearTracks(context: NSManagedObjectContext? = nil) {
        clear(request: TrackObject.fetchRequest(), context: context)
    }

    /// Gets all track objects.
    func getTracks(context: NSManagedObjectContext? = nil) -> [TrackObject] {
        (try? (context ?? self.context).fetch(TrackObject.fetchRequest())) ?? []
    }

    /// Checks if a track item exists in the data store for a manga.
    func hasTrack(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ ",
            mangaId, sourceId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Checks if a track item for a specified tracker exists in the data store for a manga.
    func hasTrack(trackerId: String, sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ AND trackerId = %@",
            mangaId, sourceId, trackerId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Fetches a track item for a specified tracker exists in the data store for a manga.
    func getTrack(trackerId: String, sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> TrackObject? {
        let context = context ?? self.context
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ AND trackerId = %@",
            mangaId, sourceId, trackerId
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Fetches all track items for a specified manga.
    func getTracks(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> [TrackObject] {
        let context = context ?? self.context
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId, sourceId
        )
        return (try? context.fetch(request)) ?? []
    }

    /// Fetches all track items for a specified tracker.
    func getTracks(trackerId: String, context: NSManagedObjectContext? = nil) -> [TrackObject] {
        let context = context ?? self.context
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "trackerId == %@",
            trackerId
        )
        return (try? context.fetch(request)) ?? []
    }

    /// Creates a new track item.
    @discardableResult
    func createTrack(
        id: String,
        trackerId: String,
        sourceId: String,
        mangaId: String,
        title: String?,
        context: NSManagedObjectContext? = nil
    ) -> TrackObject {
        let context = context ?? self.context
        let object = TrackObject(context: context)
        object.id = id
        object.trackerId = trackerId
        object.sourceId = sourceId
        object.mangaId = mangaId
        object.title = title
        return object
    }

    /// Removes a track item.
    func removeTrack(trackerId: String, sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) {
        guard let object = getTrack(
            trackerId: trackerId,
            sourceId: sourceId,
            mangaId: mangaId,
            context: context
        ) else { return }
        (context ?? self.context).delete(object)
    }

    /// Removes all track items for a tracker.
    func removeTracks(trackerId: String, context: NSManagedObjectContext? = nil) {
        let objects = getTracks(
            trackerId: trackerId,
            context: context
        )
        let context = context ?? self.context
        for object in objects {
            context.delete(object)
        }
    }
}
