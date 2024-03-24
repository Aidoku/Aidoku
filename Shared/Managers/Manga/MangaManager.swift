//
//  MangaManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import CoreData

class MangaManager {

    static let shared = MangaManager()

    private var libraryRefreshTask: Task<(), Never>?
}

// MARK: - Library Managing
extension MangaManager {

    func addToLibrary(manga: Manga, chapters: [Chapter] = [], fetchMangaDetails: Bool = false) async {
        var manga = manga
        var chapters = chapters
        // update manga or chapters
        if fetchMangaDetails || chapters.isEmpty {
            if let source = SourceManager.shared.source(for: manga.sourceId) {
                if fetchMangaDetails {
                    manga = (try? await source.getMangaDetails(manga: manga)) ?? manga
                }
                if chapters.isEmpty {
                    chapters = (try? await source.getChapterList(manga: manga)) ?? []
                }
            }
        }
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.addToLibrary(manga: manga, chapters: chapters, context: context)
            // add to default category
            if let defaultCategory = UserDefaults.standard.stringArray(forKey: "Library.defaultCategory")?.first {
                let hasCategory = CoreDataManager.shared.hasCategory(title: defaultCategory, context: context)
                if hasCategory {
                    CoreDataManager.shared.addCategoriesToManga(
                        sourceId: manga.sourceId,
                        mangaId: manga.id,
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
        NotificationCenter.default.post(name: Notification.Name("addToLibrary"), object: manga)
        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
    }

    func removeFromLibrary(sourceId: String, mangaId: String) async {
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
        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
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
        // completed
        if options.contains("completed") && manga.status == .completed {
            return true
        }
        // has unread chapters
        if options.contains("hasUnread") && CoreDataManager.shared.unreadCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            lang: manga.langFilter,
            context: context
        ) > 0 {
            return true
        }
        // has no read chapters
        if options.contains("notStarted") && CoreDataManager.shared.readCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            lang: manga.langFilter,
            context: context
        ) == 0 {
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
                            .getMangaDetails(manga: mangaItem)
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
    func refreshLibrary(category: String? = nil, forceAll: Bool = false) async {
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

        await withTaskGroup(of: Void.self) { group in
            for manga in allManga {
                group.addTask {
                    let shouldSkip = await CoreDataManager.shared.container.performBackgroundTask { context in
                        self.shouldSkip(
                            manga: manga,
                            options: skipOptions,
                            excludedCategories: excludedCategories,
                            context: context
                        )
                    }
                    guard
                        !shouldSkip,
                        let chapters = try? await SourceManager.shared.source(for: manga.sourceId)?
                            .getChapterList(manga: manga)
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
                                for chapter in newChapters
                                where mangaObject.langFilter != nil ? chapter.lang == mangaObject.langFilter : true
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
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Library.lastUpdated")
    }
}
