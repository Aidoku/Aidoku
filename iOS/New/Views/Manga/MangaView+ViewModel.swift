//
//  MangaView+ViewModel.swift
//  Aidoku
//
//  Created by Skitty on 4/29/25.
//

import AidokuRunner
import Combine
import SwiftUI

extension MangaView {
    @MainActor
    class ViewModel: ObservableObject {
        private let source: AidokuRunner.Source

        @Published var manga: AidokuRunner.Manga
        @Published var chapters: [AidokuRunner.Chapter] = []

        @Published var readingHistory: [String: (page: Int, date: Int)] = [:]
        @Published var downloadProgress: [String: Float] = [:] // chapterId: progress
        @Published var downloadStatus: [String: DownloadStatus] = [:] // chapterId: status

        @Published var bookmarked = false

        @Published var nextChapter: AidokuRunner.Chapter?
        @Published var readingInProgress = false
        @Published var allChaptersLocked = false
        @Published var allChaptersRead = false
        @Published var initialDataLoaded = false

        @Published var chapterSortOption: ChapterSortOption = .sourceOrder {
            didSet { resortChapters() }
        }
        @Published var chapterSortAscending = false {
            didSet { resortChapters() }
        }

        @Published var chapterFilters: [ChapterFilterOption] = [] {
            didSet { refilterChapters() }
        }
        @Published var chapterLangFilter: String? {
            didSet { refilterChapters() }
        }
        @Published var chapterScanlatorFilter: [String] = [] {
            didSet { refilterChapters() }
        }

        @Published var error: Error?

        private var fetchedDetails = false
        private var cancellables = Set<AnyCancellable>()

        init(source: AidokuRunner.Source, manga: AidokuRunner.Manga) {
            self.source = source
            self.manga = manga
            setupNotifications()
        }

        private func setupNotifications() {
            NotificationCenter.default.publisher(for: .updateMangaDetails)
                .sink { [weak self] output in
                    guard
                        let self,
                        let manga = output.object as? AidokuRunner.Manga,
                        manga.sourceKey == self.manga.sourceKey,
                        manga.key == self.manga.key
                    else {
                        return
                    }
                    self.manga = manga
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .addToLibrary)
                .sink { [weak self] output in
                    guard
                        let self,
                        let manga = output.object as? Manga,
                        manga.key == self.manga.sourceKey + "." + self.manga.key
                    else {
                        return
                    }
                    Task {
                        await self.loadBookmarked()
                    }
                }
                .store(in: &cancellables)

            // todo: can't change the source
//            NotificationCenter.default.publisher(for: .migratedManga)
//                .sink { [weak self] output in
//                    guard
//                        let self,
//                        let migration = output.object as? (from: Manga, to: Manga),
//                        migration.from.id == self.manga.key && migration.from.sourceId == source.key,
//                        let newSource = SourceManager.shared.source(for: migration.to.sourceId)
//                    else { return }
//                    self.source = newSource
//                    manga = migration.to.toNew()
//                }
//                .store(in: &cancellables)

            // history
            NotificationCenter.default.publisher(for: .updateHistory)
                .sink { [weak self] _ in
                    Task {
                        await self?.loadHistory()
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .historyAdded)
                .sink { [weak self] output in
                    guard
                        let self,
                        let chapters = output.object as? [Chapter]
                    else { return }
                    let date = Int(Date().timeIntervalSince1970)
                    for chapter in chapters {
                        self.readingHistory[chapter.id] = (page: -1, date: date)
                    }
                    self.updateReadButton()
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .historyRemoved)
                .sink { [weak self] output in
                    guard let self else { return }
                    if let chapters = output.object as? [Chapter] {
                        for chapter in chapters {
                            self.readingHistory.removeValue(forKey: chapter.id)
                        }
                    } else if
                        let manga = output.object as? Manga,
                        manga.id == self.manga.key && manga.sourceId == source.key
                    {
                        self.readingHistory = [:]
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .historySet)
                .sink { [weak self] output in
                    guard
                        let self,
                        let item = output.object as? (chapter: Chapter, page: Int),
                        self.readingHistory[item.chapter.id]?.page != -1
                    else {
                        return
                    }
                    self.readingHistory[item.chapter.id] = (
                        page: item.page,
                        date: Int(Date().timeIntervalSince1970)
                    )
                    self.updateReadButton()
                }
                .store(in: &cancellables)

            // downloads
            NotificationCenter.default.publisher(for: .downloadsQueued)
                .sink { [weak self] output in
                    guard let self, let downloads = output.object as? [Download] else { return }
                    let chapters = downloads.compactMap {
                        if $0.chapter?.mangaId == self.manga.key && $0.chapter?.sourceId == self.manga.sourceKey {
                            $0.chapter
                        } else {
                            nil
                        }
                    }
                    for chapter in chapters {
                        self.downloadProgress[chapter.id] = 0
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .downloadProgressed)
                .sink { [weak self] output in
                    guard
                        let self,
                        let download = output.object as? Download,
                        let chapter = download.chapter,
                        chapter.mangaId == self.manga.key && chapter.sourceId == self.manga.sourceKey
                    else { return }
                    self.downloadProgress[chapter.id] = Float(download.progress) / Float(download.total)
                }
                .store(in: &cancellables)

            for name in [
                Notification.Name.downloadFinished,
                Notification.Name.downloadRemoved,
                Notification.Name.downloadCancelled
            ] {
                NotificationCenter.default.publisher(for: name)
                    .sink { [weak self] output in
                        self?.removeDownload(output)
                    }
                    .store(in: &cancellables)
            }

            for name in [
                Notification.Name.downloadsRemoved,
                Notification.Name.downloadsCancelled
            ] {
                NotificationCenter.default.publisher(for: name)
                    .sink { [weak self] output in
                        self?.removeDownloads(output)
                    }
                    .store(in: &cancellables)
            }
        }
    }
}

extension MangaView.ViewModel {
    // fetch complete info for manga, called when view appears
    func fetchDetails() async {
        guard !fetchedDetails else { return }
        fetchedDetails = true

        let filters = CoreDataManager.shared.getMangaChapterFilters(
            sourceId: source.key,
            mangaId: manga.key
        )
        chapterSortOption = .init(flags: filters.flags)
        chapterSortAscending = filters.flags & ChapterFlagMask.sortAscending != 0
        chapterFilters = ChapterFilterOption.parseOptions(flags: filters.flags)
        chapterLangFilter = filters.language
        chapterScanlatorFilter = filters.scanlators ?? []

        await loadBookmarked()
        await loadHistory()
        await fetchData()
    }

    // fetches manga data, from coredata if in library or from source if not
    func fetchData() async {
        let sourceKey = manga.sourceKey
        let mangaId = manga.key
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(sourceId: sourceKey, mangaId: mangaId, context: context)
        }
        if inLibrary {
            // load data from db
            let (chapters, manga) = await CoreDataManager.shared.container.performBackgroundTask { context in
                (
                    CoreDataManager.shared.getChapters(
                        sourceId: sourceKey,
                        mangaId: mangaId,
                        context: context
                    ).map {
                        $0.toNewChapter()
                    },
                    CoreDataManager.shared.getManga(
                        sourceId: sourceKey,
                        mangaId: mangaId,
                        context: context
                    )?.toNewManga()
                )
            }
            var newManga = self.manga
            if let manga {
                newManga = self.manga.copy(from: manga)
            }
            newManga.chapters = chapters
            withAnimation {
                self.manga = newManga
                self.chapters = filteredChapters()
            }
        } else {
            // load new data from source
            await source.partialMangaPublisher?.sink { @Sendable newManga in
                Task { @MainActor in
                    withAnimation {
                        self.manga = self.manga.copy(from: newManga)
                        self.chapters = self.filteredChapters()
                    }
                }
            }
            do {
                let newManga = try await source.getMangaUpdate(
                    manga: manga,
                    needsDetails: true,
                    needsChapters: true
                )
                withAnimation {
                    manga = newManga
                    chapters = filteredChapters()
                }
            } catch {
                withAnimation {
                    self.manga.chapters = []
                    self.chapters = []
                    self.error = error
                }
            }
            await source.partialMangaPublisher?.removeSink()
        }
        await loadDownloadStatus()
        updateReadButton()
        initialDataLoaded = true
    }

    // refresh manga and chapter data from source, updating db
    func refresh() async {
        guard Reachability.getConnectionType() != .none else {
            return
        }

        let sourceKey = source.key
        let mangaId = manga.key

        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(sourceId: sourceKey, mangaId: mangaId, context: context)
        }

        do {
            let oldManga = self.manga
            var newManga = try await source.getMangaUpdate(
                manga: oldManga,
                needsDetails: true,
                needsChapters: true
            )

            // update manga in db
            if inLibrary {
                let result = await CoreDataManager.shared.updateMangaDetails(manga: newManga.toOld())
                newManga = result?.toNew(chapters: newManga.chapters) ?? newManga
            }

            // update chapters in db
            if inLibrary, let chapters = newManga.chapters {
                let langFilter = chapterLangFilter
                let scanlatorFilter = chapterScanlatorFilter
                let sourceKey = source.key
                await CoreDataManager.shared.container.performBackgroundTask { context in
                    let newChapters = CoreDataManager.shared.setChapters(
                        chapters,
                        sourceId: sourceKey,
                        mangaId: newManga.key,
                        context: context
                    )
                    // update manga updates
                    for chapter in newChapters
                    where
                    langFilter != nil ? chapter.lang == langFilter : true
                    && !scanlatorFilter.isEmpty ? scanlatorFilter.contains(chapter.scanlator ?? "") : true
                    {
                        CoreDataManager.shared.createMangaUpdate(
                            sourceId: sourceKey,
                            mangaId: newManga.key,
                            chapterObject: chapter,
                            context: context
                        )
                    }
                    try? context.save()
                }
            }

            await loadHistory()

            withAnimation {
                manga = newManga
                chapters = filteredChapters()
            }
        } catch {
            withAnimation {
                self.manga.chapters = []
                self.chapters = []
                self.error = error
            }
        }

        updateReadButton()
    }

    private func loadDownloadStatus() async {
        let sourceKey = source.key
        let mangaKey = manga.key
        // todo: downloadmanager needs to be moved off of mainactor since this causes hangs when loading large amounts of chapters
        for chapter in chapters {
            downloadStatus[chapter.key] = DownloadManager.shared.getDownloadStatus(
                for: chapter.toOld(sourceId: sourceKey, mangaId: mangaKey)
            )
        }
    }

    private func loadBookmarked() async {
        let sourceKey = source.key
        let mangaId = manga.key
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.hasLibraryManga(
                sourceId: sourceKey,
                mangaId: mangaId,
                context: context
            )
        }
        bookmarked = inLibrary
    }

    private func loadHistory() async {
        readingHistory = await CoreDataManager.shared.getReadingHistory(
            sourceId: source.key,
            mangaId: manga.key
        )
    }
}

extension MangaView.ViewModel {
    // mark given chapters as read in coredata
    func markRead(chapters: [AidokuRunner.Chapter]) async {
        // only mark chapters that are readable as read
        let chapters = chapters.filter { !$0.locked || downloadStatus[$0.key] == .finished }

        await HistoryManager.shared.addHistory(
            sourceId: source.key,
            mangaId: manga.key,
            chapters: chapters
        )
        let date = Int(Date().timeIntervalSince1970)
        for chapter in chapters {
            readingHistory[chapter.key] = (page: -1, date: date)
        }
        updateReadButton()
    }

    // remove coredata history for given chapters
    func markUnread(chapters: [AidokuRunner.Chapter]) async {
        await HistoryManager.shared.removeHistory(
            sourceId: source.key,
            mangaId: manga.key,
            chapters: chapters
        )
        for chapter in chapters {
            readingHistory[chapter.key] = nil
        }
        updateReadButton()
    }

    // returns the latest chapter read from a tracker if the local history needs to be synced
    func checkTrackerSync(item: TrackItem) async -> Float? {
        guard
            item.mangaId == self.manga.key && item.sourceId == source.key,
            let tracker = TrackerManager.shared.getTracker(id: item.trackerId),
            let chapters = manga.chapters
        else { return nil }

        let latestChapterNum = chapters.max {
            $0.chapterNumber ?? -1 > $1.chapterNumber ?? -1
        }?.chapterNumber ?? -1
        let lastReadChapterNum = chapters.first {
            readingHistory[$0.key]?.page ?? 0 == -1
        }?.chapterNumber ?? 0 // if not started, 0
        let hasUnreadChapters = chapters.contains {
            readingHistory[$0.key] == nil
        }
        let trackerState = await tracker.getState(trackId: item.id)

        if let trackerLastReadChapter = trackerState.lastReadChapter {
            // check if latest read chapter is below tracker last read
            var shouldSync = (lastReadChapterNum < trackerLastReadChapter)
                // check if there are chapters to actually mark read
                && (latestChapterNum >= trackerLastReadChapter || hasUnreadChapters)

            if !shouldSync && hasUnreadChapters {
                // see if there are unread chapters under the last read that are unread and below tracker last read
                shouldSync = chapters.contains {
                    readingHistory[$0.key] == nil
                    && $0.chapterNumber ?? 0 < trackerLastReadChapter
                }
            }

            if shouldSync {
//                    syncWithTracker(chapterNum: trackerLastReadChapter)
                return trackerLastReadChapter
            }
        }

        return nil
    }

    private func resortChapters() {
        withAnimation {
            chapters = sortedChapters()
        }
        if bookmarked {
            Task {
                await saveFilters()
            }
        }
    }

    private func refilterChapters() {
        withAnimation {
            chapters = filteredChapters()
        }
        if bookmarked {
            Task {
                await saveFilters()
            }
        }
    }

    private func removeDownload(_ notification: Notification) {
        var chapter: Chapter?
        if let chapterCast = notification.object as? Chapter {
            chapter = chapterCast
        } else if
            let download = notification.object as? Download,
            let chapterCast = download.chapter
        {
            chapter = chapterCast
        }
        if let chapter {
            downloadProgress.removeValue(forKey: chapter.id)
            downloadStatus[chapter.id] = DownloadManager.shared.getDownloadStatus(for: chapter)
        }
    }

    private func removeDownloads(_ notification: Notification) {
        if let chapters = notification.object as? [Chapter] {
            for chapter in chapters {
                downloadProgress.removeValue(forKey: chapter.id)
                downloadStatus[chapter.id] = DownloadManager.shared.getDownloadStatus(
                    for: chapter
                )
            }
        } else if
            let manga = notification.object as? Manga,
            manga.id == self.manga.key && manga.sourceId == self.source.key
        { // all chapters
            downloadProgress = [:]
            for chapter in self.manga.chapters ?? chapters {
                downloadStatus[chapter.key] = DownloadStatus.none
            }
        }
    }

    private func sortedChapters() -> [AidokuRunner.Chapter] {
        guard let chapters = manga.chapters, !chapters.isEmpty else {
            return []
        }
        return switch chapterSortOption {
            case .sourceOrder:
                chapterSortAscending ? chapters.reversed() : chapters
            case .chapter:
                if chapterSortAscending {
                    chapters.sorted(by: { $0.chapterNumber ?? -1 < $1.chapterNumber ?? -1 })
                } else {
                    chapters.sorted(by: { $0.chapterNumber ?? -1 > $1.chapterNumber ?? -1 })
                }
            case .uploadDate:
                if chapterSortAscending {
                    chapters.sorted(by: { $0.dateUploaded ?? .distantPast < $1.dateUploaded ?? .distantPast })
                } else {
                    chapters.sorted(by: { $0.dateUploaded ?? .distantPast > $1.dateUploaded ?? .distantPast })
                }
        }
    }

    private func filteredChapters() -> [AidokuRunner.Chapter] {
        var chapters = sortedChapters()

        // filter by language and scanlators
        if chapterLangFilter != nil || !chapterScanlatorFilter.isEmpty {
            chapters = chapters.filter { chapter in
                let cond1 = if let chapterLangFilter {
                    chapter.language == chapterLangFilter
                } else {
                    true
                }
                let cond2 = if !chapterScanlatorFilter.isEmpty  {
                    chapterScanlatorFilter.contains(where: (chapter.scanlators ?? []).contains)
                } else {
                    true
                }
                return cond1 && cond2
            }
        }

        for filter in chapterFilters {
            switch filter.type {
                case .downloaded:
                    chapters = chapters.filter {
                        let downloaded = !DownloadManager.shared.isChapterDownloaded(sourceId: source.key, mangaId: manga.key, chapterId: $0.key)
                        return filter.exclude ? downloaded : !downloaded
                    }
                case .unread:
                    chapters = chapters.filter {
                        let isCompleted = self.readingHistory[$0.id]?.0 == -1
                        return filter.exclude ? isCompleted : !isCompleted
                    }
                case .locked:
                    chapters = chapters.filter {
                        filter.exclude ? !$0.locked : $0.locked
                    }
            }
        }

        return chapters
    }

    enum ChapterResult {
        case none
        case allRead
        case allLocked
        case chapter(AidokuRunner.Chapter)
    }

    private func getNextChapter() -> ChapterResult {
        guard !chapters.isEmpty else { return .none }
        // get first chapter not completed
        let chapter = chapters.reversed().first(
            where: { (!$0.locked || downloadStatus[$0.key] == .finished) && readingHistory[$0.id]?.page ?? 0 != -1 }
        )
        if let chapter {
            return .chapter(chapter)
        }
        if !chapters.contains(where: { !$0.locked }) {
            return .allLocked
        }
        return .allRead
    }

    private func updateReadButton() {
        let nextChapter = getNextChapter()
        switch nextChapter {
            case .none:
                return
            case .allRead:
                allChaptersRead = true
                allChaptersLocked = false
            case .allLocked:
                allChaptersLocked = true
            case .chapter(let nextChapter):
                allChaptersRead = false
                allChaptersLocked = false
                readingInProgress = readingHistory[nextChapter.id]?.date ?? 0 > 0
                self.nextChapter = nextChapter
        }
    }

    private func generateChapterFlags() -> Int {
        var flags: Int = 0
        if chapterSortAscending {
            flags |= ChapterFlagMask.sortAscending
        }
        flags |= chapterSortOption.rawValue << 1
        for filter in chapterFilters {
            switch filter.type {
                case .downloaded:
                    flags |= ChapterFlagMask.downloadFilterEnabled
                    if filter.exclude {
                        flags |= ChapterFlagMask.downloadFilterExcluded
                    }
                case .unread:
                    flags |= ChapterFlagMask.unreadFilterEnabled
                    if filter.exclude {
                        flags |= ChapterFlagMask.unreadFilterExcluded
                    }
                case .locked:
                    flags |= ChapterFlagMask.lockedFilterEnabled
                    if filter.exclude {
                        flags |= ChapterFlagMask.lockedFilterExcluded
                    }
            }
        }
        return flags
    }

    private func saveFilters() async {
        let manga = manga.toOld()
        manga.chapterFlags = generateChapterFlags()
        manga.langFilter = chapterLangFilter
        manga.scanlatorFilter = chapterScanlatorFilter
        await CoreDataManager.shared.updateMangaDetails(manga: manga)
    }
}
