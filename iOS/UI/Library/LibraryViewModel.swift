//
//  LibraryViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/25/22.
//

import AidokuRunner
import CoreData
import UIKit

@MainActor
class LibraryViewModel {
    var manga: [MangaInfo] = []
    var pinnedManga: [MangaInfo] = []
    var sourceKeys: [String] = []

    // temporary storage when searching
    private var storedManga: [MangaInfo]?
    private var storedPinnedManga: [MangaInfo]?

    enum PinType: String, CaseIterable {
        case none
        case unread
        case updatedChapters

        var title: String {
            switch self {
                case .none: NSLocalizedString("PIN_DISABLED")
                case .unread: NSLocalizedString("PIN_UNREAD")
                case .updatedChapters: NSLocalizedString("PIN_UPDATED_CHAPTERS")
            }
        }

        var needsUpdateOnContentOpen: Bool {
            switch self {
                case .none: false
                case .unread: false
                case .updatedChapters: true
            }
        }
    }

    enum SortMethod: Int, CaseIterable {
        case alphabetical = 0
        case lastRead
        case lastOpened
        case lastUpdated
        case dateAdded
        case lastChapter
        case unreadChapters
        case totalChapters

        var title: String {
            switch self {
                case .alphabetical: NSLocalizedString("TITLE")
                case .lastRead: NSLocalizedString("LAST_READ")
                case .lastOpened: NSLocalizedString("LAST_OPENED")
                case .lastUpdated: NSLocalizedString("LAST_UPDATED")
                case .dateAdded: NSLocalizedString("DATE_ADDED")
                case .lastChapter: NSLocalizedString("LATEST_CHAPTER")
                case .unreadChapters: NSLocalizedString("UNREAD_CHAPTERS")
                case .totalChapters: NSLocalizedString("TOTAL_CHAPTERS")
            }
        }

        var descendingTitle: String {
            switch self {
                case .alphabetical: NSLocalizedString("ASCENDING") // reverse default for alphabetical sort
                case .lastRead: NSLocalizedString("NEWEST_FIRST")
                case .lastOpened: NSLocalizedString("NEWEST_FIRST")
                case .lastUpdated: NSLocalizedString("NEWEST_FIRST")
                case .dateAdded: NSLocalizedString("NEWEST_FIRST")
                case .lastChapter: NSLocalizedString("NEWEST_FIRST")
                case .unreadChapters: NSLocalizedString("HIGHEST_FIRST")
                case .totalChapters: NSLocalizedString("HIGHEST_FIRST")
            }
        }

        var ascendingTitle: String {
            switch self {
                case .alphabetical: NSLocalizedString("DESCENDING")
                case .lastRead: NSLocalizedString("OLDEST_FIRST")
                case .lastOpened: NSLocalizedString("OLDEST_FIRST")
                case .lastUpdated: NSLocalizedString("OLDEST_FIRST")
                case .dateAdded: NSLocalizedString("OLDEST_FIRST")
                case .lastChapter: NSLocalizedString("OLDEST_FIRST")
                case .unreadChapters: NSLocalizedString("LOWEST_FIRST")
                case .totalChapters: NSLocalizedString("LOWEST_FIRST")
            }
        }

        var sortStringValue: String {
            switch self {
                case .alphabetical: "manga.title"
                case .lastRead: "lastRead"
                case .lastOpened: "lastOpened"
                case .lastUpdated: "lastUpdated"
                case .dateAdded: "dateAdded"
                case .lastChapter: "lastChapter"
                case .unreadChapters: ""
                case .totalChapters: "manga.chapterCount"
            }
        }
    }

    struct BadgeType: OptionSet {
        let rawValue: Int

        static let unread = BadgeType(rawValue: 1 << 0)
        static let downloaded = BadgeType(rawValue: 1 << 1)
    }

    struct LibraryFilter: Codable {
        var type: FilterMethod
        var value: String?
        var exclude: Bool
    }

    enum FilterMethod: Int, Codable, CaseIterable {
        case downloaded
        case tracking
        case hasUnread
        case started
        case completed
        case source
        case contentRating

        var title: String {
            switch self {
                case .downloaded: NSLocalizedString("DOWNLOADED")
                case .tracking: NSLocalizedString("IS_TRACKING")
                case .hasUnread: NSLocalizedString("FILTER_HAS_UNREAD")
                case .started: NSLocalizedString("FILTER_STARTED")
                case .completed: NSLocalizedString("COMPLETED")
                case .source: NSLocalizedString("SOURCES")
                case .contentRating: NSLocalizedString("CONTENT_RATING")
            }
        }

        var image: UIImage? {
            let name = switch self {
                case .downloaded: "arrow.down.circle"
                case .tracking: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
                case .hasUnread: "eye.slash"
                case .started: "clock"
                case .completed: "checkmark.circle"
                case .source: "globe"
                case .contentRating: "exclamationmark.triangle.fill"
            }
            return UIImage(systemName: name)
        }

        var isAvailable: Bool {
            switch self {
                case .tracking: TrackerManager.hasAvailableTrackers
                case .source, .contentRating: false // needs custom handling
                default: true
            }
        }
    }

    lazy var pinType: PinType = getPinType()
    lazy var sortMethod = SortMethod(rawValue: UserDefaults.standard.integer(forKey: "Library.sortOption")) ?? .lastOpened
    lazy var sortAscending = UserDefaults.standard.bool(forKey: "Library.sortAscending")
    lazy var badgeType: BadgeType = {
        var type: BadgeType = []
        if UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") {
            type.insert(.unread)
        }
        if UserDefaults.standard.bool(forKey: "Library.downloadedChapterBadges") {
            type.insert(.downloaded)
        }
        return type
    }()

    var filters: [LibraryFilter] {
        didSet {
            saveFilters()
        }
    }

    var categories: [String] = []
    lazy var currentCategory: String? = UserDefaults.standard.string(forKey: "Library.currentCategory") {
        didSet {
            UserDefaults.standard.set(currentCategory, forKey: "Library.currentCategory")
        }
    }
    private(set) var actuallyEmpty = true

    init() {
        let filtersData = UserDefaults.standard.data(forKey: "Library.filters")
        if let filtersData {
            let filters = try? JSONDecoder().decode([LibraryFilter].self, from: filtersData)
            self.filters = filters ?? []
        } else {
            self.filters = []
        }
    }
}

extension LibraryViewModel {
    func isCategoryLocked() -> Bool {
        guard UserDefaults.standard.bool(forKey: "Library.lockLibrary") else { return false }
        if let currentCategory = currentCategory {
            return UserDefaults.standard.stringArray(forKey: "Library.lockedCategories")?.contains(currentCategory) ?? false
        }
        return true
    }

    func getPinType() -> PinType {
        UserDefaults.standard.string(forKey: "Library.pinTitles").flatMap(PinType.init) ?? .none
    }

    func refreshCategories() async {
        categories = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.getCategories(context: context).map { $0.title ?? "" }
        }
        if currentCategory != nil && !categories.contains(currentCategory!) {
            currentCategory = nil
            await loadLibrary()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func loadLibrary() async {
        let currentCategory = self.currentCategory
        let sortMethod = self.sortMethod
        let sortAscending = self.sortAscending
        let filters = self.filters
        let pinType = self.pinType

        let (
            success,
            actuallyEmpty,
            pinnedManga,
            manga,
            sourceKeys,
            unappliedFilters
        ) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            var pinnedManga: [MangaInfo] = []
            var manga: [MangaInfo] = []
            var sourceKeys: Set<String> = []
            var unappliedFilters: [LibraryFilter] = []

            let request = LibraryMangaObject.fetchRequest()
            if let currentCategory {
                request.predicate = NSPredicate(format: "manga != nil AND ANY categories.title == %@", currentCategory)
            } else {
                request.predicate = NSPredicate(format: "manga != nil")
            }
            if sortMethod != .unreadChapters {
                request.sortDescriptors = [
                    NSSortDescriptor(
                        key: sortMethod.sortStringValue,
                        ascending: sortMethod == .alphabetical ? !sortAscending : sortAscending
                    )
                ]
            }
            guard let libraryObjects = try? context.fetch(request) else {
                return (false, true, pinnedManga, manga, sourceKeys, unappliedFilters)
            }

            let actuallyEmpty = libraryObjects.isEmpty

            var ids = Set<String>()

            main: for libraryObject in libraryObjects {
                guard
                    let mangaObject = libraryObject.manga,
                    // ensure the manga hasn't already been accounted for
                    ids.insert("\(mangaObject.sourceId)|\(mangaObject.id)").inserted
                else { continue }

                let info = MangaInfo(
                    mangaId: mangaObject.id,
                    sourceId: mangaObject.sourceId,
                    coverUrl: mangaObject.cover.flatMap { URL(string: $0) },
                    title: mangaObject.title,
                    author: mangaObject.author,
                    url: mangaObject.url.flatMap { URL(string: $0) }
                )

                sourceKeys.insert(mangaObject.sourceId)

                // process filters
                var filteredSourceKeys: Set<String> = []
                var filteredContentRatings: Set<Int16> = []
                for filter in filters {
                    let condition: Bool
                    switch filter.type {
                        case .downloaded:
                            unappliedFilters.append(filter)
                            continue
                        case .tracking:
                            condition = CoreDataManager.shared.hasTrack(
                                sourceId: info.sourceId,
                                mangaId: info.mangaId,
                                context: context
                            )
                        case .hasUnread:
                            unappliedFilters.append(filter)
                            continue
                        case .started:
                            condition = CoreDataManager.shared.hasHistory(
                                sourceId: info.sourceId,
                                mangaId: info.mangaId,
                                context: context
                            )
                        case .completed:
                            condition = mangaObject.status == AidokuRunner.PublishingStatus.completed.rawValue
                        case .source:
                            guard let sourceId = filter.value else { continue }
                            if filter.exclude {
                                condition = info.sourceId == sourceId
                            } else {
                                // handle included source filters as OR
                                filteredSourceKeys.insert(sourceId)
                                continue
                            }
                        case .contentRating:
                            guard let contentRating = filter.value.flatMap(MangaContentRating.init) else { continue }
                            if filter.exclude {
                                condition = mangaObject.nsfw == contentRating.rawValue
                            } else {
                                // handle included content rating filters as OR
                                filteredContentRatings.insert(Int16(contentRating.rawValue))
                                continue
                            }
                    }
                    let shouldSkip = filter.exclude ? condition : !condition
                    if shouldSkip {
                        continue main
                    }
                }
                if !filteredSourceKeys.isEmpty && !filteredSourceKeys.contains(info.sourceId) {
                    continue main
                }
                if !filteredContentRatings.isEmpty && !filteredContentRatings.contains(mangaObject.nsfw) {
                    continue main
                }

                switch pinType {
                    case .none:
                        manga.append(info)
                    case .unread:
                        // don't have unread info to sort yet
                        manga.append(info)
                    case .updatedChapters:
                        if libraryObject.lastUpdatedChapters > libraryObject.lastOpened {
                            pinnedManga.append(info)
                        } else {
                            manga.append(info)
                        }
                }
            }

            return (true, actuallyEmpty, pinnedManga, manga, sourceKeys, unappliedFilters)
        }

        guard success else { return }

        self.pinnedManga = pinnedManga
        self.manga = manga
        self.sourceKeys = sourceKeys.sorted()
        self.actuallyEmpty = actuallyEmpty

        await fetchUnreads(skipSortCheck: true)
        await fetchDownloadCounts()

        if !unappliedFilters.isEmpty {
            let filter: (MangaInfo) -> Bool = { info in
                for filter in unappliedFilters {
                    let condition: Bool
                    switch filter.type {
                        case .downloaded: condition = info.downloads > 0
                        case .hasUnread: condition = info.unread > 0
                        default: continue
                    }
                    let shouldSkip = filter.exclude ? condition : !condition
                    guard !shouldSkip else { return false }
                }
                return true
            }
            self.pinnedManga = self.pinnedManga.filter(filter)
            self.manga = self.manga.filter(filter)
        }

        if pinType == .unread {
            let currentManga = self.manga + self.pinnedManga
            var pinnedManga: [MangaInfo] = []
            var manga: [MangaInfo] = []
            for item in currentManga {
                if item.unread > 0 {
                    pinnedManga.append(item)
                } else {
                    manga.append(item)
                }
            }
            self.pinnedManga = pinnedManga
            self.manga = manga
        }

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
                                scanlators: filters.scanlators,
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
        await MainActor.run {
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
        }
        if pinType == .unread {
            await loadLibrary()
        } else if sortMethod == .unreadChapters {
            await sortLibrary()
        }
    }

    func fetchUnreads(skipSortCheck: Bool = false) async {
        if !skipSortCheck && pinType == .unread {
            // re-load library to ensure pinned manga is correct
            return await loadLibrary()
        }

        let currentManga = self.manga + self.pinnedManga

        // fetch new unread counts
        let unreadCounts = await withTaskGroup(of: (Int, Int).self) { group in
            var unreadCounts: [Int: Int] = [:]
            for manga in currentManga {
                group.addTask {
                    let context = CoreDataManager.shared.container.newBackgroundContext()
                    return context.performAndWait {
                        let filters = CoreDataManager.shared.getMangaChapterFilters(
                            sourceId: manga.sourceId,
                            mangaId: manga.mangaId,
                            context: context
                        )
                        let count = CoreDataManager.shared.unreadCount(
                            sourceId: manga.sourceId,
                            mangaId: manga.mangaId,
                            lang: filters.language,
                            scanlators: filters.scanlators,
                            context: context
                        )
                        return (manga.hashValue, count)
                    }
                }
            }
            for await (key, count) in group {
                unreadCounts[key] = count
            }
            return unreadCounts
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
        if !skipSortCheck && sortMethod == .unreadChapters {
            await sortLibrary()
        }
    }

    func fetchUnreads(for identifier: MangaIdentifier) async {
        let unreadCount = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            let filters = CoreDataManager.shared.getMangaChapterFilters(
                sourceId: identifier.sourceKey,
                mangaId: identifier.mangaKey,
                context: context
            )
            return CoreDataManager.shared.unreadCount(
                sourceId: identifier.sourceKey,
                mangaId: identifier.mangaKey,
                lang: filters.language,
                scanlators: filters.scanlators,
                context: context
            )
        }
        var didUpdate = false
        if let index = self.manga.firstIndex(where: { $0.identifier == identifier }) {
            if self.manga[index].unread != unreadCount {
                didUpdate = true
                self.manga[index].unread = unreadCount
            }
        } else if let index = self.pinnedManga.firstIndex(where: { $0.identifier == identifier }) {
            if self.pinnedManga[index].unread != unreadCount {
                didUpdate = true
                self.pinnedManga[index].unread = unreadCount
            }
        }
        // re-sort library if needed
        if didUpdate {
            if pinType == .unread {
                await loadLibrary()
            } else if sortMethod == .unreadChapters {
                await sortLibrary()
            }
        }
    }

    func fetchDownloadCounts(for identifier: MangaIdentifier? = nil) async {
        var downloadCounts: [MangaIdentifier: Int] = [:]
        if let identifier {
            downloadCounts[identifier] = await DownloadManager.shared.downloadsCount(for: identifier)
        } else {
            let currentManga = self.manga + self.pinnedManga
            for manga in currentManga {
                let identifier = manga.identifier
                downloadCounts[identifier] = await DownloadManager.shared.downloadsCount(for: identifier)
            }
        }
        for (i, manga) in self.pinnedManga.enumerated() {
            if let count = downloadCounts[manga.identifier] {
                self.pinnedManga[i].downloads = count
            }
        }
        for (i, manga) in self.manga.enumerated() {
            if let count = downloadCounts[manga.identifier] {
                self.manga[i].downloads = count
            }
        }
    }

    @MainActor
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

    func setSort(method: SortMethod, ascending: Bool) async {
        guard sortMethod != method || sortAscending != ascending else {
            return
        }
        if sortAscending != ascending {
            sortAscending = ascending
            UserDefaults.standard.set(sortAscending, forKey: "Library.sortAscending")
        }
        if sortMethod != method {
            sortMethod = method
            UserDefaults.standard.set(sortMethod.rawValue, forKey: "Library.sortOption")
        }
        await sortLibrary()
    }

    func toggleFilter(method: FilterMethod, value: String? = nil) async {
        let filterIndex = filters.firstIndex(where: { $0.type == method && $0.value == value })
        if let filterIndex {
            if filters[filterIndex].exclude {
                filters.remove(at: filterIndex)
            } else {
                filters[filterIndex].exclude = true
            }
        } else {
            filters.append(LibraryFilter(type: method, value: value, exclude: false))
        }
        await loadLibrary()
    }

    private func saveFilters() {
        let filtersData = try? JSONEncoder().encode(filters)
        if let filtersData {
            UserDefaults.standard.set(filtersData, forKey: "Library.filters")
        }
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

    // returns true if library was reloaded
    @discardableResult
    func mangaOpened(sourceId: String, mangaId: String) async -> Bool {
        guard sortMethod == .lastOpened || pinType.needsUpdateOnContentOpen else { return false }

        var libraryReloaded = false

        let pinnedIndex = pinnedManga.firstIndex(where: { $0.mangaId == mangaId && $0.sourceId == sourceId })
        if let pinnedIndex {
            if sortMethod == .lastOpened {
                let manga = pinnedManga.remove(at: pinnedIndex)
                if pinType.needsUpdateOnContentOpen {
                    self.manga.insert(manga, at: 0)
                } else {
                    pinnedManga.insert(manga, at: 0)
                }
            } else {
                await loadLibrary() // don't know where to put in manga array, just refresh
                libraryReloaded = true
            }
        } else if sortMethod == .lastOpened {
            let index = manga.firstIndex(where: { $0.mangaId == mangaId && $0.sourceId == sourceId })
            if let index {
                let manga = manga.remove(at: index)
                if sortAscending {
                    // add to end
                    self.manga.append(manga)
                } else {
                    // add to start
                    self.manga.insert(manga, at: 0)
                }
            }
        }

        return libraryReloaded
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

    func addToCurrentCategory(manga: MangaInfo) async {
        guard let currentCategory = currentCategory else { return }
        await CoreDataManager.shared.addCategoriesToManga(
            sourceId: manga.sourceId,
            mangaId: manga.mangaId,
            categories: [currentCategory]
        )
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
}
