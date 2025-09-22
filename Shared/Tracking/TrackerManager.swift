//
//  TrackerManager.swift
//  Aidoku
//
//  Created by Skitty on 6/14/22.
//

import AidokuRunner
import CoreData
import Foundation

/// An interface to interact with title tracking services.
class TrackerManager {
    /// The shared tracker mangaer instance.
    static let shared = TrackerManager()

    /// An instance of the AniList tracker.
    let anilist = AniListTracker()
    /// An instance of the MyAnimeList tracker.
    let myanimelist = MyAnimeListTracker()
    /// An instance of the Shikimori tracker.
    let shikimori = ShikimoriTracker()
    /// An instance of the Bangumi tracker.
    let bangumi = BangumiTracker()
    /// An instance of the Komga tracker.
    let komga = KomgaTracker()

    /// An array of the available trackers.
    lazy var trackers: [Tracker] = [anilist, myanimelist, shikimori, bangumi, komga]

    /// A boolean indicating if there is a tracker that is currently logged in.
    var hasAvailableTrackers: Bool {
        trackers.filter { !($0 is EnhancedTracker) }.contains { $0.isLoggedIn }
    }

    /// Get the instance of the tracker with the specified id.
    func getTracker(id: String) -> Tracker? {
        trackers.first { $0.id == id }
    }

    /// Send chapter read update to logged in trackers.
    func setCompleted(chapter: Chapter) async {
        let chapterNum = chapter.chapterNum
        let volumeNum = chapter.volumeNum.flatMap { Int(floor($0)) }
        guard chapterNum != nil || volumeNum != nil else { return }

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
                let state = try? await tracker.getState(trackId: item.id),
                state.lastReadChapter ?? 0 < chapterNum ?? 0 || state.lastReadVolume ?? 0 < volumeNum ?? 0
            else { continue }

            var update = TrackUpdate()

            // update last read chapter and volume
            update.lastReadChapter = chapterNum
            if let volumeNum, volumeNum > 0 && state.lastReadVolume ?? 0 < volumeNum {
                update.lastReadVolume = volumeNum
            }

            // update reading state
            var readLastChapter = if let chapterNum {
                state.totalChapters.flatMap { $0 == Int(floor(chapterNum)) } ?? false
            } else {
                false
            }
            if chapterNum == nil && update.lastReadVolume != nil {
                readLastChapter = update.lastReadVolume == state.totalVolumes
            }
            if readLastChapter {
                if state.finishReadDate == nil {
                    update.finishReadDate = Date()
                }
                update.status = .completed
            } else if state.status != .reading && state.status != .rereading {
                // if there's no start date, and the status is planning or null, set it to current date
                if state.startReadDate == nil && state.status == nil || state.status == .planning {
                    update.startReadDate = Date()
                }
                update.status = state.status == .completed ? .rereading : .reading
            }

            do {
                try await tracker.update(trackId: item.id, update: update)
            } catch {
                LogManager.logger.error("Failed to set tracker chapter as completed (\(tracker.id)): \(error)")
            }
        }
    }

    /// Register a new track item to a manga and save to the data store.
    func register(tracker: Tracker, manga: Manga, item: TrackSearchItem) async {
        let (highestChapterRead, earliestReadDate) = await CoreDataManager.shared.container.performBackgroundTask { context in
            (
                CoreDataManager.shared.getHighestChapterRead(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    context: context
                ),
                CoreDataManager.shared.getEarliestReadDate(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    context: context
                )
            )
        }
        do {
            let id = try await tracker.register(
                trackId: item.id,
                highestChapterRead: highestChapterRead,
                earliestReadDate: earliestReadDate
            )
            await TrackerManager.shared.saveTrackItem(item: TrackItem(
                id: id ?? item.id,
                trackerId: tracker.id,
                sourceId: manga.sourceId,
                mangaId: manga.id,
                title: item.title ?? manga.title
            ))
        } catch {
            LogManager.logger.error("Failed to register tracker \(tracker.id): \(error)")
        }
    }

    /// Saves a TrackItem to the data store.
    private func saveTrackItem(item: TrackItem) async {
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

    /// Checks if there is a tracker that can be added to the given manga.
    func hasAvailableTrackers(sourceKey: String, mangaKey: String) -> Bool {
        trackers.contains { $0.canRegister(sourceKey: sourceKey, mangaKey: mangaKey) }
    }

    /// Add all applicable enhanced trackers to a given manga.
    func bindEnhancedTrackers(manga: AidokuRunner.Manga) async {
        for tracker in trackers where tracker is EnhancedTracker {
            if tracker.canRegister(sourceKey: manga.sourceKey, mangaKey: manga.key) {
                let oldManga = manga.toOld()
                do {
                    let items = try await tracker.search(for: oldManga, includeNsfw: true)
                    guard let item = items.first else {
                        LogManager.logger.error("Unable to find track item from tracker \(tracker.id)")
                        return
                    }
                    await TrackerManager.shared.register(tracker: tracker, manga: oldManga, item: item)
                } catch {
                    LogManager.logger.error("Unable to find track item from tracker \(tracker.id): \(error)")
                }
            }
        }
    }
}
