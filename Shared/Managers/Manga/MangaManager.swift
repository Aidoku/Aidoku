//
//  MangaManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import AidokuRunner
import CoreData
import Nuke

class MangaManager {
    static let shared = MangaManager()

    private var libraryRefreshTask: Task<(), Never>?
    private var libraryRefreshProgressTask: Task<(), Never>?
    private var onLibraryRefreshProgress: ((Float) -> Void)?
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

    /// Update properties on manga from latest source info.
    func updateMangaDetails(manga: [Manga]) async {
        let newDetails = await withTaskGroup(
            of: (Int, Manga)?.self,
            returning: [Int: Manga].self
        ) { taskGroup in
            for mangaItem in manga {
                taskGroup.addTask {
                    guard
                        let newInfo = try? await SourceManager.shared.source(for: mangaItem.sourceId)?
                            .getMangaUpdate(manga: mangaItem.toNew(), needsDetails: true, needsChapters: false)
                            .toOld()
                    else { return nil }
                    return (mangaItem.hashValue, newInfo)
                }
            }

            var results: [Int: Manga] = [:]
            for await result in taskGroup {
                guard let result = result else { continue }
                results[result.0] = result.1
            }
            return results
        }
        for mangaItem in manga {
            guard let newInfo = newDetails[manga.hashValue] else { return }
            mangaItem.load(from: newInfo)
        }
    }

    /// Refresh manga objects in library.
    func refreshLibrary(category: String? = nil, forceAll: Bool = false, onProgress: ((Float) -> Void)? = nil) async {
        onLibraryRefreshProgress = onProgress
        if libraryRefreshTask != nil {
            // wait for already running library refresh
            await libraryRefreshTask?.value
        } else {
            // spawn new library refresh
            libraryRefreshTask = Task {
                await doLibraryRefresh(category: category, forceAll: forceAll)
                libraryRefreshTask = nil
            }
            await libraryRefreshTask?.value
        }
    }

    private func doLibraryRefresh(category: String?, forceAll: Bool) async {
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

        // fetch new details
        if updateMetadata {
            await updateMangaDetails(manga: allManga)
        }

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

        await withTaskGroup(of: Void.self) { group in
            for manga in filteredManga {
                group.addTask {
                    guard
                        let chapters = try? await SourceManager.shared.source(for: manga.sourceId)?
                            .getMangaUpdate(manga: manga.toNew(), needsDetails: false, needsChapters: true)
                            .chapters
                    else { return }

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
                }
            }

            for await _ in group {
                completed += 1
                let progress = Float(completed) / Float(total)
                updateLibraryRefreshProgress(progress)
            }
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Library.lastUpdated")
    }

    private func updateLibraryRefreshProgress(_ progress: Float) {
        libraryRefreshProgressTask?.cancel()
        libraryRefreshProgressTask = Task {
            // buffer progress updates by 100ms
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onLibraryRefreshProgress?(progress)
            }
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
