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

        let uniqueKey = "\(chapter.sourceId).\(chapter.mangaId)"
        let key = "Manga.chapterDisplayMode.\(uniqueKey)"
        let displayMode = MangaDisplayMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default
        let mangaVolumeMode = displayMode == .volume
        let mangaChapterMode = displayMode == .chapter

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
                let state = try? await tracker.getState(trackId: item.id)
            else { continue }

            // Check if we need to update based on mode
            var shouldUpdate = false
            if mangaChapterMode {
                // Chapter mode: check chapter progress, or volume progress if no chapter
                shouldUpdate = (chapterNum != nil && (state.lastReadChapter ?? 0) < chapterNum!) ||
                              (volumeNum != nil && (state.lastReadChapter ?? 0) < Float(volumeNum!))
            } else if mangaVolumeMode {
                // Volume mode: check volume progress, or chapter progress if no volume
                shouldUpdate = (volumeNum != nil && (state.lastReadVolume ?? 0) < volumeNum!) ||
                              (chapterNum != nil && (state.lastReadVolume ?? 0) < Int(floor(chapterNum!)))
            } else {
                // Default mode: check both chapter and volume progress
                shouldUpdate = (chapterNum != nil && (state.lastReadChapter ?? 0) < chapterNum!) ||
                              (volumeNum != nil && (state.lastReadVolume ?? 0) < volumeNum!)
            }

            guard shouldUpdate else { continue }

            var update = TrackUpdate()

            // update last read chapter and volume based on mode
            if mangaChapterMode {
                // chapter mode: only update chapter, don't update volume
                let chapterNum = chapterNum ?? (volumeNum.flatMap { Float($0) } ?? 0)
                if chapterNum > 0 && state.lastReadChapter ?? 0 < chapterNum {
                    update.lastReadChapter = chapterNum
                }
            } else if mangaVolumeMode {
                // volume mode: only update volume, don't update chapter
                if let volumeNum, volumeNum > 0 && state.lastReadVolume ?? 0 < volumeNum {
                    update.lastReadVolume = volumeNum
                } else if let chapterNum {
                    // no volume metadata, use chapter number as volume
                    let volumeFromChapter = Int(floor(chapterNum))
                    if volumeFromChapter > state.lastReadVolume ?? 0 {
                        update.lastReadVolume = volumeFromChapter
                    }
                }
            } else {
                // default mode: update both chapter and volume if available
                if let chapterNum, chapterNum > 0 && state.lastReadChapter ?? 0 < chapterNum {
                    update.lastReadChapter = chapterNum
                }
                if let volumeNum, volumeNum > 0 && state.lastReadVolume ?? 0 < volumeNum {
                    update.lastReadVolume = volumeNum
                }
            }

            // update reading state
            var readLastChapter = (chapterNum != nil) && (state.totalChapters != nil && update.lastReadChapter != nil)
                                  ? (state.totalChapters! == Int(floor(update.lastReadChapter!))) : false
            if (chapterNum == nil || mangaVolumeMode) && update.lastReadVolume != nil {
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
        let (highestReadNumber, earliestReadDate) = await CoreDataManager.shared.container.performBackgroundTask { context in
            (
                CoreDataManager.shared.getHighestReadNumber(
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
                highestChapterRead: highestReadNumber,
                earliestReadDate: earliestReadDate
            )
            await TrackerManager.shared.saveTrackItem(item: TrackItem(
                id: id ?? item.id,
                trackerId: tracker.id,
                sourceId: manga.sourceId,
                mangaId: manga.id,
                title: item.title ?? manga.title
            ))

            // Sync progress from tracker if enabled or is enhanced tracker
            if UserDefaults.standard.bool(forKey: "Tracking.autoSyncFromTracker") || (tracker is EnhancedTracker) {
                await syncProgressFromTracker(tracker: tracker, trackId: id ?? item.id, manga: manga)
            }
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

    /// Sync progress from tracker to local history
    func syncProgressFromTracker(tracker: Tracker, trackId: String, manga: Manga) async {
        guard let state = try? await tracker.getState(trackId: trackId) else { return }
        let trackerLastReadChapter = state.lastReadChapter ?? 0
        let trackerLastReadVolume = state.lastReadVolume ?? 0

        if trackerLastReadChapter <= 0 && trackerLastReadVolume <= 0 { return }

        let currentHighestRead = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getHighestReadNumber(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                context: context
            ) ?? 0
        }

        // Get chapters from source
        guard
            let source = SourceManager.shared.source(for: manga.sourceId),
            let chapters = try? await source.getMangaUpdate(manga: manga.toNew(), needsDetails: false, needsChapters: true).chapters
        else { return }

        // Check for display mode
        let uniqueKey = "\(manga.sourceId).\(manga.id)"
        let key = "Manga.chapterDisplayMode.\(uniqueKey)"
        let displayMode = MangaDisplayMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default
        let mangaVolumeMode = displayMode == .volume
        let mangaChapterMode = displayMode == .chapter

        var chaptersToMark: [AidokuRunner.Chapter] = []

        // Determine what to sync based on tracker progress and forced mode
        if mangaChapterMode {
            // Forced chapter mode: sync chapter progress
            if trackerLastReadChapter > currentHighestRead {
                chaptersToMark = chapters.filter { ($0.chapterNumber ?? $0.volumeNumber ?? 0) <= trackerLastReadChapter }
            }
        } else if mangaVolumeMode {
            // Forced volume mode: sync volume progress
            if trackerLastReadVolume > 0 && Float(trackerLastReadVolume) > currentHighestRead {
                chaptersToMark = chapters.filter { ($0.volumeNumber ?? $0.chapterNumber ?? 0) <= Float(trackerLastReadVolume) }
            }
        } else {
            // Default mode: sync both chapter and volume progress
            if trackerLastReadChapter > currentHighestRead {
                chaptersToMark = chapters.filter { $0.chapterNumber ?? 0 <= trackerLastReadChapter }
            }
            if trackerLastReadVolume > 0 && chaptersToMark.isEmpty {
                chaptersToMark = chapters.filter { ($0.volumeNumber ?? 0) <= Float(trackerLastReadVolume) }
            }
        }

        if !chaptersToMark.isEmpty {
            await HistoryManager.shared.addHistory(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                chapters: chaptersToMark
            )
        }
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
