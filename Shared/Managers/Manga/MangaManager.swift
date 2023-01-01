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

// MARK: - Library Updating
extension MangaManager {

    /// Check if a manga should skip updating based on skip options.
    private func shouldSkip(manga: Manga, options: [String], context: NSManagedObjectContext? = nil) -> Bool {
        // completed
        if options.contains("completed") && manga.status == .completed {
            return true
        }
        // has unread chapters
        if options.contains("hasUnread") && CoreDataManager.shared.unreadCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            context: context
        ) > 0 {
            return true
        }
        // has no read chapters
        if options.contains("notStarted") && CoreDataManager.shared.readCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            context: context
        ) == 0 {
            return true
        }

        return false
    }

    /// Get the latest chapters for all manga in the array, indexed by manga.key.
    private func getLatestChapters(manga: [Manga], skipOptions: [String] = []) async -> [String: [Chapter]] {
        await withTaskGroup(
            of: (String, [Chapter]).self,
            returning: [String: [Chapter]].self,
            body: { taskGroup in
                for mangaItem in manga {
                    if shouldSkip(manga: mangaItem, options: skipOptions) {
                        continue
                    }
                    taskGroup.addTask {
                        let chapters = try? await SourceManager.shared.source(for: mangaItem.sourceId)?
                            .getChapterList(manga: mangaItem)
                        return (mangaItem.key, chapters ?? [])
                    }
                }

                var results: [String: [Chapter]] = [:]
                for await result in taskGroup {
                    results[result.0] = result.1
                }
                return results
            }
        )
    }

    /// Update properties on manga from latest source info.
    func updateMangaDetails(manga: [Manga]) async {
        for mangaItem in manga {
            guard
                let newInfo = try? await SourceManager.shared.source(for: mangaItem.sourceId)?
                    .getMangaDetails(manga: mangaItem)
            else { continue }
            mangaItem.load(from: newInfo)
        }
    }

    /// Refresh manga objects in library.
    func refreshLibrary(forceAll: Bool = false) async {
        if libraryRefreshTask != nil {
            // wait for already running library refresh
            await libraryRefreshTask?.value
            libraryRefreshTask = nil
        } else {
            // spawn new library refresh
            libraryRefreshTask = Task {
                await doLibraryRefresh(forceAll: forceAll)
                libraryRefreshTask = nil
            }
        }
    }

    private func doLibraryRefresh(forceAll: Bool) async {
        let allManga = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getLibraryManga(context: context).compactMap { $0.manga?.toManga() }
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

        // fetch new chapters
        let newChapters = await getLatestChapters(manga: allManga, skipOptions: skipOptions)

        await CoreDataManager.shared.container.performBackgroundTask { context in
            for manga in allManga {
                guard let chapters = newChapters[manga.key] else { continue }

                guard let libraryObject = CoreDataManager.shared.getLibraryManga(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    context: context
                ) else {
                    continue
                }

                // check if excluded via category
                if !excludedCategories.isEmpty {
                    let categories = CoreDataManager.shared.getCategories(
                        libraryManga: libraryObject
                    ).compactMap { $0.title }

                    if !categories.isEmpty {
                        if excludedCategories.contains(where: categories.contains) {
                            continue
                        }
                    }
                }

                // update manga object
                if let mangaObject = libraryObject.manga {
                    // update details
                    if updateMetadata {
                        mangaObject.load(from: manga)
                    }

                    // update chapter list
                    if mangaObject.chapters?.count != chapters.count && !chapters.isEmpty {
                        CoreDataManager.shared.setChapters(
                            chapters,
                            sourceId: manga.sourceId,
                            mangaId: manga.id,
                            context: context
                        )
                        libraryObject.lastUpdated = Date()
                    }
                }
            }

            // save changes (runs on main thread)
            if context.hasChanges {
                try? context.save()
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Library.lastUpdated")
        }
    }
}
