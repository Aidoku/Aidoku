//
//  TrackerManager.swift
//  Aidoku
//
//  Created by Skitty on 6/14/22.
//

import Foundation
import CoreData

/// An interface to interact with title tracking services.
class TrackerManager {
    /// The shared tracker mangaer instance.
    static let shared = TrackerManager()

    /// An instance of the AniList tracker.
    let anilist = AniListTracker()
    /// An instance of the MyAnimeList tracker.
    let myanimelist = MyAnimeListTracker()

    /// An array of the available trackers.
    lazy var trackers: [Tracker] = [anilist, myanimelist]

    /// A boolean indicating if there is a tracker that is currently logged in.
    var hasAvailableTrackers: Bool {
        trackers.contains { $0.isLoggedIn }
    }

    /// Get the instance of the tracker with the specified id.
    func getTracker(id: String) -> Tracker? {
        trackers.first { $0.id == id }
    }

    /// Send chapter read update to logged in trackers.
    func setCompleted(chapter: Chapter) async {
        guard let chapterNum = chapter.chapterNum else { return }
        let volumeNum = Int(floor(chapter.volumeNum ?? -1))
        let trackItems: [TrackItem] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getTracks(
                sourceId: chapter.sourceId,
                mangaId: chapter.mangaId,
                context: context
            ).map { $0.toItem() }
        }

        for item in trackItems {
            guard
                let tracker = getTracker(id: item.trackerId),
                case let state = await tracker.getState(trackId: item.id),
                state.lastReadChapter ?? 0 < chapterNum
            else { continue }

            var update = TrackUpdate()

            // update last read chapter and volume
            update.lastReadChapter = chapterNum
            if volumeNum > 0 && state.lastReadVolume ?? 0 < volumeNum {
                update.lastReadVolume = volumeNum
            }

            // update reading state
            if Int(floor(state.lastReadChapter ?? 0)) == state.totalChapters ?? -1 {
                if state.finishReadDate == nil {
                    update.finishReadDate = Date()
                }
                update.status = .completed
            } else if state.status != .reading && state.status != .rereading {
                if state.startReadDate == nil {
                    update.startReadDate = Date()
                }
                update.status = .reading
            }

            await tracker.update(trackId: item.id, update: update)
        }
    }

    /// Saves a TrackItem to the data store.
    func saveTrackItem(item: TrackItem) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.createTrack(
                id: item.id,
                trackerId: item.trackerId,
                sourceId: item.sourceId,
                mangaId: item.mangaId,
                title: item.title,
                context: context
            )
            do {
                try context.save()
            } catch {
                LogManager.logger.error("TrackManager.saveTrackItem(item: \(item)): \(error.localizedDescription)")
            }
        }
        NotificationCenter.default.post(name: Notification.Name("updateTrackers"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("trackItemAdded"), object: item)
    }

    /// Removes the TrackItem from the data store.
    func removeTrackItem(item: TrackItem) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            self.removeTrackItem(item: item, context: context)
        }
    }

    func removeTrackItem(item: TrackItem, context: NSManagedObjectContext) {
        CoreDataManager.shared.removeTrack(
            trackerId: item.trackerId,
            sourceId: item.sourceId,
            mangaId: item.mangaId,
            context: context
        )
        do {
            try context.save()
        } catch {
            LogManager.logger.error("TrackManager.removeTrackItem(item: \(item)): \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: Notification.Name("updateTrackers"), object: nil)
    }

    /// Checks if a manga is being tracked.
    func isTracking(sourceId: String, mangaId: String) -> Bool {
        CoreDataManager.shared.hasTrack(sourceId: sourceId, mangaId: mangaId)
    }
}
