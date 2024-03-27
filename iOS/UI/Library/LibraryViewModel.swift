//
//  LibraryViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/25/22.
//

import Foundation
import CoreData

class LibraryViewModel {

    var manga: [MangaInfo] = []
    var pinnedManga: [MangaInfo] = []

    // temporary storage when searching
    private var storedManga: [MangaInfo]?
    private var storedPinnedManga: [MangaInfo]?

    enum PinType {
        case none
        case unread
        case updated
    }

    enum SortMethod: Int {
        case alphabetical = 0
        case lastRead
        case lastOpened
        case lastUpdated
        case dateAdded
        case unreadChapters
        case totalChapters

        var sortStringValue: String {
            switch self {
            case .alphabetical: "manga.title"
            case .lastRead: "lastRead"
            case .lastOpened: "lastOpened"
            case .lastUpdated: "lastUpdated"
            case .dateAdded: "dateAdded"
            case .unreadChapters: ""
            case .totalChapters: "manga.chapterCount"
            }
        }
    }

    enum BadgeType {
        case none
        case unread
    }

    struct LibraryFilter {
        var type: FilterMethod
        var exclude: Bool
    }

    enum FilterMethod: Int {
        case downloaded = 0
        case tracking
    }

    lazy var pinType: PinType = getPinType()
    lazy var sortMethod = SortMethod(rawValue: UserDefaults.standard.integer(forKey: "Library.sortOption")) ?? .lastOpened
    lazy var sortAscending = UserDefaults.standard.bool(forKey: "Library.sortAscending")
    lazy var badgeType: BadgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

    var filters: [LibraryFilter] = []

    var categories: [String] = []
    lazy var currentCategory: String? = UserDefaults.standard.string(forKey: "Library.currentCategory") {
        didSet {
            UserDefaults.standard.set(currentCategory, forKey: "Library.currentCategory")
        }
    }

    func isCategoryLocked() -> Bool {
        guard UserDefaults.standard.bool(forKey: "Library.lockLibrary") else { return false }
        if let currentCategory = currentCategory {
            return UserDefaults.standard.stringArray(forKey: "Library.lockedCategories")?.contains(currentCategory) ?? false
        }
        return true
    }

    func getPinType() -> PinType {
        if UserDefaults.standard.bool(forKey: "Library.pinManga") {
            switch UserDefaults.standard.integer(forKey: "Library.pinMangaType") {
            case 0: return .unread
            case 1: return .updated
            default: return .none
            }
        } else {
            return .none
        }
    }

    func refreshCategories() async {
        categories = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getCategories(context: context).map { $0.title ?? "" }
        }
        if currentCategory != nil && !categories.contains(currentCategory!) {
            currentCategory = nil
            await loadLibrary()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func loadLibrary() async {
        var pinnedManga: [MangaInfo] = []
        var manga: [MangaInfo] = []

        var checkDownloads = false
        var excludeDownloads = false

        await CoreDataManager.shared.container.performBackgroundTask { context in
            let request = LibraryMangaObject.fetchRequest()
            if let currentCategory = self.currentCategory {
                request.predicate = NSPredicate(format: "manga != nil AND ANY categories.title == %@", currentCategory)
            } else {
                request.predicate = NSPredicate(format: "manga != nil")
            }
            if self.sortMethod != .unreadChapters {
                request.sortDescriptors = [
                    NSSortDescriptor(
                        key: self.sortMethod.sortStringValue,
                        ascending: self.sortMethod == .alphabetical ? !self.sortAscending : self.sortAscending
                    )
                ]
            }
            guard let libraryObjects = try? context.fetch(request) else { return }

            var ids = Set<String>()

            main: for libraryObject in libraryObjects {
                guard
                    let mangaObject = libraryObject.manga,
                    // ensure the manga hasn't already been accounted for
                    ids.insert("\(mangaObject.sourceId)|\(mangaObject.id)").inserted
                else { continue }

                let unreadCount = CoreDataManager.shared.unreadCount(
                    sourceId: mangaObject.sourceId,
                    mangaId: mangaObject.id,
                    lang: mangaObject.langFilter,
                    context: context
                )

                let info = MangaInfo(
                    mangaId: mangaObject.id,
                    sourceId: mangaObject.sourceId,
                    coverUrl: mangaObject.cover != nil ? URL(string: mangaObject.cover!) : nil,
                    title: mangaObject.title,
                    author: mangaObject.author,
                    url: mangaObject.url != nil ? URL(string: mangaObject.url!) : nil,
                    unread: unreadCount
                )

                // process filters
                for filter in self.filters {
                    let condition: Bool
                    switch filter.type {
                    case .downloaded:
                        checkDownloads = true
                        excludeDownloads = filter.exclude
                        continue
                    case .tracking:
                        condition = TrackerManager.shared.isTracking(sourceId: info.sourceId, mangaId: info.mangaId)
                    }
                    let shouldSkip = filter.exclude ? condition : !condition
                    if shouldSkip {
                        continue main
                    }
                }

                switch self.pinType {
                case .none:
                    manga.append(info)
                case .unread:
                    if info.unread > 0 {
                        pinnedManga.append(info)
                    } else {
                        manga.append(info)
                    }
                case .updated:
                    if libraryObject.lastUpdated > libraryObject.lastOpened {
                        pinnedManga.append(info)
                    } else {
                        manga.append(info)
                    }
                }
            }
        }

        if checkDownloads {
            let pinnedMangaCopy = pinnedManga
            let mangaCopy = manga
            let exclude = excludeDownloads
            (pinnedManga, manga) = await MainActor.run {
                (
                    pinnedMangaCopy.filter { info in
                        let condition = DownloadManager.shared.hasDownloadedChapter(sourceId: info.sourceId, mangaId: info.mangaId)
                        return exclude ? !condition : condition
                    },
                    mangaCopy.filter { info in
                        let condition = DownloadManager.shared.hasDownloadedChapter(sourceId: info.sourceId, mangaId: info.mangaId)
                        return exclude ? !condition : condition
                    }
                )
            }
        }

        self.pinnedManga = pinnedManga
        self.manga = manga

        if sortMethod == .unreadChapters {
            await sortLibrary()
        }
    }

    // updates unread counts and manga sort order for history change
    func updateHistory(for manga: [MangaInfo], read: Bool) async {
        let currentManga = self.manga + self.pinnedManga
        let unreadCounts = await withTaskGroup(of: (Int, Int)?.self, returning: [Int: Int].self) { group in
            for item in manga {
                group.addTask {
                    func getUnreadCount() async -> Int {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            let filters = CoreDataManager.shared.getMangaChapterFilters(
                                sourceId: item.sourceId,
                                mangaId: item.mangaId,
                                context: context
                            )
                            return CoreDataManager.shared.unreadCount(
                                sourceId: item.sourceId,
                                mangaId: item.mangaId,
                                lang: filters.language,
                                context: context
                            )
                        }
                    }
                    if let manga = currentManga.first(where: {
                        $0.mangaId == item.mangaId && $0.sourceId == item.sourceId
                    }) {
                        return (manga.hashValue, await getUnreadCount())
                    } else {
                        return nil
                    }
                }
            }
            var ret: [Int: Int] = [:]
            for await result in group {
                guard let result = result else { continue }
                ret[result.0] = result.1
            }
            return ret
        }
        for count in unreadCounts {
            if let pinnedIndex = pinnedManga.firstIndex(where: { $0.hashValue == count.key }) {
                pinnedManga[pinnedIndex].unread = count.value
                if read && sortMethod == .lastRead && pinnedIndex != 0 {
                    let manga = pinnedManga.remove(at: pinnedIndex)
                    pinnedManga.insert(manga, at: 0)
                }
            } else if let mangaIndex = self.manga.firstIndex(where: { $0.hashValue == count.key }) {
                self.manga[mangaIndex].unread = count.value
                if read && sortMethod == .lastRead && mangaIndex != 0 {
                    let manga = self.manga.remove(at: mangaIndex)
                    self.manga.insert(manga, at: 0)
                }
            }
        }
        if pinType == .unread {
            await loadLibrary()
        } else if sortMethod == .unreadChapters {
            await sortLibrary()
        }
    }

    func fetchUnreads() async {
        var unreadCounts: [Int: Int] = [:]
        let currentManga = self.manga + self.pinnedManga
        // fetch new unread counts
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for manga in currentManga {
                let filters = CoreDataManager.shared.getMangaChapterFilters(
                    sourceId: manga.sourceId,
                    mangaId: manga.mangaId,
                    context: context
                )
                unreadCounts[manga.hashValue] = CoreDataManager.shared.unreadCount(
                    sourceId: manga.sourceId,
                    mangaId: manga.mangaId,
                    lang: filters.language,
                    context: context
                )
            }
        }
        // set unread counts
        for (i, manga) in self.manga.enumerated() {
            guard let count = unreadCounts[manga.hashValue] else { continue }
            self.manga[i].unread = count
        }
        for (i, manga) in self.pinnedManga.enumerated() {
            guard let count = unreadCounts[manga.hashValue] else { continue }
            self.pinnedManga[i].unread = count
        }
        // re-sort library if needed
        if pinType == .unread {
            await loadLibrary()
        } else if sortMethod == .unreadChapters {
            await sortLibrary()
        }
    }

    func sortLibrary() async {
        switch sortMethod {
        case .alphabetical:
            if sortAscending {
                pinnedManga.sort { $0.title ?? "" > $1.title ?? "" }
                manga.sort { $0.title ?? "" > $1.title ?? "" }
            } else {
                pinnedManga.sort { $0.title ?? "" < $1.title ?? "" }
                manga.sort { $0.title ?? "" < $1.title ?? "" }
            }

        case .unreadChapters:
            if sortAscending {
                pinnedManga.sort {
                    if $0.unread == 0 {
                        false
                    } else if $1.unread == 0 {
                        true
                    } else {
                        $0.unread < $1.unread
                    }
                }
                manga.sort {
                    if $0.unread == 0 {
                        false
                    } else if $1.unread == 0 {
                        true
                    } else {
                        $0.unread < $1.unread
                    }
                }
            } else {
                pinnedManga.sort { $0.unread > $1.unread }
                manga.sort { $0.unread > $1.unread }
            }

        default:
            await loadLibrary()
        }
    }

    func toggleSort(method: SortMethod) async {
        if sortMethod == method {
            sortAscending.toggle()
        } else {
            sortMethod = method
            sortAscending = false
            UserDefaults.standard.set(sortMethod.rawValue, forKey: "Library.sortOption")
        }

        UserDefaults.standard.set(sortAscending, forKey: "Library.sortAscending")

        await sortLibrary()
    }

    func toggleFilter(method: FilterMethod) async {
        let filterIndex = filters.firstIndex(where: { $0.type == method })
        if let filterIndex = filterIndex {
            if filters[filterIndex].exclude {
                filters.remove(at: filterIndex)
            } else {
                filters[filterIndex].exclude = true
            }
        } else {
            filters.append(LibraryFilter(type: method, exclude: false))
        }
        await loadLibrary()
    }

    func search(query: String) async {
        guard !query.isEmpty else {
            var shouldResort = false
            if let storedManga = storedManga {
                manga = storedManga
                self.storedManga = nil
                shouldResort = true
            }
            if let storedPinnedManga = storedPinnedManga {
                pinnedManga = storedPinnedManga
                self.storedPinnedManga = nil
                shouldResort = true
            }
            if shouldResort {
                await sortLibrary()
            }
            return
        }
        if storedManga == nil {
            storedManga = manga
            storedPinnedManga = pinnedManga
        }
        guard let storedManga = storedManga, let storedPinnedManga = storedPinnedManga else {
            return
        }

        let query = query.lowercased()
        pinnedManga = storedPinnedManga.filter { $0.title?.lowercased().contains(query) ?? false }
        manga = storedManga.filter { $0.title?.lowercased().fuzzyMatch(query) ?? false || $0.author?.lowercased().fuzzyMatch(query) ?? false }
    }

    func mangaOpened(sourceId: String, mangaId: String) async {
        guard sortMethod == .lastOpened || pinType == .updated else { return }

        let pinnedIndex = pinnedManga.firstIndex(where: { $0.mangaId == mangaId && $0.sourceId == sourceId })
        if let pinnedIndex = pinnedIndex {
            if sortMethod == .lastOpened {
                let manga = pinnedManga.remove(at: pinnedIndex)
                if pinType == .updated {
                    self.manga.insert(manga, at: 0)
                } else {
                    pinnedManga.insert(manga, at: 0)
                }
            } else {
                await loadLibrary() // don't know where to put in manga array, just refresh
            }
        } else if sortMethod == .lastOpened {
            let index = manga.firstIndex(where: { $0.mangaId == mangaId && $0.sourceId == sourceId })
            if let index = index {
                let manga = manga.remove(at: index)
                self.manga.insert(manga, at: 0)
            }
        }
    }

    func mangaRead(sourceId: String, mangaId: String) {
        guard sortMethod == .lastRead else { return }
        if let pinnedIndex = pinnedManga.firstIndex(where: { $0.mangaId == mangaId && $0.sourceId == sourceId }) {
            let manga = pinnedManga.remove(at: pinnedIndex)
            self.manga.insert(manga, at: 0)
        } else if let index = manga.firstIndex(where: { $0.mangaId == mangaId && $0.sourceId == sourceId }) {
            let manga = manga.remove(at: index)
            self.manga.insert(manga, at: 0)
        }
    }

    func removeFromLibrary(manga: MangaInfo) async {
        pinnedManga.removeAll { $0.mangaId == manga.mangaId && $0.sourceId == manga.sourceId }
        self.manga.removeAll { $0.mangaId == manga.mangaId && $0.sourceId == manga.sourceId }
        await MangaManager.shared.removeFromLibrary(sourceId: manga.sourceId, mangaId: manga.mangaId)
    }

    func removeFromCurrentCategory(manga: MangaInfo) async {
        guard let currentCategory = currentCategory else { return }
        pinnedManga.removeAll { $0.mangaId == manga.mangaId && $0.sourceId == manga.sourceId }
        self.manga.removeAll { $0.mangaId == manga.mangaId && $0.sourceId == manga.sourceId }
        await CoreDataManager.shared.removeCategoriesFromManga(
            sourceId: manga.sourceId,
            mangaId: manga.mangaId,
            categories: [currentCategory]
        )
    }

    func shouldUpdateLibrary() -> Bool {
        let lastUpdated = UserDefaults.standard.double(forKey: "Library.lastUpdated")
        let interval: Double = [
            "never": Double(-1),
            "12hours": 43200,
            "daily": 86400,
            "2days": 172800,
            "weekly": 604800
        ][UserDefaults.standard.string(forKey: "Library.updateInterval")] ?? Double(0)
        guard interval > 0 else { return false }
        if Date().timeIntervalSince1970 - lastUpdated > interval {
            return true
        }
        return false
    }
}
