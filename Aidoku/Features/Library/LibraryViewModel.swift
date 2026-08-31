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
    private var searchQuery: String = ""
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
                case .alphabetical: NSLocalizedString("SORT_TITLE")
                case .lastRead: NSLocalizedString("SORT_LAST_READ")
                case .lastOpened: NSLocalizedString("SORT_LAST_OPENED")
                case .lastUpdated: NSLocalizedString("SORT_LAST_UPDATED")
                case .dateAdded: NSLocalizedString("SORT_DATE_ADDED")
                case .lastChapter: NSLocalizedString("SORT_LATEST_CHAPTER")
                case .unreadChapters: NSLocalizedString("SORT_UNREAD_CHAPTERS")
                case .totalChapters: NSLocalizedString("SORT_TOTAL_CHAPTERS")
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

    lazy var pinType: PinType = getPinType()
    lazy var sortMethod = SortMethod(rawValue: AppSettings.library.sortOption.get()) ?? .lastOpened
    lazy var sortAscending = AppSettings.library.sortAscending.get()
    lazy var badgeType: BadgeType = {
        var type: BadgeType = []
        if AppSettings.library.unreadChapterBadges.get() {
            type.insert(.unread)
        }
        if AppSettings.library.downloadedChapterBadges.get() {
            type.insert(.downloaded)
        }
        return type
    }()

    var filters: [LibraryFilter] {
        didSet {
            saveFilters()
        }
    }
    var activeFilters: [LibraryFilter] {
        if let currentCategory, let group = filterGroups.first(where: { $0.title == currentCategory }) {
            group.filters + self.filters
        } else {
            self.filters
        }
    }

    var categories: [String] = []
    var filterGroups: [FilterGroup] = []
    lazy var currentCategory: String? = AppSettings.library.currentCategory.get() {
        didSet {
            AppSettings.library.currentCategory.set(currentCategory)
        }
    }
    var isInRealCategory: Bool {
        if let currentCategory, !currentCategory.isEmpty {
            categories.contains(currentCategory)
        } else {
            false
        }
    }
    var isInUncategorizedCategory: Bool {
        currentCategory?.isEmpty ?? false
    }
    private(set) var actuallyEmpty = true

    init() {
        let filtersData = AppSettings.library.filtersData.get()
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
        guard AppSettings.library.lockLibrary.get() else { return false }
        if let currentCategory, !currentCategory.isEmpty {
            let lockedCategories = AppSettings.library.lockedCategories.get()
            return lockedCategories.contains(currentCategory)
        }
        return true
    }

    func getPinType() -> PinType {
        PinType(rawValue: AppSettings.library.pinTitles.get()) ?? .none
    }

    func refreshCategories(skipDataLoad: Bool = false) async {
        (categories, filterGroups) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            (
                CoreDataManager.shared.getCategoryTitles(context: context),
                CoreDataManager.shared.getFilterGroups(context: context)
            )
        }
        if !skipDataLoad {
            let isInFilterGroup = filterGroups.contains(where: { $0.title == currentCategory })
            let showUncategorized = AppSettings.library.showUncategorizedCategory.get()
            if let currentCategory, (!categories.contains(currentCategory) && !isInFilterGroup) || (currentCategory.isEmpty && !showUncategorized) {
                self.currentCategory = nil
                await loadLibrary()
            } else if isInFilterGroup {
                // refresh filter group in case filters changed
                await loadLibrary()
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func loadLibrary() async {
        // handle filter groups
        let filters = self.activeFilters
        let currentCategory = (isInUncategorizedCategory || isInRealCategory) ? self.currentCategory : nil

        let (
            success,
            actuallyEmpty,
            pinnedManga,
            manga,
            sourceKeys,
            unappliedFilters
        ) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable [sortMethod, sortAscending, pinType] context in
            var pinnedManga: [MangaInfo] = []
            var manga: [MangaInfo] = []
            var sourceKeys: Set<String> = []
            var unappliedFilters: [LibraryFilter] = []

            let request = LibraryMangaObject.fetchRequest()
            if let currentCategory {
                if currentCategory.isEmpty {
                    request.predicate = NSPredicate(format: "manga != nil AND categories.@count == 0")
                } else {
                    request.predicate = NSPredicate(format: "manga != nil AND ANY categories.title == %@", currentCategory)
                }
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

            var ids = Set<MangaIdentifier>()

            main: for libraryObject in libraryObjects {
                guard
                    let mangaObject = libraryObject.manga,
                    // ensure the manga hasn't already been accounted for
                    ids.insert(mangaObject.identifier).inserted
                else {
                    continue
                }

                let categories = (libraryObject.categories?.allObjects as? [CategoryObject])?.map { $0.title } ?? []

                let info = MangaInfo(
                    id: mangaObject.identifier,
                    coverUrl: mangaObject.cover.flatMap { URL(string: $0) },
                    title: mangaObject.title,
                    author: mangaObject.author,
                    url: mangaObject.url.flatMap { URL(string: $0) }
                )

                sourceKeys.insert(mangaObject.sourceId)

                // process filters
                var filteredSourceKeys: Set<String> = []
                var filteredContentRatings: Set<Int16> = []
                var filteredCategories: Set<String> = []
                for filter in filters {
                    let condition: Bool
                    switch filter.type {
                        case .downloaded:
                            unappliedFilters.append(filter)
                            continue
                        case .tracking:
                            condition = CoreDataManager.shared.hasTrack(
                                mangaId: info.id,
                                context: context
                            )
                        case .hasUnread:
                            unappliedFilters.append(filter)
                            continue
                        case .started:
                            condition = CoreDataManager.shared.hasHistory(
                                mangaId: info.id,
                                context: context
                            )
                        case .completed:
                            condition = mangaObject.status == AidokuRunner.PublishingStatus.completed.rawValue
                        case .source:
                            guard let sourceId = filter.value else { continue }
                            if filter.exclude {
                                condition = info.id.sourceKey == sourceId
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
                        case .category:
                            guard let category = filter.value else { continue }
                            if filter.exclude {
                                condition = categories.contains(category)
                            } else {
                                // handle included category filters as OR
                                filteredCategories.insert(category)
                                continue
                            }

                    }
                    let shouldSkip = filter.exclude ? condition : !condition
                    if shouldSkip {
                        continue main
                    }
                }
                if !filteredSourceKeys.isEmpty && !filteredSourceKeys.contains(info.id.sourceKey) {
                    continue main
                }
                if !filteredContentRatings.isEmpty && !filteredContentRatings.contains(mangaObject.nsfw) {
                    continue main
                }
                if !filteredCategories.isEmpty && !filteredCategories.contains(where: { categories.contains($0) }) {
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
        self.storedPinnedManga = nil
        self.storedManga = nil
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

        if !searchQuery.isEmpty {
            await search(query: searchQuery)
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
                                mangaId: item.id,
                                context: context
                            )
                            return CoreDataManager.shared.unreadCount(
                                mangaId: item.id,
                                lang: filters.language,
                                scanlators: filters.scanlators,
                                context: context
                            )
                        }
                    }
                    if let info = currentManga.first(where: { $0.id == item.id }) {
                        return (info.hashValue, await getUnreadCount())
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
        if pinType == .unread || activeFilters.contains(where: { $0.type == .hasUnread }) {
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
                        let filters = CoreDataManager.shared.getMangaChapterFilters(mangaId: manga.id, context: context)
                        let count = CoreDataManager.shared.unreadCount(
                            mangaId: manga.id,
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
                mangaId: identifier,
                context: context
            )
            return CoreDataManager.shared.unreadCount(
                mangaId: identifier,
                lang: filters.language,
                scanlators: filters.scanlators,
                context: context
            )
        }
        var didUpdate = false
        if let index = self.manga.firstIndex(where: { $0.id == identifier }) {
            if self.manga[index].unread != unreadCount {
                didUpdate = true
                self.manga[index].unread = unreadCount
            }
        } else if let index = self.pinnedManga.firstIndex(where: { $0.id == identifier }) {
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
                let identifier = manga.id
                downloadCounts[identifier] = await DownloadManager.shared.downloadsCount(for: identifier)
            }
        }
        for (i, manga) in self.pinnedManga.enumerated() {
            if let count = downloadCounts[manga.id] {
                self.pinnedManga[i].downloads = count
            }
        }
        for (i, manga) in self.manga.enumerated() {
            if let count = downloadCounts[manga.id] {
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
            AppSettings.library.sortAscending.set(sortAscending)
        }
        if sortMethod != method {
            sortMethod = method
            AppSettings.library.sortOption.set(sortMethod.rawValue)
        }
        await sortLibrary()
    }

    func toggleFilter(method: LibraryFilter.FilterMethod, value: String? = nil) async {
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
            AppSettings.library.filtersData.set(filtersData)
        }
    }

    func search(query: String) async {
        searchQuery = query

        guard !query.isEmpty else {
            var shouldResort = false
            if let storedManga {
                manga = storedManga
                self.storedManga = nil
                shouldResort = true
            }
            if let storedPinnedManga {
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
        guard let storedManga, let storedPinnedManga else {
            return
        }

        let query = query.lowercased()
        pinnedManga = storedPinnedManga.filter { $0.title?.lowercased().contains(query) ?? false }
        manga = storedManga.filter { $0.title?.lowercased().fuzzyMatch(query) ?? false || $0.author?.lowercased().fuzzyMatch(query) ?? false }
    }

    // returns true if library was reloaded
    @discardableResult
    func mangaOpened(mangaId: MangaIdentifier) async -> Bool {
        guard sortMethod == .lastOpened || pinType.needsUpdateOnContentOpen else { return false }

        var libraryReloaded = false

        let pinnedIndex = pinnedManga.firstIndex(where: { $0.id == mangaId })
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
            let index = manga.firstIndex(where: { $0.id == mangaId })
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

    func mangaRead(mangaId: MangaIdentifier) async {
        if activeFilters.contains(where: { $0.type == .hasUnread }) {
            // reload library in case all chapters were read and the manga should be filtered
            await loadLibrary()
            return
        }

        guard sortMethod == .lastRead else { return }

        if let pinnedIndex = pinnedManga.firstIndex(where: { $0.id == mangaId }) {
            let manga = pinnedManga.remove(at: pinnedIndex)
            self.manga.insert(manga, at: 0)
        } else if let index = manga.firstIndex(where: { $0.id == mangaId }) {
            let manga = manga.remove(at: index)
            self.manga.insert(manga, at: 0)
        }
    }

    func removeFromLibrary(manga: MangaInfo) async {
        pinnedManga.removeAll { $0.id == manga.id }
        self.manga.removeAll { $0.id == manga.id }
        await MangaManager.shared.removeFromLibrary(mangaId: manga.id)
    }

    func addToCurrentCategory(manga: MangaInfo) async {
        guard let currentCategory, isInRealCategory else { return }
        await CoreDataManager.shared.addCategoriesToManga(
            mangaId: manga.id,
            categories: [currentCategory]
        )
    }

    func removeFromCurrentCategory(manga: MangaInfo) async {
        guard let currentCategory, isInRealCategory else { return }
        pinnedManga.removeAll { $0.id == manga.id }
        self.manga.removeAll { $0.id == manga.id }
        await CoreDataManager.shared.removeCategoriesFromManga(
            mangaId: manga.id,
            categories: [currentCategory]
        )
    }
}
