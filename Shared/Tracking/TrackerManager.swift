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

    /// An instance of the Komga tracker.
    let komga = KomgaTracker()
    /// An instance of the Komga tracker.
    let kavita = KavitaTracker()
    /// An instance of the AniList tracker.
    let anilist = AniListTracker()
    /// An instance of the MyAnimeList tracker.
    let myanimelist = MyAnimeListTracker()
    /// An instance of the Shikimori tracker.
    let shikimori = ShikimoriTracker()
    /// An instance of the Bangumi tracker.
    let bangumi = BangumiTracker()

    /// An array of the available trackers.
    lazy var trackers: [Tracker] = [komga, kavita, anilist, myanimelist, shikimori, bangumi]

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
        let displayMode = ChapterTitleDisplayMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default

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
                !(tracker is PageTracker),
                let state = try? await tracker.getState(trackId: item.id)
            else { continue }

            // Check if we need to update based on chapter display mode
            var shouldUpdate = false
            if displayMode == .chapter {
                // Chapter mode: check chapter progress, or volume progress if no chapter
                let hasChapterProgress = chapterNum != nil && (state.lastReadChapter ?? 0) < chapterNum!
                let hasVolumeProgress = volumeNum != nil && (state.lastReadChapter ?? 0) < Float(volumeNum!)
                shouldUpdate = hasChapterProgress || hasVolumeProgress
            } else if displayMode == .volume {
                // Volume mode: check volume progress, or chapter progress if no volume
                let hasChapterProgress = chapterNum != nil && (state.lastReadVolume ?? 0) < Int(floor(chapterNum!))
                let hasVolumeProgress = volumeNum != nil && (state.lastReadVolume ?? 0) < volumeNum!
                shouldUpdate = hasChapterProgress || hasVolumeProgress
            } else {
                // Default mode: check both chapter and volume progress
                let hasChapterProgress = chapterNum != nil && (state.lastReadChapter ?? 0) < chapterNum!
                let hasVolumeProgress = volumeNum != nil && (state.lastReadVolume ?? 0) < volumeNum!
                shouldUpdate = hasChapterProgress || hasVolumeProgress
            }
            guard shouldUpdate else { continue }

            var update = TrackUpdate()

            // update last read chapter and volume based on mode
            if displayMode == .chapter {
                // chapter mode: only update chapter, don't update volume
                if let chapterNum, chapterNum > 0 && state.lastReadChapter ?? 0 < chapterNum {
                    update.lastReadChapter = chapterNum
                } else if let volumeNum {
                    // no chapter metadata, use volume number as chapter
                    let chapterFromVolume = Float(volumeNum)
                    if chapterFromVolume > state.lastReadChapter ?? 0 {
                        update.lastReadChapter = chapterFromVolume
                    }
                }
            } else if displayMode == .volume {
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
            let readLastChapter = if
                chapterNum != nil,
                let totalChapters = state.totalChapters,
                let lastReadChapter = state.lastReadChapter
            {
                totalChapters == Int(floor(lastReadChapter))
            } else if (chapterNum == nil || displayMode == .volume) && update.lastReadVolume != nil {
                update.lastReadVolume == state.totalVolumes
            } else {
                false
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

    /// Set the page progress for trackers that support it.
    func setProgress(sourceKey: String, mangaKey: String, chapter: AidokuRunner.Chapter, progress: ChapterReadProgress) async {
        await setProgress(sourceKey: sourceKey, mangaKey: mangaKey, chapters: [chapter], progress: progress)
    }

    func setProgress(sourceKey: String, mangaKey: String, chapters: [AidokuRunner.Chapter], progress: ChapterReadProgress) async {
        let trackItems: [TrackItem] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getTracks(
                sourceId: sourceKey,
                mangaId: mangaKey,
                context: context
            ).map { $0.toItem() }
        }

        for item in trackItems {
            guard let tracker = getTracker(id: item.trackerId) as? PageTracker else { continue }
            do {
                for chapter in chapters {
                    try await tracker.setProgress(trackId: item.id, chapter: chapter, progress: progress)
                }
            } catch {
                LogManager.logger.error("Failed to set tracker progress (\(tracker.id)): \(error)")
            }
        }
    }

    /// Register a new track item to a manga and save to the data store.
    func register(tracker: Tracker, manga: AidokuRunner.Manga, item: TrackSearchItem) async {
        let (highestReadNumber, earliestReadDate) = await CoreDataManager.shared.container.performBackgroundTask { context in
            (
                CoreDataManager.shared.getHighestReadNumber(
                    sourceId: manga.sourceKey,
                    mangaId: manga.key,
                    context: context
                ),
                CoreDataManager.shared.getEarliestReadDate(
                    sourceId: manga.sourceKey,
                    mangaId: manga.key,
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
                sourceId: manga.sourceKey,
                mangaId: manga.key,
                title: item.title ?? manga.title
            ))

            // Sync progress from tracker if enabled or is enhanced tracker
            if UserDefaults.standard.bool(forKey: "Tracking.autoSyncFromTracker") || (tracker is EnhancedTracker) || (tracker is PageTracker) {
                if tracker is PageTracker {
                    await syncPageTrackerHistory(manga: manga)
                } else {
                    await syncProgressFromTracker(tracker: tracker, trackId: id ?? item.id, manga: manga)
                }
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

    /// Sync progress from tracker to local history.
    func syncProgressFromTracker(
        tracker: Tracker,
        trackId: String,
        manga: AidokuRunner.Manga,
        chapters: [AidokuRunner.Chapter]? = nil
    ) async {
        guard
            let state = try? await tracker.getState(trackId: trackId),
            case let trackerLastReadChapter = state.lastReadChapter,
            case let trackerLastReadVolume = state.lastReadVolume,
            (trackerLastReadChapter ?? 0) > 0 || (trackerLastReadVolume ?? 0) > 0
        else {
            return
        }

        let chapters = if let chapters {
            chapters
        } else {
            await getChapters(manga: manga)
        }
        guard !chapters.isEmpty else { return }

        let currentHighestRead = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getHighestReadNumber(
                sourceId: manga.sourceKey,
                mangaId: manga.key,
                context: context
            ) ?? 0
        }

        // Check for display mode
        let key = "Manga.chapterDisplayMode.\(manga.uniqueKey)"
        let displayMode = ChapterTitleDisplayMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default

        var chaptersToMark: [AidokuRunner.Chapter] = []

        // Determine what to sync based on tracker progress and forced mode
        if displayMode == .chapter {
            // Forced chapter mode: sync chapter progress
            if let trackerLastReadChapter, trackerLastReadChapter > currentHighestRead {
                chaptersToMark = chapters.filter { ($0.chapterNumber ?? $0.volumeNumber ?? 0) <= trackerLastReadChapter }
            }
        } else if displayMode == .volume {
            // Forced volume mode: sync volume progress
            if let trackerLastReadVolume, trackerLastReadVolume > 0 && Float(trackerLastReadVolume) > currentHighestRead {
                chaptersToMark = chapters.filter { ($0.volumeNumber ?? $0.chapterNumber ?? 0) <= Float(trackerLastReadVolume) }
            }
        } else {
            // Default mode: sync both chapter and volume progress
            var checkedForChapters = false
            if let trackerLastReadChapter, trackerLastReadChapter > currentHighestRead {
                // find all chapters with a chapter number less than or equal to the last tracker chapter
                chaptersToMark = chapters.filter {
                    // floor the chapter number so partial chapters are marked (e.g. 10.1 and 10.2 will be marked if the tracker is at 10)
                    if let chapter = $0.chapterNumber, floor(chapter) <= trackerLastReadChapter {
                        true
                    } else {
                        false
                    }
                }
                checkedForChapters = true
            }
            // otherwise, if we didn't find any chapters, try using the volume number instead
            // note: ignores the case where we skipped checking chapters due to currentHighestRead <= trackerLastReadChapter (#753)
            let foundNoChapters = checkedForChapters && chaptersToMark.isEmpty
            if let trackerLastReadVolume, trackerLastReadVolume > 0 && (foundNoChapters || trackerLastReadChapter == nil) {
                // find all chapters with a volume number less than or equal to the last tracker volume
                chaptersToMark = chapters.filter {
                    if let volume = $0.volumeNumber, volume <= Float(trackerLastReadVolume) {
                        true
                    } else {
                        false
                    }
                }
            }
        }

        if !chaptersToMark.isEmpty {
            await HistoryManager.shared.addHistory(
                sourceId: manga.sourceKey,
                mangaId: manga.key,
                chapters: chaptersToMark
            )
        }
    }

    /// Sync progress with all linked trackers that support page progress.
    func syncPageTrackerHistory(manga: AidokuRunner.Manga, chapters: [AidokuRunner.Chapter]? = nil) async {
        let chapters = if let chapters {
            chapters
        } else {
            await getChapters(manga: manga)
        }
        guard !chapters.isEmpty else { return }

        // fetch remote history from linked page trackers
        var result: [String: ChapterReadProgress] = [:]

        let trackItems: [TrackItem] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getTracks(
                sourceId: manga.sourceKey,
                mangaId: manga.key,
                context: context
            ).map { $0.toItem() }
        }

        for item in trackItems {
            guard let tracker = getTracker(id: item.trackerId) as? PageTracker else { continue }
            do {
                let batchProgress = try await tracker.getProgress(trackId: item.id, chapters: chapters)
                if result.isEmpty {
                    result = batchProgress
                } else {
                    // merge with the existing progress map, keeping newest
                    for (chapterKey, progress) in batchProgress {
                        if let existing = result[chapterKey] {
                            // replace if the new date is higher, otherwise keep existing
                            if let existingDate = existing.date, let newDate = progress.date {
                                if newDate > existingDate {
                                    result[chapterKey] = progress
                                }
                            }
                        } else {
                            result[chapterKey] = progress
                        }
                    }
                }
            } catch {
                LogManager.logger.error("Failed to get tracker progress (\(tracker.id)): \(error)")
            }
        }

        guard !result.isEmpty else { return }

        // create local history
        let (completed, progressed) = await CoreDataManager.shared.container.performBackgroundTask { context in
            var completed: [String] = []
            var progressed: [String: Int] = [:]

            for (chapterKey, progress) in result {
                let existingHistory = CoreDataManager.shared.getHistory(
                    sourceId: manga.sourceKey,
                    mangaId: manga.key,
                    chapterId: chapterKey,
                    context: context
                )
                if let existingDate = existingHistory?.dateRead, let newDate = progress.date, newDate <= existingDate {
                    // don't update if the existing history is newer than the tracker history
                    continue
                }
                // mark chapters as read
                if progress.completed {
                    if !(existingHistory?.completed ?? false) {
                        completed.append(chapterKey)
                        CoreDataManager.shared.setCompleted(
                            sourceId: manga.sourceKey,
                            mangaId: manga.key,
                            chapterIds: [chapterKey],
                            date: progress.date ?? Date(),
                            context: context
                        )
                    }
                } else if progress.page != 0 {
                    progressed[chapterKey] = progress.page
                    CoreDataManager.shared.setProgress(
                        progress.page,
                        sourceId: manga.sourceKey,
                        mangaId: manga.key,
                        chapterId: chapterKey,
                        dateRead: progress.date,
                        completed: false,
                        context: context
                    )
                }
            }

            // mark manga as read only if history was updated
            if !completed.isEmpty || !progressed.isEmpty {
                CoreDataManager.shared.setRead(
                    sourceId: manga.sourceKey,
                    mangaId: manga.key,
                    context: context
                )
            }

            try? context.save()

            return (completed, progressed)
        }

        // post notifications to update ui
        if !completed.isEmpty {
            NotificationCenter.default.post(
                name: .historyAdded,
                object: completed.map {
                    Chapter(
                        sourceId: manga.sourceKey,
                        id: $0,
                        mangaId: manga.key,
                        title: "",
                        sourceOrder: -1
                    )
                }
            )
        }
        for (chapterKey, page) in progressed {
            NotificationCenter.default.post(
                name: .historySet,
                object: (
                    Chapter(
                        sourceId: manga.sourceKey,
                        id: chapterKey,
                        mangaId: manga.key,
                        title: "",
                        sourceOrder: -1
                    ),
                    page
                )
            )
        }
    }

    /// Add all applicable enhanced trackers to a given manga.
    func bindEnhancedTrackers(manga: AidokuRunner.Manga) async {
        for tracker in trackers where tracker is EnhancedTracker {
            if tracker.canRegister(sourceKey: manga.sourceKey, mangaKey: manga.key) {
                do {
                    let items = try await tracker.search(for: manga, includeNsfw: true)
                    guard let item = items.first else {
                        LogManager.logger.error("Unable to find track item from tracker \(tracker.id)")
                        return
                    }
                    await TrackerManager.shared.register(tracker: tracker, manga: manga, item: item)
                } catch {
                    LogManager.logger.error("Unable to find track item from tracker \(tracker.id): \(error)")
                }
            }
        }
    }
}

extension TrackerManager {
    private func getChapters(manga: AidokuRunner.Manga) async -> [AidokuRunner.Chapter] {
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceKey, mangaId: manga.key, context: context)
        }
        if inLibrary {
            // load data from db
            return await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getChapters(
                    sourceId: manga.sourceKey,
                    mangaId: manga.key,
                    context: context
                ).map {
                    $0.toNewChapter()
                }
            }
        } else {
            return (try? await SourceManager.shared.source(for: manga.sourceKey)?.getMangaUpdate(
                manga: manga,
                needsDetails: false,
                needsChapters: true
            ).chapters) ?? []
        }
    }
}
