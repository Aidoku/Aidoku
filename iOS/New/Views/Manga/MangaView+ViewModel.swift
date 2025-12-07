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
        weak var source: AidokuRunner.Source?

        @Published var manga: AidokuRunner.Manga
        @Published var chapters: [AidokuRunner.Chapter] = []
        @Published var otherDownloadedChapters: [AidokuRunner.Chapter] = []

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

        @Published var chapterTitleDisplayMode: ChapterTitleDisplayMode

        @Published var error: Error?

        private var fetchedDetails = false
        private var cancellables = Set<AnyCancellable>()

        init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
            self.source = source
            self.manga = manga

            let key = "Manga.chapterDisplayMode.\(manga.uniqueKey)"
            self.chapterTitleDisplayMode = .init(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default

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

            NotificationCenter.default.publisher(for: .migratedManga)
                .sink { [weak self] output in
                    guard
                        let self,
                        let migration = output.object as? (from: Manga, to: Manga),
                        migration.from.id == self.manga.key && migration.from.sourceId == manga.sourceKey,
                        let newSource = SourceManager.shared.source(for: migration.to.sourceId)
                    else { return }
                    self.source = newSource
                    manga = migration.to.toNew()
                }
                .store(in: &cancellables)

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
                    for chapter in chapters where chapter.mangaIdentifier == self.manga.identifier {
                        self.readingHistory[chapter.id] = (page: -1, date: date)
                    }
                    self.updateReadButton()
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .historyRemoved)
                .sink { [weak self] output in
                    guard let self else { return }
                    if let chapters = output.object as? [Chapter] {
                        for chapter in chapters where chapter.mangaIdentifier == self.manga.identifier {
                            self.readingHistory.removeValue(forKey: chapter.id)
                        }
                    } else if
                        let manga = output.object as? Manga,
                        manga.identifier == self.manga.identifier
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
                        item.chapter.mangaIdentifier == self.manga.identifier,
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

            // tracking
            NotificationCenter.default.publisher(for: .syncTrackItem)
                .sink { [weak self] output in
                    guard let self, let item = output.object as? TrackItem else { return }
                    Task {
                        if let tracker = TrackerManager.getTracker(id: item.trackerId) {
                            await TrackerManager.shared.syncProgressFromTracker(
                                tracker: tracker,
                                trackId: item.id,
                                manga: self.manga,
                                chapters: self.chapters
                            )
                        }
                    }
                }
                .store(in: &cancellables)

            // downloads
            NotificationCenter.default.publisher(for: .downloadsQueued)
                .sink { [weak self] output in
                    guard let self, let downloads = output.object as? [Download] else { return }
                    let chapters = downloads.compactMap {
                        if $0.mangaIdentifier == self.manga.identifier {
                            $0.chapter
                        } else {
                            nil
                        }
                    }
                    for chapter in chapters {
                        self.downloadStatus[chapter.key] = .queued
                        self.downloadProgress[chapter.key] = 0
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .downloadProgressed)
                .sink { [weak self] output in
                    guard
                        let self,
                        let download = output.object as? Download,
                        download.mangaIdentifier == self.manga.identifier
                    else { return }
                    self.downloadStatus[download.chapterIdentifier.chapterKey] = .downloading
                    self.downloadProgress[download.chapterIdentifier.chapterKey] = Float(download.progress) / Float(download.total)
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
    func markOpened() async {
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            await MangaUpdateManager.shared.viewAllUpdates(of: manga)
        }
    }

    // fetch complete info for manga, called when view appears
    func fetchDetails() async {
        guard !fetchedDetails else { return }
        fetchedDetails = true

        if let cachedManga = CoreDataManager.shared.getManga(sourceId: self.manga.sourceKey, mangaId: self.manga.key) {
            self.manga = self.manga.copy(from: cachedManga.toNewManga())
        }

        let filters = CoreDataManager.shared.getMangaChapterFilters(
            sourceId: manga.sourceKey,
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
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.hasLibraryManga(sourceId: sourceKey, mangaId: mangaId, context: context)
        }
        if inLibrary {
            // load data from db
            let chapters = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                CoreDataManager.shared.getChapters(
                    sourceId: sourceKey,
                    mangaId: mangaId,
                    context: context
                ).map {
                    $0.toNewChapter()
                }
            }

            var newManga = self.manga
            newManga.chapters = chapters
            withAnimation {
                self.manga = newManga
                self.chapters = filteredChapters()
            }
        } else if let source {
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
        await fetchDownloadedChapters()
        await loadDownloadStatus()
        updateReadButton()
        initialDataLoaded = true
    }

    func fetchDownloadedChapters() async {
        let downloadedChapters = await DownloadManager.shared.getDownloadedChapters(for: manga.identifier)
            .filter { chapter in
                !(manga.chapters ?? chapters).contains(where: { $0.key.directoryName == chapter.chapterId.directoryName })
            }
            .map { $0.toChapter() }
            .sorted { (lhs: AidokuRunner.Chapter, rhs: AidokuRunner.Chapter) in
                // Primary sort: by chapter number if both have it
                if let lhsChapter = lhs.chapterNumber, let rhsChapter = rhs.chapterNumber {
                    if lhsChapter != rhsChapter {
                        return lhsChapter > rhsChapter
                    }
                    // If chapter numbers are equal, sort by volume number
                    if let lhsVolume = lhs.volumeNumber, let rhsVolume = rhs.volumeNumber {
                        return lhsVolume > rhsVolume
                    }
                }

                // Secondary sort: by volume number if only one has chapter number
                if let lhsVolume = lhs.volumeNumber, let rhsVolume = rhs.volumeNumber {
                    return lhsVolume > rhsVolume
                }

                // Final fallback: alphabetical comparison of display titles
                let lhsTitle = lhs.title?.lowercased() ?? ""
                let rhsTitle = rhs.title?.lowercased() ?? ""
                return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedDescending
            }
        withAnimation {
            otherDownloadedChapters = downloadedChapters
        }
    }

    func syncTrackerProgress() async {
        // sync progress from page trackers
        await TrackerManager.shared.syncPageTrackerHistory(
            manga: manga,
            chapters: chapters
        )

        // sync progress from regular trackers if auto sync enabled
        if UserDefaults.standard.bool(forKey: "Tracking.autoSyncFromTracker") {
            let trackItems: [TrackItem] = await CoreDataManager.shared.container.performBackgroundTask { @Sendable [manga] context in
                CoreDataManager.shared.getTracks(
                    sourceId: manga.sourceKey,
                    mangaId: manga.key,
                    context: context
                ).map { $0.toItem() }
            }
            for trackItem in trackItems {
                guard let tracker = TrackerManager.getTracker(id: trackItem.trackerId) else { continue }
                await TrackerManager.shared.syncProgressFromTracker(
                    tracker: tracker,
                    trackId: trackItem.id,
                    manga: manga,
                    chapters: chapters
                )
            }
        }
    }

    // refresh manga and chapter data from source, updating db
    func refresh() async {
        guard Reachability.getConnectionType() != .none, let source else {
            return
        }

        let sourceKey = source.key
        let mangaId = manga.key

        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
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

                if let chapters = newManga.chapters {
                    let sourceKey = source.key
                    let mangaKey = newManga.key
                    await CoreDataManager.shared.container.performBackgroundTask { @Sendable [chapterLangFilter, chapterScanlatorFilter] context in
                        let newChapters = CoreDataManager.shared.setChapters(
                            chapters,
                            sourceId: sourceKey,
                            mangaId: mangaKey,
                            context: context
                        )
                        // update manga updates
                        for chapter in newChapters
                        where
                            chapterLangFilter != nil ? chapter.lang == chapterLangFilter : true
                            && !chapterScanlatorFilter.isEmpty ? chapterScanlatorFilter.contains(chapter.scanlator ?? "") : true
                        {
                            CoreDataManager.shared.createMangaUpdate(
                                sourceId: sourceKey,
                                mangaId: mangaKey,
                                chapterObject: chapter,
                                context: context
                            )
                        }
                        try? context.save()
                    }
                    await markOpened()
                }
            }

            NotificationCenter.default.post(name: .updateChapters, object: newManga.identifier)

            await loadHistory()

            withAnimation {
                manga = newManga
                chapters = filteredChapters()
            }

            // ensure downloaded chapters are in the correct section if they were added/removed from the main list
            await fetchDownloadedChapters()
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
        for chapter in chapters {
            downloadStatus[chapter.key] = DownloadManager.shared.getDownloadStatus(
                for: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
            )
        }
        for chapter in otherDownloadedChapters {
            downloadStatus[chapter.key] = .finished
        }
    }

    private func loadBookmarked() async {
        let sourceKey = manga.sourceKey
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
            sourceId: manga.sourceKey,
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
            sourceId: manga.sourceKey,
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
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            chapterIds: chapters.map { $0.key }
        )
        for chapter in chapters {
            readingHistory[chapter.key] = nil
        }
        updateReadButton()
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
        var chapter: ChapterIdentifier?
        if let identifier = notification.object as? ChapterIdentifier {
            chapter = identifier
        } else if let download = notification.object as? Download {
            chapter = download.chapterIdentifier
        }
        if let chapter {
            downloadProgress.removeValue(forKey: chapter.chapterKey)
            downloadStatus[chapter.chapterKey] = DownloadManager.shared.getDownloadStatus(for: chapter)
            if let chapterIndex = otherDownloadedChapters.firstIndex(where: { $0.key == chapter.chapterKey }) {
                withAnimation {
                    _ = otherDownloadedChapters.remove(at: chapterIndex)
                }
            }
        }
    }

    private func removeDownloads(_ notification: Notification) {
        if let chapters = notification.object as? [ChapterIdentifier] {
            for chapter in chapters {
                downloadProgress.removeValue(forKey: chapter.chapterKey)
                downloadStatus[chapter.chapterKey] = DownloadStatus.none
            }
        } else if
            let manga = notification.object as? MangaIdentifier,
            manga == self.manga.identifier
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
                        let downloaded = !DownloadManager.shared.isChapterDownloaded(
                            chapter: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
                        )
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

        // Find most recently read chapter (by date)
        let lastRead = readingHistory
            .filter { $0.value.date > 0 }
            .max { $0.value.date < $1.value.date }

        if let (lastReadId, lastReadInfo) = lastRead {
            // Find the chapter object
            // If the chapter is filtered out (e.g. by lang), we might still want to know it was last read
            // but we likely can't "continue" it if it's not in the list.
            // But we should check `manga.chapters` for full list if needed?
            // "Continue Reading" usually implies continuing what's visible or logical.
            // Let's stick to visible chapters for now to avoid playing hidden chapters.
            // Actually, if I hide "read" chapters, the last read one is hidden.
            // So we should look at the full sorted list to find the "next" one.

            let sorted = sortedChapters()
            if let chapter = sorted.first(where: { $0.id == lastReadId }) {
                // If incomplete, resume this chapter
                if lastReadInfo.page != -1 {
                    return .chapter(chapter)
                }

                // If completed, find the next chapter in the sorted list
                if let index = sorted.firstIndex(where: { $0.id == lastReadId }) {
                    let nextChapters = sorted.suffix(from: index + 1)
                    if let next = nextChapters.first(where: { (!$0.locked || downloadStatus[$0.key] == .finished) }) {
                        return .chapter(next)
                    }
                }
            }
        }

        // Fallback: get first chapter not completed
        let chapter = (chapterSortAscending ? chapters : chapters.reversed()).first(
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
