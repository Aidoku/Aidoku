//
//  CoreDataManager+Track.swift
//  Aidoku
//
//  Created by Skitty on 8/15/22.
//

import CoreData

extension CoreDataManager {
    /// Removes all track objects.
    func clearTracks(context: NSManagedObjectContext) {
        clear(request: TrackObject.fetchRequest(), context: context)
    }

    /// Gets all track objects.
    func getTracks(context: NSManagedObjectContext) -> [TrackObject] {
        (try? context.fetch(TrackObject.fetchRequest())) ?? []
    }

    @MainActor
    func hasTrack(mangaId: MangaIdentifier) -> Bool {
        hasTrack(mangaId: mangaId, context: context)
    }

    /// Checks if a track item exists in the data store for a manga.
    func hasTrack(mangaId: MangaIdentifier, context: NSManagedObjectContext) -> Bool {
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ ",
            mangaId.mangaKey, mangaId.sourceKey
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Checks if a track item for a specified tracker exists in the data store for a manga.
    func hasTrack(trackerId: String, mangaId: MangaIdentifier, context: NSManagedObjectContext) -> Bool {
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ AND trackerId = %@",
            mangaId.mangaKey, mangaId.sourceKey, trackerId
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Fetches a track item for a specified tracker exists in the data store for a manga.
    func getTrack(trackerId: String, mangaId: MangaIdentifier, context: NSManagedObjectContext) -> TrackObject? {
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ AND trackerId = %@",
            mangaId.mangaKey, mangaId.sourceKey, trackerId
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Fetches all track items for a specified manga.
    func getTracks(mangaId: MangaIdentifier, context: NSManagedObjectContext) -> [TrackObject] {
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId.mangaKey, mangaId.sourceKey
        )
        return (try? context.fetch(request)) ?? []
    }

    /// Fetches all track items for a specified tracker.
    func getTracks(trackerId: String, context: NSManagedObjectContext) -> [TrackObject] {
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
        mangaId: MangaIdentifier,
        title: String?,
        chapterOffset: Int = 0,
        context: NSManagedObjectContext
    ) -> TrackObject {
        let object = TrackObject(context: context)
        object.id = id
        object.trackerId = trackerId
        object.sourceId = mangaId.sourceKey
        object.mangaId = mangaId.mangaKey
        object.title = title
        object.chapterOffset = Int16(chapterOffset)
        return object
    }

    func setTrackChapterOffset(
        trackerId: String,
        mangaId: MangaIdentifier,
        chapterOffset: Int,
        context: NSManagedObjectContext
    ) {
        guard let object = getTrack(
            trackerId: trackerId,
            mangaId: mangaId,
            context: context
        ) else { return }
        object.chapterOffset = Int16(chapterOffset)
    }

    /// Removes a track item.
    func removeTrack(trackerId: String, mangaId: MangaIdentifier, context: NSManagedObjectContext) {
        guard let object = getTrack(
            trackerId: trackerId,
            mangaId: mangaId,
            context: context
        ) else { return }
        context.delete(object)
    }

    /// Removes all track items for a tracker.
    func removeTracks(trackerId: String, context: NSManagedObjectContext) {
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(format: "trackerId == %@", trackerId)
        queueClear(request: request, context: context)
    }

    func removeTracks(mangaId: MangaIdentifier, context: NSManagedObjectContext) {
        let request = TrackObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId.mangaKey, mangaId.sourceKey
        )
        queueClear(request: request, context: context)
    }
}
