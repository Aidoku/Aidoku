//
//  HistoryView+ViewModel.swift
//  Aidoku
//
//  Created by Skitty on 7/31/25.
//

import AidokuRunner
import Combine
import SwiftUI

struct MangaKey: Hashable {
    let sourceId: String
    let mangaId: String
}

extension HistoryView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var filteredHistory: [Int: HistorySection] = [:]
        @Published var mangaCache: [String: AidokuRunner.Manga] = [:]
        @Published var chapterCache: [String: AidokuRunner.Chapter] = [:]

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

        private var missingMangaQueue: [MangaKey: Set<String>] = [:]  // [mangaKey: Set<chapterId>]
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
                    let chapters = output.object as? [Chapter]
                else { return }
                Task {
                    await self.fetchNew(count: chapters.count)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .historyRemoved)
            .sink { [weak self] output in
                // remove history entries
                guard let self else { return }
                if let chapters = output.object as? [Chapter] {
                    for chapter in chapters {
                        let chapterId = chapter.sourceId + "." + chapter.mangaId + "." + chapter.id
                        self.removeStoredHistory(chapterCacheKey: chapterId)
                    }
                } else if let manga = output.object as? Manga {
                    self.removeStoredHistory(mangaCacheKey: manga.key)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .historySet)
            .sink { [weak self] output in
                // remove existing history entry and add new one
                guard
                    let self,
                    let item = output.object as? (chapter: Chapter, page: Int)
                else {
                    return
                }
                let chapterCacheKey = item.chapter.sourceId + "." + item.chapter.mangaId + "." + item.chapter.id
                if
                    self.chapterCache[chapterCacheKey] != nil
                        || missingMangaQueue[MangaKey(sourceId: item.chapter.sourceId, mangaId: item.chapter.mangaId)] != nil
                {
                    // a history entry might exist already, so remove it
                    self.removeStoredHistory(chapterCacheKey: chapterCacheKey)
                }
                // add new chapter history to the top
                Task {
                    await self.fetchNew(count: 1)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: Loading
extension HistoryView.ViewModel {
    // fetch a specified number of new history entries (that will be appended to the top)
    func fetchNew(count: Int) async {
        if let loadTask {
            _ = await loadTask.value
        }

        loadTask = Task.detached {
            // offset needs to be the number of items before today, in case of entries in the future
            var offset = 0
            for (_, section) in await self.filteredHistory.sorted(by: { $0.key < $1.key }) {
                if section.daysAgo > 0 {
                    break
                } else if section.daysAgo == 0 {
                    // find any items with a date before now
                    let now = Date()
                    for entry in section.entries {
                        if entry.date < now {
                            break
                        }
                        offset += 1
                    }
                    break
                }
                offset += section.entries.count
            }
            let newObjectCount = await self.processHistoryObjects(limit: count, offset: offset)
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
            await HistoryManager.shared.removeHistory(
                sourceId: entry.sourceKey,
                mangaId: entry.mangaKey
            )
        } else {
            await HistoryManager.shared.removeHistory(
                sourceId: entry.sourceKey,
                mangaId: entry.mangaKey,
                chapterIds: [entry.chapterKey]
            )
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
    private func removeStoredHistory(chapterCacheKey: String) {
        for section in historyData {
            for (index, entry) in section.value.enumerated() where entry.chapterCacheKey == chapterCacheKey {
                historyData[section.key]?.remove(at: index)
                filteredHistory[section.key] = HistorySection(
                    daysAgo: section.key,
                    entries: filterDay(entries: historyData[section.key] ?? [])
                )
                offset -= 1
                return
            }
        }
    }

    // remove all cached history entries for a manga
    private func removeStoredHistory(mangaCacheKey: String) {
        var modifiedDays = Set<Int>()
        for section in historyData {
            var index = 0
            for _ in 0..<section.value.count {
                let entry = historyData[section.key]![index]
                if entry.mangaCacheKey == mangaCacheKey {
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
    private func addToQueue(mangaKey: MangaKey, chapterKey: String) {
        if missingMangaQueue[mangaKey] == nil {
            missingMangaQueue[mangaKey] = []
        }
        missingMangaQueue[mangaKey]?.insert(chapterKey)
    }

    // loader for manga/chapters missing from coredata
    private func processMissingMangaQueue() async {
        while !missingMangaQueue.isEmpty {
            let mangaKeys = Array(missingMangaQueue.keys.prefix(maxConcurrentLoads))
            await withTaskGroup(of: Void.self) { group in
                for mangaKey in mangaKeys {
                    guard let chapterIds = missingMangaQueue[mangaKey] else { continue }
                    group.addTask {
                        await self.loadMangaAndChapters(
                            mangaKey: mangaKey,
                            chapterIds: chapterIds
                        )
                    }
                }
                await group.waitForAll()
            }
            // remove processed manga from queue
            for mangaKey in mangaKeys {
                missingMangaQueue.removeValue(forKey: mangaKey)
            }
        }
        mangaLoadTask = nil
    }

    // load manga and chapter data from source into cache
    private func loadMangaAndChapters(mangaKey: MangaKey, chapterIds: Set<String>) async {
        let sourceId = mangaKey.sourceId
        let mangaId = mangaKey.mangaId
        guard let source = SourceManager.shared.source(for: sourceId) else { return }
        let tempManga = AidokuRunner.Manga(sourceKey: sourceId, key: mangaId, title: "")

        let mangaCacheKey = "\(sourceId).\(mangaId)"
        let needsManga = mangaCache[mangaCacheKey] == nil

        if let newManga = try? await source.getMangaUpdate(
            manga: tempManga,
            needsDetails: needsManga,
            needsChapters: true
        ) {
            await MainActor.run {
                if needsManga {
                    self.mangaCache[mangaCacheKey] = newManga
                }
                if let chapters = newManga.chapters {
                    for chapter in chapters where chapterIds.contains(chapter.key) {
                        let chapterCacheKey = "\(sourceId).\(mangaId).\(chapter.key)"
                        self.chapterCache[chapterCacheKey] = chapter
                    }
                }
            }
        }
    }
}

// MARK: Processing
extension HistoryView.ViewModel {
    private struct HistoryInfo {
        let sourceId: String
        let mangaId: String
        let chapterId: String
        let dateRead: Date?
        let progress: Int16
        let total: Int16
        let completed: Bool
    }

    // fetch history objects from core data and process them into history entries
    // returns the number of history objects found (if less than limit then the end was reached)
    private nonisolated func processHistoryObjects(limit: Int, offset: Int) async -> Int {
        let historyObj = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.getRecentHistory(limit: limit, offset: offset, context: context)
                .map {
                    HistoryInfo(
                        sourceId: $0.sourceId,
                        mangaId: $0.mangaId,
                        chapterId: $0.chapterId,
                        dateRead: $0.dateRead,
                        progress: $0.progress,
                        total: $0.total,
                        completed: $0.completed
                    )
                }
        }

        var modifiedDays = Set<Int>()

        var newHistoryData = await historyData
        var newMangaCacheItems: [String: AidokuRunner.Manga] = [:]
        var newChapterCacheItems: [String: AidokuRunner.Chapter] = [:]

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
                        sourceId: obj.sourceId,
                        mangaId: obj.mangaId,
                        context: context
                    )?.toNewManga(),
                    CoreDataManager.shared.getChapter(
                        sourceId: obj.sourceId,
                        mangaId: obj.mangaId,
                        chapterId: obj.chapterId,
                        context: context
                    )?.toNewChapter()
                )
            }

            // If manga or chapter is missing, add to queue for background loading
            if manga == nil || chapter == nil {
                let key = MangaKey(sourceId: obj.sourceId, mangaId: obj.mangaId)
                let shortChapterKey = obj.chapterId
                await addToQueue(mangaKey: key, chapterKey: shortChapterKey)
            }

            let mangaCacheKey = "\(obj.sourceId).\(obj.mangaId)"
            let chapterCacheKey = mangaCacheKey + ".\(obj.chapterId)"
            if let manga { newMangaCacheItems[mangaCacheKey] = manga }
            if let chapter { newChapterCacheItems[chapterCacheKey] = chapter }

            let newEntry = HistoryEntry(
                sourceKey: obj.sourceId,
                mangaKey: obj.mangaId,
                chapterKey: obj.chapterId,
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

        var counts: [String: Int] = [:]  // keyed by manga key

        for entry in entries {
            if let existingCount = counts[entry.mangaCacheKey] {
                counts[entry.mangaCacheKey] = existingCount + 1
                continue
            }
            if !searchQuery.isEmpty {
                let query = searchQuery.lowercased()
                let manga = mangaCache[entry.mangaCacheKey]
                if let manga, manga.title.lowercased().contains(query) {
                    newEntries.append(entry)
                }
            } else {
                newEntries.append(entry)
            }
            counts[entry.mangaCacheKey] = 0
        }

        for (i, entry) in newEntries.enumerated() {
            if let additionalCount = counts[entry.mangaCacheKey], additionalCount > 0 {
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

    private func addMangaCacheItems(_ newItems: [String: AidokuRunner.Manga]) {
        for (key, manga) in newItems {
            mangaCache[key] = manga
        }
    }

    private func addChapterCacheItems(_ newItems: [String: AidokuRunner.Chapter]) {
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
