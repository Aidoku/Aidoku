//
//  MangaManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import AidokuRunner
import BackgroundTasks
import CoreData
import Nuke

#if canImport(UIKit)
import UIKit
#endif

actor MangaManager {
    static let shared = MangaManager()

    private static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "") + ".libraryRefresh"

    private var libraryRefreshTask: Task<(), Never>?
    private var libraryRefreshProgressTask: Task<(), Never>?
    private var onLibraryRefreshProgress: (@MainActor (Progress) -> Void)?

    private var targetCategory: String?
    private var skipReachabilityCheck: Bool = false

    private static let maxConcurrentLibraryUpdateTasks = 10

    nonisolated func getNextChapter(
        manga: AidokuRunner.Manga,
        chapters: [AidokuRunner.Chapter],
        readingHistory: [String: (page: Int, date: Int)],
        sortAscending: Bool
    ) -> AidokuRunner.Chapter? {
        let resumeLastOpened = UserDefaults.standard.bool(forKey: "Library.resumeLastOpenedChapter")

        // 1. Resume Reading: Find the most recently read chapter that isn't
        // completed, unless the "resume last opened" option is enabled.
        var selectedChapter: AidokuRunner.Chapter?
        var selectedDate: Int = -1

        for chapter in chapters {
            guard
                let history = readingHistory[chapter.id],
                resumeLastOpened || history.page != -1,
                history.date > selectedDate
            else { continue }

            if chapter.locked {
                let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
                let isDownloaded = DownloadManager.shared.getDownloadStatus(for: identifier) == .finished
                guard isDownloaded else { continue }
            }

            selectedDate = history.date
            selectedChapter = chapter
        }

        if let selectedChapter {
            return selectedChapter
        }

        // 2. Fallback: Find first uncompleted chapter in sort order (Start Reading)
        let sorted = sortAscending ? chapters : chapters.reversed()

        return sorted.first(where: { chapter in
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
            let isDownloaded = DownloadManager.shared.getDownloadStatus(for: identifier) == .finished
            let isUnlocked = !chapter.locked || isDownloaded
            let history = readingHistory[chapter.id]
            let isCompleted = history?.page ?? 0 == -1

            return isUnlocked && !isCompleted
        })
    }
}

// MARK: - Library Managing
extension MangaManager {
    func addToLibrary(
        manga: AidokuRunner.Manga,
        chapters: [AidokuRunner.Chapter] = [],
        fetchMangaDetails: Bool = false
    ) async {
        var manga = manga
        var chapters = chapters
        // update manga or chapters
        if fetchMangaDetails || chapters.isEmpty {
            if let source = SourceManager.shared.source(for: manga.sourceKey) {
                manga = (try? await source.getMangaUpdate(manga: manga, needsDetails: fetchMangaDetails, needsChapters: chapters.isEmpty)) ?? manga
                chapters = manga.chapters ?? chapters
            }
        }
        await CoreDataManager.shared.container.performBackgroundTask { [manga, chapters] context in
            CoreDataManager.shared.addToLibrary(
                manga: manga,
                chapters: chapters,
                context: context
            )
            // add to default category
            let defaultCategory = UserDefaults.standard.string(forKey: "Library.defaultCategory")
            if let defaultCategory {
                let hasCategory = CoreDataManager.shared.hasCategory(title: defaultCategory, context: context)
                if hasCategory {
                    CoreDataManager.shared.addCategoriesToManga(
                        sourceId: manga.sourceKey,
                        mangaId: manga.key,
                        categories: [defaultCategory],
                        context: context
                    )
                }
            }
            do {
                try context.save()
            } catch {
                LogManager.logger.error("MangaManager.addToLibrary: \(error.localizedDescription)")
            }
        }
        // add enhanced trackers
        await TrackerManager.shared.bindEnhancedTrackers(manga: manga)

        NotificationCenter.default.post(name: .addToLibrary, object: manga)
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    func removeFromLibrary(sourceId: String, mangaId: String) async {
        // Get manga object for notification before deletion
        let mangaForNotification = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getManga(sourceId: sourceId, mangaId: mangaId, context: context)?.toNewManga()
        }

        await CoreDataManager.shared.container.performBackgroundTask { context in
            // remove from library
            CoreDataManager.shared.removeManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )
            // remove chapters
            CoreDataManager.shared.removeChapters(sourceId: sourceId, mangaId: mangaId, context: context)
            // remove associated trackers
            if
                case let items = CoreDataManager.shared.getTracks(
                    sourceId: sourceId,
                    mangaId: mangaId,
                    context: context
                ).map({ $0.toItem() }),
                !items.isEmpty
            {
                for item in items {
                    TrackerManager.shared.removeTrackItem(item: item, context: context)
                }
            }
            do {
                try context.save()
            } catch {
                LogManager.logger.error("MangaManager.removeFromLibrary(mangaId: \(mangaId)): \(error.localizedDescription)")
            }
        }

        // Post specific notification for removal with manga object
        if let mangaForNotification {
            NotificationCenter.default.post(name: .removeFromLibrary, object: mangaForNotification)
        }

        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    func restoreToLibrary(
        manga: Manga,
        chapters: [Chapter],
        trackItems: [TrackItem],
        categories: [String]
    ) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.addToLibrary(
                manga: manga.toNew(),
                chapters: chapters.map { $0.toNew() },
                context: context
            )

            if let libraryObject = CoreDataManager.shared.getLibraryManga(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                context: context
            ) {
                if
                    let lastOpened = manga.lastOpened,
                    let lastUpdated = manga.lastUpdated,
                    let lastUpdatedChapters = manga.lastUpdatedChapters,
                    let dateAdded = manga.dateAdded
                {
                    libraryObject.lastOpened = lastOpened
                    libraryObject.lastUpdated = lastUpdated
                    libraryObject.lastUpdatedChapters = lastUpdatedChapters
                    libraryObject.lastChapter = manga.lastChapter
                    libraryObject.lastRead = manga.lastRead
                    libraryObject.dateAdded = dateAdded
                }
            }

            for item in trackItems {
                CoreDataManager.shared.createTrack(
                    id: item.id, trackerId: item.trackerId, sourceId: item.sourceId,
                    mangaId: item.mangaId, title: item.title, context: context)
            }

            for category in categories {
                let hasCategory = CoreDataManager.shared.hasCategory(
                    title: category, context: context)
                if !hasCategory {
                    CoreDataManager.shared.createCategory(title: category, context: context)
                }
            }
            CoreDataManager.shared.addCategoriesToManga(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                categories: categories,
                context: context
            )

            do {
                try context.save()
            } catch {
                LogManager.logger.error(
                    "MangaManager.restoreToLibrary: \(error.localizedDescription)")
            }
        }
    }

    static func shouldAskForCategories() -> Bool {
        let categories = CoreDataManager.shared.getCategoryTitles()
        guard !categories.isEmpty else { return false }
        if
            let defaultCategory = UserDefaults.standard.string(forKey: "Library.defaultCategory"),
            defaultCategory == "none" || categories.contains(defaultCategory)
        {
            return false
        }
        return true
    }
}

// MARK: - Category Managing
extension MangaManager {
    func setCategories(sourceId: String, mangaId: String, categories: [String]) async {
        await CoreDataManager.shared.setMangaCategories(
            sourceId: sourceId,
            mangaId: mangaId,
            categories: categories
        )
        NotificationCenter.default.post(
            name: Notification.Name("updateMangaCategories"),
            object: MangaInfo(mangaId: mangaId, sourceId: sourceId)
        )
    }
}

// MARK: - Library Updating
extension MangaManager {
    nonisolated func register() {
#if !os(macOS) && !targetEnvironment(simulator)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { @Sendable [weak self] task in
            guard let self else { return }

            task.expirationHandler = {
                Task {
                    await self.libraryRefreshTask?.cancel()
                }
                task.setTaskCompleted(success: false)
            }

            Task { @Sendable in
                await self.refreshLibrary(category: self.targetCategory, task: task as? ProgressReporting)

                task.setTaskCompleted(success: true)
            }
        }
#endif
    }

    func scheduleLibraryRefresh() {
        let lastUpdated = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "Library.lastUpdated"))
        let interval: Double = switch UserDefaults.standard.string(forKey: "Library.updateInterval") {
            case "12hours": 43200
            case "daily": 86400
            case "2days": 172800
            case "weekly": 604800
            default: 0
        }
        guard interval > 0 else {
#if !os(macOS) && !targetEnvironment(simulator)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
#endif
            return
        }
        let nextUpdateTime = lastUpdated + interval

        if nextUpdateTime < Date.now {
            // interval time has passed, refresh now
            Task {
                await refreshLibrary()
            }
        } else {
#if !os(macOS) && !targetEnvironment(simulator)
            // schedule task for the future
            let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
            request.earliestBeginDate = nextUpdateTime
            request.requiresExternalPower = false
            request.requiresNetworkConnectivity = true

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                LogManager.logger.error("Could not schedule library refresh: \(error)")
            }
#endif
        }
    }

    func backgroundRefreshLibrary(category: String? = nil, skipReachabilityCheck: Bool = false) async {
        targetCategory = category
        self.skipReachabilityCheck = skipReachabilityCheck

#if !os(macOS) && !targetEnvironment(simulator)
        if #available(iOS 26.0, *), UserDefaults.standard.bool(forKey: "Library.backgroundRefresh"), !ProcessInfo.processInfo.isMacCatalystApp {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.taskIdentifier,
                title: NSLocalizedString("REFRESHING_LIBRARY"),
                subtitle: NSLocalizedString("PROCESSING_ENTRIES")
            )
            do {
                try BGTaskScheduler.shared.submit(request)
                return
            } catch {
                LogManager.logger.error("Failed to start background library refresh: \(error)")
            }
        }
#endif

        await refreshLibrary(category: category)
    }

    /// Refresh manga objects in library.
    func refreshLibrary(
        category: String? = nil,
        forceAll: Bool = false,
        task: (ProgressReporting & Sendable)? = nil
    ) async {
#if !os(macOS)
        let tabController = await UIApplication.shared.firstKeyWindow?.rootViewController as? TabBarController
#endif

        if libraryRefreshTask != nil {
            // wait for already running library refresh
            await libraryRefreshTask?.value
        } else {
            // spawn new library refresh
            libraryRefreshTask = Task {
                await doLibraryRefresh(
                    category: category,
                    skipReachabilityCheck: skipReachabilityCheck,
                    forceAll: forceAll,
                    task: task,
                    refreshStarted: {
#if !os(macOS)
                        await tabController?.showLibraryRefreshView()

                        self.onLibraryRefreshProgress = { progress in
                            tabController?.setLibraryRefreshProgress(Float(progress.fractionCompleted))
                            task?.progress.totalUnitCount = progress.totalUnitCount
                            task?.progress.completedUnitCount = progress.completedUnitCount
                            if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
                                task.updateTitle(
                                    NSLocalizedString("REFRESHING_LIBRARY"),
                                    subtitle: String(format: NSLocalizedString("%i_OF_%i"), progress.completedUnitCount, progress.totalUnitCount)
                                )
                            }
                        }
#endif
                    }
                )
                libraryRefreshTask = nil
            }
            await libraryRefreshTask?.value
        }

        self.targetCategory = nil
        self.skipReachabilityCheck = false

#if !os(macOS)
        // wait 0.5s for final progress animation to complete
        try? await Task.sleep(nanoseconds: 500_000_000)
        await tabController?.hideAccessoryView()
#endif

        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    /// Check if a manga should skip updating based on skip options.
    private func shouldSkip(
        manga: Manga,
        options: [String],
        excludedCategories: [String] = [],
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        // update strategy is never
        if manga.updateStrategy == .never {
            return true
        }
        // next update time hasn't been reached
        if let nextUpdateTime = manga.nextUpdateTime {
            if nextUpdateTime > Date() {
                return true
            }
        }
        // completed
        if options.contains("completed") && manga.status == .completed {
            return true
        }
        // has unread chapters
        if options.contains("hasUnread") && CoreDataManager.shared.unreadCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            lang: manga.langFilter,
            scanlators: manga.scanlatorFilter,
            context: context
        ) > 0 {
            return true
        }
        // has no read chapters
        if options.contains("notStarted") && CoreDataManager.shared.readCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            lang: manga.langFilter,
            scanlators: manga.scanlatorFilter,
            context: context
        ) == 0 {
            return true
        }
        // source is missing
        if SourceManager.shared.source(for: manga.sourceId) == nil {
            return true
        }

        if !excludedCategories.isEmpty {
            // check if excluded via category
            let categories = CoreDataManager.shared.getCategories(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                context: context
            ).compactMap { $0.title }

            if !categories.isEmpty {
                if excludedCategories.contains(where: categories.contains) {
                    return true
                }
            }
        }

        return false
    }

    private func doLibraryRefresh(
        category: String?,
        skipReachabilityCheck: Bool,
        forceAll: Bool,
        task: ProgressReporting? = nil,
        refreshStarted: (() async -> Void)? = nil
    ) async {
        // make sure user agent and sources have loaded before doing library refresh
        _ = await UserAgentProvider.shared.getUserAgent()
        await SourceManager.shared.waitForSourcesLoad()

        // process failed tracker updates first
        await TrackerManager.shared.processPendingUpdates()

        // fetch all library items from db
        let allManga = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getLibraryManga(category: category, context: context).compactMap { $0.manga?.toManga() }
        }

        // ensure there are manga to update
        guard !allManga.isEmpty else {
            return
        }

        // check if connected to wi-fi
        if
            !skipReachabilityCheck,
            UserDefaults.standard.bool(forKey: "Library.updateOnlyOnWifi"),
            Reachability.getConnectionType() != .wifi
        {
            return
        }

        let skipOptions = forceAll ? [] : UserDefaults.standard.stringArray(forKey: "Library.skipTitles") ?? []
        let excludedCategories = forceAll ? [] : (UserDefaults.standard.stringArray(forKey: "Library.excludedUpdateCategories") ?? [])
            .filter { $0 != category }
        let updateMetadata = forceAll || UserDefaults.standard.bool(forKey: "Library.refreshMetadata")

        await refreshStarted?()

        // filter items that we should skip
        let filteredManga = await CoreDataManager.shared.container.performBackgroundTask { context in
            allManga.filter { manga in
                !self.shouldSkip(
                    manga: manga,
                    options: skipOptions,
                    excludedCategories: excludedCategories,
                    context: context
                )
            }
        }

        let total = filteredManga.count
        var completed = 0

        let isBackground = await UIApplication.shared.applicationState != .active
        let notificationsEnabled = isBackground && NotificationManager.shared.isEnabled()
        var pendingNotifications: [NotificationManager.NewChaptersSummary] = []

        let newDetails = await {
            var results: [Int: AidokuRunner.Manga] = [:]
            let progress = Progress(totalUnitCount: Int64(total))

            for manga in filteredManga {
                guard !Task.isCancelled else { return results }

                guard
                    let newManga = try? await SourceManager.shared.source(for: manga.sourceId)?
                        .getMangaUpdate(manga: manga.toNew(), needsDetails: updateMetadata, needsChapters: true)
                else {
                    completed += 1
                    progress.completedUnitCount = Int64(completed)
                    updateLibraryRefreshProgress(progress)
                    continue
                }

                if updateMetadata {
                    results[manga.hashValue] = newManga
                }

                let summary = await CoreDataManager.shared.container.performBackgroundTask { context -> NotificationManager.NewChaptersSummary? in
                    guard
                        let libraryObject = CoreDataManager.shared.getLibraryManga(
                            sourceId: manga.sourceId,
                            mangaId: manga.id,
                            context: context
                        ),
                        let mangaObject = libraryObject.manga
                    else {
                        return nil
                    }

                    // update details
                    if updateMetadata {
                        mangaObject.load(from: newManga)
                    }

                    // update chapters
                    guard let chapters = newManga.chapters, !chapters.isEmpty else { return nil }

                    let newChapters = CoreDataManager.shared.setChapters(
                        chapters,
                        sourceId: manga.sourceId,
                        mangaId: manga.id,
                        context: context
                    )
                    var notifiableCount = 0
                    if !newChapters.isEmpty {
                        // add manga updates
                        let scanlatorFilter = mangaObject.scanlatorFilter ?? []
                        for chapter in newChapters
                        where
                            mangaObject.langFilter != nil ? chapter.lang == mangaObject.langFilter : true
                            && !scanlatorFilter.isEmpty ? scanlatorFilter.contains(chapter.scanlator ?? "") : true
                        {
                            CoreDataManager.shared.createMangaUpdate(
                                sourceId: manga.sourceId,
                                mangaId: manga.id,
                                chapterObject: chapter,
                                context: context
                            )
                            notifiableCount += 1
                        }
                        libraryObject.lastChapter = chapters.compactMap { $0.dateUploaded }.max()
                        libraryObject.lastUpdatedChapters = Date.now
                    }

                    if updateMetadata || !newChapters.isEmpty {
                        libraryObject.lastUpdated = Date.now
                    }

                    if context.hasChanges {
                        try? context.save()
                    }

                    guard notifiableCount > 0 else { return nil }
                    let title = mangaObject.title.isEmpty ? (manga.title ?? "") : mangaObject.title
                    return NotificationManager.NewChaptersSummary(
                        mangaIdentifier: MangaIdentifier(sourceKey: manga.sourceId, mangaKey: manga.id),
                        mangaTitle: title,
                        chapterCount: notifiableCount
                    )
                }

                if notificationsEnabled, let summary {
                    pendingNotifications.append(summary)
                }

                completed += 1
                progress.completedUnitCount = Int64(completed)
                updateLibraryRefreshProgress(progress)
            }

            return results
        }()

        if notificationsEnabled, !pendingNotifications.isEmpty {
            await NotificationManager.shared.notifyNewChapters(pendingNotifications)
        }

        if updateMetadata {
            for mangaItem in filteredManga {
                guard let newInfo = newDetails[mangaItem.hashValue] else { continue }
                mangaItem.load(from: newInfo.toOld())
            }
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Library.lastUpdated")
    }

    private func updateLibraryRefreshProgress(_ progress: Progress) {
        libraryRefreshProgressTask?.cancel()
        libraryRefreshProgressTask = Task {
            // buffer progress updates by 100ms
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await onLibraryRefreshProgress?(progress)
        }
    }
}

// MARK: - Detail Editing
extension MangaManager {
    // sets uploaded cover image and returns the new cover url
    func setCover(manga: AidokuRunner.Manga, cover: PlatformImage) async -> String? {
        if manga.isLocal() {
            return await LocalFileManager.shared.setCover(for: manga.key, image: cover)
        }

        // upload cover image to Documents/Covers/id.png
        let documentsDirectory = FileManager.default.documentDirectory
        let targetDirectory = documentsDirectory.appendingPathComponent("Covers")
        let ext = if #available(iOS 17.0, *) {
            "heic"
        } else {
            "png"
        }
        var targetUrl = targetDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        while targetUrl.exists {
            targetUrl = targetDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        }
        targetDirectory.createDirectory()
        do {
            let data = if #available(iOS 17.0, *) {
#if !os(macOS)
                cover.heicData()
#else
                cover.pngData()
#endif
            } else {
                cover.pngData()
            }
            try data?.write(to: targetUrl)
        } catch {
            LogManager.logger.error("MangaManager.setMangaCover: \(error.localizedDescription)")
            return nil
        }

        // set cover in coredata
        let coverUrl = "aidoku-image:///Covers/\(targetUrl.lastPathComponent)"
        await CoreDataManager.shared.setCover(
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            coverUrl: coverUrl
        )

        return coverUrl
    }

    func resetCover(manga: AidokuRunner.Manga) async -> String? {
        guard let source = SourceManager.shared.source(for: manga.sourceKey) else { return nil }

        // fetch new manga details (for cover)
        let newManga = try? await source.getMangaUpdate(
            manga: manga,
            needsDetails: true,
            needsChapters: false
        )

        guard let cover = newManga?.cover else { return nil }

        // set new cover and get old cover url
        let originalCover = await CoreDataManager.shared.setCover(
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            coverUrl: cover,
            original: true
        )

        // if the original cover is an aidoku image, remove it
        if originalCover != cover, let originalCover, let url = URL(string: originalCover)?.toAidokuFileUrl() {
            url.removeItem()
        }

        return cover
    }
}

// MARK: Migration
extension MangaManager {
    func migrate(
        copy: Bool,
        fromSeries: [AidokuRunner.Manga],
        toSeries: [MangaIdentifier: AidokuRunner.Manga?],
        withChapters: [MangaIdentifier: [AidokuRunner.Chapter]] = [:],
        progressReport: ((Float) -> Void)? = nil
    ) async {
        let newDetails = await fetchNewDetails(
            fromSeries: fromSeries,
            toSeries: toSeries,
            withChapters: withChapters,
            progressReport: { counter in
                if let progressReport {
                    progressReport(Float(counter) / Float(fromSeries.count * 2))
                }
            }
        )

        await withTaskGroup(of: (from: AidokuRunner.Manga, to: AidokuRunner.Manga)?.self) { group in
            let batchSize = 10
            var counter = fromSeries.count

            for i in stride(from: 0, to: fromSeries.count, by: batchSize) {
                let batch = Array(fromSeries[i..<min(i + batchSize, fromSeries.count)])

                for oldManga in batch {
                    group.addTask {
                        guard
                            let details = newDetails[oldManga.key]
                        else { return nil }

                        let newManga = details.0
                        let newChapters = details.1

                        return await Self.migrate(copy: copy, from: oldManga, to: newManga, withChapters: newChapters)
                    }
                }

                for await result in group {
                    counter += 1
                    if let progressReport {
                        progressReport(Float(counter) / Float(fromSeries.count * 2))
                    }
                    if let result {
                        if !copy {
                            await TrackerManager.shared.bindEnhancedTrackers(manga: result.to)
                            NotificationCenter.default.post(name: .migratedManga, object: result)
                        }
                    }
                }
            }
        }
    }

    private static func migrate(
        copy: Bool,
        from oldManga: AidokuRunner.Manga,
        to newManga: AidokuRunner.Manga,
        withChapters newChapters: [AidokuRunner.Chapter],
    ) async -> (AidokuRunner.Manga, AidokuRunner.Manga)? {
        // migrate settings
        if let readingMode = UserDefaults.standard.string(forKey: "Reader.readingMode.\(oldManga.identifier)") {
            UserDefaults.standard.set(readingMode, forKey: "Reader.readingMode.\(newManga.identifier)")
            if !copy {
                UserDefaults.standard.removeObject(forKey: "Reader.readingMode.\(oldManga.identifier)")
            }
        }

        // add new item to library if copying
        if copy {
            let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                let storedNewManga = CoreDataManager.shared.getManga(
                    sourceId: newManga.sourceKey,
                    mangaId: newManga.key,
                    context: context
                )
                guard let storedNewManga else {
                    return false // add to library
                }
                // update details
                storedNewManga.load(from: newManga)
                // update chapters
                CoreDataManager.shared.setChapters(
                    newChapters,
                    sourceId: newManga.sourceKey,
                    mangaId: newManga.key,
                    context: context
                )
                return true
            }
            if !inLibrary {
                await MangaManager.shared.addToLibrary(
                    manga: newManga,
                    chapters: newChapters
                )
            }
        }

        // migrate/copy data
        return await CoreDataManager.shared.container.performBackgroundTask { context in
            do {
                // update manga object in library with new data
                // remove old entry if the new one already exists in library
                if !copy {
                    var mangaObjectToUpdate: MangaObject?

                    // new is already in library
                    if newManga.key != oldManga.key, let storedNewManga = CoreDataManager.shared.getManga(
                        sourceId: newManga.sourceKey,
                        mangaId: newManga.key,
                        context: context
                    ) {
                        // update the object in the library with the new details we fetched already
                        mangaObjectToUpdate = storedNewManga
                        // remove old entry
                        CoreDataManager.shared.removeManga(
                            sourceId: oldManga.sourceKey,
                            mangaId: oldManga.key,
                            context: context
                        )
                    } else {
                        // get existing old object to replace data with new details
                        mangaObjectToUpdate = CoreDataManager.shared.getManga(
                            sourceId: oldManga.sourceKey,
                            mangaId: oldManga.key,
                            context: context
                        )
                    }

                    mangaObjectToUpdate?.load(from: newManga)
                }

                // migrate history
                let storedOldHistory = CoreDataManager.shared.getHistoryForManga(
                    sourceId: oldManga.sourceKey,
                    mangaId: oldManga.key,
                    context: context
                )

                var maxChapterRead = storedOldHistory
                    .compactMap { $0.chapter?.chapter != nil ? $0.chapter : nil }
                    .max { $0.chapter!.decimalValue < $1.chapter!.decimalValue }?
                    .chapter?.floatValue

                if maxChapterRead == nil || maxChapterRead == -1 {
                    // try finding max volume read instead, in case of no chapters
                    maxChapterRead = storedOldHistory
                        .compactMap { $0.chapter?.volume != nil ? $0.chapter : nil }
                        .max { $0.volume!.decimalValue < $1.volume!.decimalValue }?
                        .volume?.floatValue
                }

                // remove old chapters and history
                if !copy {
                    CoreDataManager.shared.removeChapters(
                        sourceId: oldManga.sourceKey,
                        mangaId: oldManga.key,
                        context: context
                    )

                    CoreDataManager.shared.removeHistory(
                        sourceId: oldManga.sourceKey,
                        mangaId: oldManga.key,
                        context: context
                    )

                    // store new chapters
                    CoreDataManager.shared.setChapters(
                        newChapters,
                        sourceId: newManga.sourceKey,
                        mangaId: newManga.key,
                        context: context
                    )
                }

                // mark new chapters as read
                if let maxChapterRead {
                    var chaptersToMark = newChapters.filter({ $0.chapterNumber ?? Float.greatestFiniteMagnitude <= maxChapterRead })
                    if chaptersToMark.isEmpty {
                        // fall back to using volume numbers instead, in case the source we're migrating to uses volumes
                        chaptersToMark = newChapters.filter({ $0.volumeNumber ?? Float.greatestFiniteMagnitude <= maxChapterRead })
                    }
                    if !chaptersToMark.isEmpty {
                        CoreDataManager.shared.setCompleted(
                            sourceId: newManga.sourceKey,
                            mangaId: newManga.key,
                            chapterIds: chaptersToMark.map { $0.key },
                            context: context
                        )
                    }
                }

                // migrate trackers
                let trackItems = CoreDataManager.shared.getTracks(
                    sourceId: oldManga.sourceKey,
                    mangaId: oldManga.key,
                    context: context
                )

                for item in trackItems {
                    guard
                        let trackId = item.id,
                        let trackerId = item.trackerId,
                        !CoreDataManager.shared.hasTrack(
                            trackerId: trackerId,
                            sourceId: newManga.sourceKey,
                            mangaId: newManga.key,
                            context: context
                        ),
                        let tracker = TrackerManager.getTracker(id: trackerId),
                        tracker.canRegister(sourceKey: newManga.sourceKey, mangaKey: newManga.key)
                    else {
                        if !copy && newManga.identifier != oldManga.identifier {
                            context.delete(item)
                        }
                        continue
                    }

                    if copy {
                        CoreDataManager.shared.createTrack(
                            id: trackId,
                            trackerId: trackerId,
                            sourceId: newManga.sourceKey,
                            mangaId: newManga.key,
                            title: item.title,
                            context: context
                        )
                    } else {
                        item.sourceId = newManga.sourceKey
                        item.mangaId = newManga.key
                    }
                }

                try context.save()

                return (from: oldManga, to: newManga)
            } catch {
                LogManager.logger.error("Error migrating manga \(oldManga.key): \(error)")
                return nil
            }
        }
    }

    private func fetchNewDetails(
        fromSeries: [AidokuRunner.Manga],
        toSeries: [MangaIdentifier: AidokuRunner.Manga?],
        withChapters: [MangaIdentifier: [AidokuRunner.Chapter]],
        progressReport: (Int) -> Void
    ) async -> [String: (AidokuRunner.Manga, [AidokuRunner.Chapter])] {
        await withTaskGroup(
            of: (String, AidokuRunner.Manga, [AidokuRunner.Chapter])?.self,
            returning: [String: (AidokuRunner.Manga, [AidokuRunner.Chapter])].self
        ) { group in
            let batchSize = 10
            var ret: [String: (AidokuRunner.Manga, [AidokuRunner.Chapter])] = [:]
            var counter = 0

            for i in stride(from: 0, to: fromSeries.count, by: batchSize) {
                let batch = Array(fromSeries[i..<min(i + batchSize, fromSeries.count)])

                for oldManga in batch {
                    group.addTask {
                        guard
                            let newManga = toSeries[oldManga.identifier],
                            let newManga,
                            let source = SourceManager.shared.source(for: newManga.sourceKey)
                        else { return nil }

                        let newChapters = withChapters[oldManga.identifier]

                        let updatedManga = try? await source.getMangaUpdate(
                            manga: newManga,
                            needsDetails: true,
                            needsChapters: newChapters == nil
                        )

                        let mangaDetails = updatedManga ?? newManga
                        let chapters = newChapters ?? updatedManga?.chapters ?? []

                        return (oldManga.key, mangaDetails, chapters)
                    }
                }

                // wait for all results in batch to finish before continuing
                for await result in group {
                    counter += 1
                    progressReport(counter)
                    if let result {
                        ret[result.0] = (result.1, result.2)
                    }
                }
            }

            return ret
        }
    }
}
