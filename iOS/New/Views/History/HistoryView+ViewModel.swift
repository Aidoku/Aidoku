//
//  HistoryView+ViewModel.swift
//  Aidoku
//
//  Created by Skitty on 7/31/25.
//

import AidokuRunner
import Combine
import SwiftUI

extension HistoryView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var filteredHistory: [Int: HistorySection] = [:]
        @Published var mangaCache: [MangaIdentifier: AidokuRunner.Manga] = [:]
        @Published var chapterCache: [ChapterIdentifier: AidokuRunner.Chapter] = [:]

        enum LoadingState {
            case idle  // more available to laod
            case loading  // currently loading more
            case complete  // nothing more to load
        }

        @Published var loadingState: LoadingState = .idle

        private var offset = 0
        private var historyData: [Int: [HistoryEntry]] = [:]
        private var loadTask: Task<Bool, Never>?

        private var searchQuery: String = ""
        private var searchTask: Task<Void, Never>?

        private var missingMangaQueue: [MangaIdentifier: Set<String>] = [:]  // [mangaKey: Set<chapterId>]
        private var mangaLoadTask: Task<Void, Never>?
        private let maxConcurrentLoads = 3

        private let batchSize = 100

        private var cancellables = Set<AnyCancellable>()

        init() {
            setUpNotifications()
        }
    }
}

extension HistoryView.ViewModel {
    private func setUpNotifications() {
        NotificationCenter.default.publisher(for: .updateHistory)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // reset all cached history entries
                guard let self else { return }
                self.filteredHistory = [:]
                self.historyData = [:]
                self.offset = 0
                self.loadingState = .idle
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .historyAdded)
            .sink { [weak self] output in
                // fetch new history entries
                guard
                    let self,
                    let chapters = output.object as? [ChapterIdentifier]
                else {
                    return
                }
                Task { @MainActor in
                    var refreshingDays = Set<Int>()
                    if chapters.count == 1, let chapterId = chapters.first {
                        // check if there's existing history to remove first
                        if
                            self.chapterCache[chapterId] != nil
                                || self.missingMangaQueue[chapterId.mangaIdentifier] != nil,
                            let day = self.removeStoredHistory(
                                chapterId: chapterId,
                                updateFilteredHistory: false
                            )
                        {
                            refreshingDays.insert(day)
                        }
                    }
                    await self.fetchNew(count: chapters.count, refreshingDays: refreshingDays)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .historyRemoved)
            .sink { [weak self] output in
                // remove history entries
                guard let self else { return }
                Task { @MainActor in
                    if let chapters = output.object as? [ChapterIdentifier] {
                        for chapterId in chapters {
                            self.removeStoredHistory(chapterId: chapterId)
                        }
                    } else if let mangaId = output.object as? MangaIdentifier {
                        self.removeStoredHistory(mangaId: mangaId)
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .historySet)
            .sink { [weak self] output in
                // remove existing history entry and add new one
                guard
                    let self,
                    let item = output.object as? (chapterId: ChapterIdentifier, page: Int)
                else {
                    return
                }
                Task { @MainActor in
                    var refreshingDays = Set<Int>()
                    // a history entry might exist already, so remove it
                    if
                        self.chapterCache[item.chapterId] != nil
                            || self.missingMangaQueue[item.chapterId.mangaIdentifier] != nil,
                        let day = self.removeStoredHistory(
                            chapterId: item.chapterId,
                            updateFilteredHistory: false
                        )
                    {
                        refreshingDays.insert(day)
                    }
                    // add new chapter history to the top
                    await self.fetchNew(count: 1, refreshingDays: refreshingDays)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: Loading
extension HistoryView.ViewModel {
    // fetch a specified number of new history entries (that will be appended to the top)
    func fetchNew(count: Int, refreshingDays: Set<Int> = []) async {
        if let loadTask {
            _ = await loadTask.value
        }

        loadTask = Task.detached {
            // offset needs to be the number of items before today, in case of entries in the future
            let now = Date()
            let offset = await self.historyData.reduce(into: 0) { offset, section in
                switch section.key {
                    case ..<0: // future
                        offset += section.value.count
                    case 0: // today
                        offset += section.value.prefix(while: { $0.date >= now }).count
                    default: // past
                        break
                }
            }
            let newObjectCount = await self.processHistoryObjects(
                limit: count,
                offset: offset,
                refreshingDays: refreshingDays
            )
            await self.increaseOffset(by: newObjectCount)
            return false
        }
        _ = await loadTask?.value
    }

    // load more history entries (called when scrolling to the bottom)
    func loadMore() async {
        guard loadingState == .idle else { return }

        loadingState = .loading

        if loadTask == nil {
            loadTask = Task.detached { [offset] in
                let newObjectCount = await self.processHistoryObjects(limit: self.batchSize, offset: offset)
                await self.increaseOffset(by: newObjectCount)
                return newObjectCount < self.batchSize // if less than the limit, we reached the end
            }
        }
        guard let loadTask else { return }
        let completed = await loadTask.value
        self.loadTask = nil

        loadingState = completed ? .complete : .idle
    }
}

// MARK: Searching
extension HistoryView.ViewModel {
    // start a new search task with an optional delay
    func search(query: String, delay: Bool) async {
        guard searchQuery != query else { return }
        searchTask?.cancel()
        searchTask = Task {
            if delay {
                try? await Task.sleep(nanoseconds: 500_000_000) // wait 0.5s
            }
            guard !Task.isCancelled else { return }
            searchQuery = query
            refilterHistory()
        }
    }

    // refilter all of the existing cached history entries
    private func refilterHistory() {
        for (index, existingSection) in filteredHistory {
            let newSection = HistorySection(
                daysAgo: existingSection.daysAgo,
                entries: filterDay(entries: historyData[existingSection.daysAgo] ?? [])
            )
            filteredHistory[index] = newSection
        }
    }
}

// MARK: Removing
extension HistoryView.ViewModel {
    // remove history linked to an entry
    // if all is true, removes all history for the associated manga
    func removeHistory(entry: HistoryEntry, all: Bool = false) async {
        if all {
            await HistoryManager.shared.removeHistory(mangaId: entry.chapterId.mangaIdentifier)
        } else {
            await HistoryManager.shared.removeHistory(chapterIds: [entry.chapterId])
        }
    }

    // removes all history
    func clearHistory() {
        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.clearHistory(context: context)
                try? context.save()
            }
            filteredHistory = [:]
            historyData = [:]
            offset = 0
            loadingState = .idle
        }
    }

    // remove a cached history entry for a chapter
    @discardableResult
    private func removeStoredHistory(chapterId: ChapterIdentifier, updateFilteredHistory: Bool = true) -> Int? {
        for section in historyData {
            for (index, entry) in section.value.enumerated() where entry.chapterId == chapterId {
                historyData[section.key]?.remove(at: index)
                if updateFilteredHistory {
                    filteredHistory[section.key] = HistorySection(
                        daysAgo: section.key,
                        entries: filterDay(entries: historyData[section.key] ?? [])
                    )
                }
                offset -= 1
                return section.key
            }
        }
        return nil
    }

    // remove all cached history entries for a manga
    private func removeStoredHistory(mangaId: MangaIdentifier) {
        var modifiedDays = Set<Int>()
        for section in historyData {
            var index = 0
            for _ in 0..<section.value.count {
                let entry = historyData[section.key]![index]
                if entry.chapterId.mangaIdentifier == mangaId {
                    historyData[section.key]?.remove(at: index)
                    modifiedDays.insert(section.key)
                    offset -= 1
                } else {
                    index += 1
                }
            }
        }

        for day in modifiedDays {
            filteredHistory[day] = HistorySection(
                daysAgo: day,
                entries: filterDay(entries: historyData[day] ?? [])
            )
        }
    }
}

// MARK: Queue
extension HistoryView.ViewModel {
    private func startMissingMangaQueueIfNeeded() {
        if mangaLoadTask == nil || mangaLoadTask?.isCancelled == true {
            mangaLoadTask = Task { await self.processMissingMangaQueue() }
        }
    }

    // add a chapter (missing from coredata) to the queue for loading
    private func addToQueue(mangaId: MangaIdentifier, chapterKey: String) {
        if missingMangaQueue[mangaId] == nil {
            missingMangaQueue[mangaId] = []
        }
        missingMangaQueue[mangaId]?.insert(chapterKey)
    }

    // loader for manga/chapters missing from coredata
    private func processMissingMangaQueue() async {
        while !missingMangaQueue.isEmpty {
            let mangaIds = Array(missingMangaQueue.keys.prefix(maxConcurrentLoads))
            await withTaskGroup(of: Void.self) { group in
                for mangaId in mangaIds {
                    guard let chapterIds = missingMangaQueue[mangaId] else { continue }
                    group.addTask {
                        await self.loadMangaAndChapters(mangaId: mangaId, chapterIds: chapterIds)
                    }
                }
                await group.waitForAll()
            }
            // remove processed manga from queue
            for mangaId in mangaIds {
                missingMangaQueue.removeValue(forKey: mangaId)
            }
        }
        mangaLoadTask = nil
    }

    // load manga and chapter data from source into cache
    private func loadMangaAndChapters(mangaId: MangaIdentifier, chapterIds: Set<String>) async {
        guard let source = SourceManager.shared.source(for: mangaId.sourceKey) else { return }
        let tempManga = AidokuRunner.Manga(sourceKey: mangaId.sourceKey, key: mangaId.mangaKey, title: "")

        let needsManga = mangaCache[mangaId] == nil

        if let newManga = try? await source.getMangaUpdate(
            manga: tempManga,
            needsDetails: needsManga,
            needsChapters: true
        ) {
            await MainActor.run {
                if needsManga {
                    self.mangaCache[mangaId] = newManga
                }
                if let chapters = newManga.chapters {
                    for chapter in chapters where chapterIds.contains(chapter.key) {
                        let key = ChapterIdentifier(sourceKey: mangaId.sourceKey, mangaKey: mangaId.mangaKey, chapterKey: chapter.key)
                        self.chapterCache[key] = chapter
                    }
                }
            }
        }
    }
}

// MARK: Processing
extension HistoryView.ViewModel {
    private struct HistoryInfo {
        let chapterId: ChapterIdentifier
        let dateRead: Date?
        let progress: Int16
        let total: Int16
        let completed: Bool
    }

    // fetch history objects from core data and process them into history entries
    // returns the number of history objects found (if less than limit then the end was reached)
    private nonisolated func processHistoryObjects(
        limit: Int,
        offset: Int,
        refreshingDays: Set<Int> = []
    ) async -> Int {
        let historyObj = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.getRecentHistory(limit: limit, offset: offset, context: context)
                .map {
                    HistoryInfo(
                        chapterId: .init(sourceKey: $0.sourceId, mangaKey: $0.mangaId, chapterKey: $0.chapterId),
                        dateRead: $0.dateRead,
                        progress: $0.progress,
                        total: $0.total,
                        completed: $0.completed
                    )
                }
        }

        var modifiedDays = refreshingDays

        var newHistoryData = await historyData
        var newMangaCacheItems: [MangaIdentifier: AidokuRunner.Manga] = [:]
        var newChapterCacheItems: [ChapterIdentifier: AidokuRunner.Chapter] = [:]

        for obj in historyObj {
            let readDate = obj.dateRead ?? Date.distantPast
            let endOfDay = Date.endOfDay()
            let isInFuture = readDate > endOfDay
            let endDate = if isInFuture {
                // if the date is in the future, compare the difference to the start of the day instead of end
                Date.startOfDay()
            } else {
                endOfDay
            }
            let days = Calendar.autoupdatingCurrent.dateComponents(
                Set([Calendar.Component.day]),
                from: readDate,
                to: endDate
            ).day ?? 0

            let (manga, chapter) = await CoreDataManager.shared.container.performBackgroundTask { context in
                (
                    CoreDataManager.shared.getManga(
                        mangaId: obj.chapterId.mangaIdentifier,
                        context: context
                    )?.toNewManga(),
                    CoreDataManager.shared.getChapter(
                        chapterId: obj.chapterId,
                        context: context
                    )?.toNewChapter()
                )
            }

            let chapterId = obj.chapterId
            let mangaId = chapterId.mangaIdentifier

            // If manga or chapter is missing, add to queue for background loading
            if manga == nil || chapter == nil {
                await addToQueue(mangaId: mangaId, chapterKey: chapterId.chapterKey)
            }

            if let manga { newMangaCacheItems[mangaId] = manga }
            if let chapter { newChapterCacheItems[chapterId] = chapter }

            let newEntry = HistoryEntry(
                chapterId: obj.chapterId,
                date: obj.dateRead ?? Date.distantPast,
                currentPage: obj.completed ? -1 : Int(obj.progress),
                totalPages: Int(obj.total)
            )
            var arr = newHistoryData[days] ?? []
            arr.append(newEntry)
            newHistoryData[days] = arr
            modifiedDays.insert(days)
        }

        // re-sort in case we appended "new" history at the bottom
        for day in modifiedDays {
            newHistoryData[day] = newHistoryData[day]?.sorted { $0.date > $1.date }  // sort by date, most recent first
        }

        var newFilteredHistory = await filteredHistory

        // update data
        for day in modifiedDays {
            newFilteredHistory[day] = HistorySection(
                daysAgo: day,
                entries: await filterDay(entries: newHistoryData[day] ?? [])
            )
        }

        await addMangaCacheItems(newMangaCacheItems)
        await addChapterCacheItems(newChapterCacheItems)
        await startMissingMangaQueueIfNeeded()

        await setHistoryData(newHistoryData)
        await setFilteredHistory(newFilteredHistory)

        return historyObj.count
    }

    // filter a day's worth of history entries based on the search query
    // also deduplicates entries by manga, only showing the most recent entry for each manga (with additional count)
    private func filterDay(entries: [HistoryEntry]) -> [HistoryEntry] {
        var newEntries: [HistoryEntry] = []

        var counts: [MangaIdentifier: Int] = [:]  // keyed by manga key

        for entry in entries {
            let mangaId = entry.chapterId.mangaIdentifier
            if let existingCount = counts[mangaId] {
                counts[mangaId] = existingCount + 1
                continue
            }
            if !searchQuery.isEmpty {
                let query = searchQuery.lowercased()
                let manga = mangaCache[mangaId]
                if let manga, manga.title.lowercased().contains(query) {
                    newEntries.append(entry)
                }
            } else {
                newEntries.append(entry)
            }
            counts[mangaId] = 0
        }

        for (i, entry) in newEntries.enumerated() {
            if let additionalCount = counts[entry.chapterId.mangaIdentifier], additionalCount > 0 {
                newEntries[i].additionalEntryCount = additionalCount
            } else {
                newEntries[i].additionalEntryCount = nil
            }
        }

        return newEntries
    }
}

// MARK: Setters
extension HistoryView.ViewModel {
    private func increaseOffset(by value: Int) {
        offset += value
    }

    private func addMangaCacheItems(_ newItems: [MangaIdentifier: AidokuRunner.Manga]) {
        for (key, manga) in newItems {
            mangaCache[key] = manga
        }
    }

    private func addChapterCacheItems(_ newItems: [ChapterIdentifier: AidokuRunner.Chapter]) {
        for (key, chapter) in newItems {
            chapterCache[key] = chapter
        }
    }

    private func setHistoryData(_ newHistoryData: [Int: [HistoryEntry]]) {
        historyData = newHistoryData
    }

    private func setFilteredHistory(_ newFilteredHistory: [Int: HistorySection]) {
        filteredHistory = newFilteredHistory
    }
}
