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
}

// MARK: - Library Managing
extension MangaManager {
    func addToLibrary(
        sourceId: String,
        manga: AidokuRunner.Manga,
        chapters: [AidokuRunner.Chapter] = [],
        fetchMangaDetails: Bool = false
    ) async {
        var manga = manga
        var chapters = chapters
        // update manga or chapters
        if fetchMangaDetails || chapters.isEmpty {
            if let source = SourceManager.shared.source(for: sourceId) {
                manga = (try? await source.getMangaUpdate(manga: manga, needsDetails: fetchMangaDetails, needsChapters: chapters.isEmpty)) ?? manga
                chapters = manga.chapters ?? chapters
            }
        }
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.addToLibrary(
                sourceId: sourceId,
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
                        sourceId: sourceId,
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

        NotificationCenter.default.post(
            name: .addToLibrary,
            object: manga.toOld()
        )
        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
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
        manga: Manga, chapters: [Chapter], trackItems: [TrackItem], categories: [String]
    ) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.addToLibrary(
                sourceId: manga.sourceId,
                manga: manga.toNew(),
                chapters: chapters.map { $0.toNew() },
                context: context
            )

            if let libraryObject = CoreDataManager.shared.getLibraryManga(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                context: context
            ) {
                if let lastOpened = manga.lastOpened, let lastUpdated = manga.lastUpdated,
                   let dateAdded = manga.dateAdded
                {
                    libraryObject.lastOpened = lastOpened
                    libraryObject.lastUpdated = lastUpdated
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

    func backgroundRefreshLibrary(category: String? = nil) async {
        targetCategory = category

#if !os(macOS) && !targetEnvironment(simulator)
        if #available(iOS 26.0, *), UserDefaults.standard.bool(forKey: "Library.backgroundRefresh") {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.taskIdentifier,
                title: NSLocalizedString("REFRESHING_LIBRARY"),
                subtitle: NSLocalizedString("PROCESSING_ENTRIES")
            )
            do {
                try BGTaskScheduler.shared.submit(request)
                return
            } catch {
                LogManager.logger.error("Failed to start background downloading: \(error)")
            }
        }
#endif

        await refreshLibrary(category: category)
    }

    /// Refresh manga objects in library.
    func refreshLibrary(
        category: String? = nil,
        forceAll: Bool = false,
        task: ProgressReporting? = nil
    ) async {
#if !os(macOS)
        let tabController = await UIApplication.shared.firstKeyWindow?.rootViewController as? TabBarController
        await tabController?.showLibraryRefreshView()

        onLibraryRefreshProgress = { progress in
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

        if libraryRefreshTask != nil {
            // wait for already running library refresh
            await libraryRefreshTask?.value
        } else {
            // spawn new library refresh
            libraryRefreshTask = Task {
                await doLibraryRefresh(category: category, forceAll: forceAll, task: task)
                libraryRefreshTask = nil
            }
            await libraryRefreshTask?.value
        }

        self.targetCategory = nil

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
        forceAll: Bool,
        task: ProgressReporting? = nil
    ) async {
        // make sure user agent has loaded before doing library refresh
        _ = await UserAgentProvider.shared.getUserAgent()

        let allManga = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getLibraryManga(category: category, context: context).compactMap { $0.manga?.toManga() }
        }

        // check if connected to wi-fi
        if UserDefaults.standard.bool(forKey: "Library.updateOnlyOnWifi") && Reachability.getConnectionType() != .wifi {
            return
        }

        let skipOptions = forceAll ? [] : UserDefaults.standard.stringArray(forKey: "Library.skipTitles") ?? []
        let excludedCategories = forceAll ? [] : UserDefaults.standard.stringArray(forKey: "Library.excludedUpdateCategories") ?? []
        let updateMetadata = forceAll || UserDefaults.standard.bool(forKey: "Library.refreshMetadata")

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

        let newDetails = await withTaskGroup(
            of: (Int, AidokuRunner.Manga)?.self,
            returning: [Int: AidokuRunner.Manga].self
        ) { group in
            for manga in filteredManga {
                group.addTask {
                    guard
                        !Task.isCancelled,
                        let newManga = try? await SourceManager.shared.source(for: manga.sourceId)?
                            .getMangaUpdate(manga: manga.toNew(), needsDetails: updateMetadata, needsChapters: true)
                    else {
                        return nil
                    }

                    let returnResult: (Int, AidokuRunner.Manga)? = if updateMetadata {
                        (manga.hashValue, newManga)
                    } else {
                        nil
                    }

                    guard let chapters = newManga.chapters else { return returnResult }

                    await CoreDataManager.shared.container.performBackgroundTask { context in
                        guard let libraryObject = CoreDataManager.shared.getLibraryManga(
                            sourceId: manga.sourceId,
                            mangaId: manga.id,
                            context: context
                        ) else {
                            return
                        }

                        // update manga object
                        if let mangaObject = libraryObject.manga {
                            // update details
                            if updateMetadata {
                                mangaObject.load(from: manga)
                            }

                            // update chapter list
                            if mangaObject.chapters?.count != chapters.count && !chapters.isEmpty {
                                let newChapters = CoreDataManager.shared.setChapters(
                                    chapters,
                                    sourceId: manga.sourceId,
                                    mangaId: manga.id,
                                    context: context
                                )
                                // update manga updates
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
                                }
                                libraryObject.lastUpdated = Date()
                                try? context.save()
                            }
                        }
                    }

                    return returnResult
                }
            }

            var results: [Int: AidokuRunner.Manga] = [:]
            let progress = Progress(totalUnitCount: Int64(total))
            for await result in group {
                guard !Task.isCancelled else { return results }
                completed += 1
                progress.completedUnitCount = Int64(completed)
                updateLibraryRefreshProgress(progress)
                if let result {
                    results[result.0] = result.1
                }
            }
            return results
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
