//
//  DownloadedMangaView+ViewModel.swift
//  Aidoku
//
//  Created by Skitty on 7/21/25.
//

import SwiftUI
import Combine
import AidokuRunner

extension DownloadedMangaView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var manga: DownloadedMangaInfo

        @Published var chapters: [DownloadedChapterInfo] = []
        @Published var isLoading = true
        @Published var showingDeleteAllConfirmation = false
        @Published var sortAscending = true
        @Published var readingHistory: [String: (page: Int, date: Int)] = [:]

        // Non-reactive state for background management
        private var backgroundUpdateInProgress = false
        private var lastUpdateId = UUID()
        private var updateDebouncer: Timer?
        private var cancellables = Set<AnyCancellable>()

        init(manga: DownloadedMangaInfo) {
            self.manga = manga
            // Load sort preference from UserDefaults
            self.sortAscending = UserDefaults.standard.bool(forKey: "downloadChapterSortAscending")
            setupNotificationObservers()
        }
    }
}

extension DownloadedMangaView.ViewModel {
    func loadChapters() async {
        isLoading = true

        let downloadedChapters = await DownloadManager.shared.getDownloadedChapters(for: manga.mangaIdentifier)

        await MainActor.run {
            self.chapters = self.sortChapters(downloadedChapters)
            self.isLoading = false
        }
    }

    func loadHistory() async {
        readingHistory = await CoreDataManager.shared.getReadingHistory(
            sourceId: manga.sourceId,
            mangaId: manga.mangaId
        )
    }

    func toggleSortOrder() {
        sortAscending.toggle()
        // Save sort preference to UserDefaults
        UserDefaults.standard.set(sortAscending, forKey: "downloadChapterSortAscending")
        chapters = sortChapters(chapters)
    }

    private func sortChapters(_ chapters: [DownloadedChapterInfo]) -> [DownloadedChapterInfo] {
        let sorted = chapters.sorted { lhs, rhs in
            // Primary sort: by chapter number if both have it
            if let lhsChapter = lhs.chapterNumber, let rhsChapter = rhs.chapterNumber {
                if lhsChapter != rhsChapter {
                    return lhsChapter < rhsChapter
                }
                // If chapter numbers are equal, sort by volume number
                if let lhsVolume = lhs.volumeNumber, let rhsVolume = rhs.volumeNumber {
                    return lhsVolume < rhsVolume
                }
            }

            // Secondary sort: by volume number if only one has chapter number
            if let lhsVolume = lhs.volumeNumber, let rhsVolume = rhs.volumeNumber {
                return lhsVolume < rhsVolume
            }

            // Tertiary sort: by display title (which includes smart formatting)
            let lhsTitle = lhs.displayTitle.lowercased()
            let rhsTitle = rhs.displayTitle.lowercased()

            // Try to extract numbers from display titles for numeric comparison
            if let lhsNum = extractNumberFromTitle(lhsTitle),
               let rhsNum = extractNumberFromTitle(rhsTitle) {
                return lhsNum < rhsNum
            }

            // Final fallback: alphabetical comparison of display titles
            return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
        }

        return sortAscending ? sorted : sorted.reversed()
    }

    private func extractNumberFromTitle(_ title: String) -> Double? {
        // Look for patterns like "Chapter 1", "Ch. 15.5", "Episode 42", etc.
        let patterns = [
            #"(?:chapter|ch\.?|episode|ep\.?)\s*(\d+(?:\.\d+)?)"#,
            #"^(\d+(?:\.\d+)?)(?:\s|$)"#,  // Starting with number
            #"(\d+(?:\.\d+)?)$"#           // Ending with number
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                let numberString = String(title[range])
                if let number = Double(numberString) {
                    return number
                }
            }
        }

        return nil
    }

    /// Background update that preserves scroll position and selection state
    private func performBackgroundUpdate() async {
        guard !backgroundUpdateInProgress else { return }
        backgroundUpdateInProgress = true
        defer { backgroundUpdateInProgress = false }

        let updateId = UUID()
        lastUpdateId = updateId

        // Fetch updates in background
        let newChapters = await DownloadManager.shared.getDownloadedChapters(for: manga.mangaIdentifier)
        let updatedMangaStatus = await fetchUpdatedMangaLibraryStatus()

        guard updateId == lastUpdateId else { return }

        // Update library status immediately (doesn't affect list)
        if updatedMangaStatus != manga.isInLibrary {
            updateMangaLibraryStatus(to: updatedMangaStatus)
        }

        // Selective chapter list updates
        updateChaptersSelectively(newChapters: newChapters)
    }

    /// Update only changed chapters to preserve scroll position
    private func updateChaptersSelectively(newChapters: [DownloadedChapterInfo]) {
        let oldChapters = chapters

        // Quick equality check
        guard !areChapterListsEqual(oldChapters, newChapters) else { return }

        // Use gentle animation for list updates
        withAnimation(.easeInOut(duration: 0.25)) {
            chapters = sortChapters(newChapters)
        }
    }

    /// Efficient comparison to avoid unnecessary updates
    private func areChapterListsEqual(_ lhs: [DownloadedChapterInfo], _ rhs: [DownloadedChapterInfo]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        for (old, new) in zip(lhs, rhs) {
            if old.id != new.id || old.size != new.size {
                return false
            }
        }
        return true
    }

    /// Immediate update for user-initiated deletions
    func deleteChapter(_ chapter: DownloadedChapterInfo) {
        // Optimistically update UI immediately
        withAnimation(.easeOut(duration: 0.2)) {
            chapters.removeAll { $0.id == chapter.id }
        }

        // Perform actual deletion
        Task {
            await DownloadManager.shared.delete(chapters: [
                .init(
                    sourceKey: manga.sourceId,
                    mangaKey: manga.mangaId,
                    chapterKey: chapter.chapterId
                )
            ])
        }
    }

    func deleteAllChapters() {
        // Optimistically clear UI immediately
        withAnimation(.easeOut(duration: 0.3)) {
            chapters.removeAll()
        }

        // Perform actual deletion
        Task {
            await DownloadManager.shared.deleteChapters(for: manga.mangaIdentifier)
        }
    }

    func confirmDeleteAll() {
        showingDeleteAllConfirmation = true
    }

    /// Fetch updated library status without affecting the view
    private func fetchUpdatedMangaLibraryStatus() async -> Bool {
        await withCheckedContinuation { continuation in
            CoreDataManager.shared.container.performBackgroundTask { [manga] context in
                let hasLibraryManga = CoreDataManager.shared.hasLibraryManga(
                    sourceId: manga.sourceId,
                    mangaId: manga.mangaId,
                    context: context
                )
                continuation.resume(returning: hasLibraryManga)
            }
        }
    }

    /// Update manga library status without recreating the object
    private func updateMangaLibraryStatus(to newStatus: Bool) {
        manga = DownloadedMangaInfo(
            sourceId: manga.sourceId,
            mangaId: manga.mangaId,
            directoryMangaId: manga.directoryMangaId,
            title: manga.title,
            coverUrl: manga.coverUrl,
            totalSize: manga.totalSize,
            chapterCount: manga.chapterCount,
            isInLibrary: newStatus
        )
    }

    /// Schedule debounced background updates
    private func scheduleBackgroundUpdate() {
        updateDebouncer?.invalidate()
        updateDebouncer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task {
                await self?.performBackgroundUpdate()
            }
        }
    }

    private func setupNotificationObservers() {
        // Immediate updates for relevant manga operations
        let immediateNotifications: [(NSNotification.Name, (Notification) -> Bool)] = [
            (.downloadRemoved, { [weak self] notification in
                guard
                    let id = notification.object as? ChapterIdentifier,
                    id.mangaIdentifier == self?.manga.mangaIdentifier
                else { return false }
                return true
            }),
            (.downloadsRemoved, { [weak self] notification in
                guard
                    let id = notification.object as? MangaIdentifier,
                    id == self?.manga.mangaIdentifier
                else { return false }
                return true
            })
        ]

        for (notificationName, filter) in immediateNotifications {
            NotificationCenter.default.publisher(for: notificationName)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    if filter(notification) {
                        Task {
                            await self?.performBackgroundUpdate()
                        }
                    }
                }
                .store(in: &cancellables)
        }

        // Debounced updates for general events
        let debouncedNotifications: [(NSNotification.Name, (Notification) -> Bool)] = [
            (.downloadFinished, { [weak self] notification in
                guard let download = notification.object as? Download,
                      download.mangaIdentifier == self?.manga.mangaIdentifier
                else { return false }
                return true
            }),
            (.downloadsQueued, { [weak self] notification in
                guard let downloads = notification.object as? [Download] else { return false }
                return downloads.contains { $0.mangaIdentifier == self?.manga.mangaIdentifier }
            }),
            (.addToLibrary, { [weak self] notification in
                guard let addedManga = notification.object as? Manga,
                      addedManga.sourceId == self?.manga.sourceId,
                      addedManga.id == self?.manga.mangaId else { return false }
                return true
            }),
            (.removeFromLibrary, { [weak self] notification in
                guard let removedManga = notification.object as? AidokuRunner.Manga,
                      removedManga.sourceKey == self?.manga.sourceId,
                      removedManga.key == self?.manga.mangaId else { return false }
                return true
            })
        ]

        for (notificationName, filter) in debouncedNotifications {
            NotificationCenter.default.publisher(for: notificationName)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    if filter(notification) {
                        self?.scheduleBackgroundUpdate()
                    }
                }
                .store(in: &cancellables)
        }

        // General updates that might affect this manga
        let generalNotifications: [NSNotification.Name] = [
            .updateLibrary, .updateHistory
        ]

        for notification in generalNotifications {
            NotificationCenter.default.publisher(for: notification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.scheduleBackgroundUpdate()
                    Task {
                        await self?.loadHistory()
                    }
                }
                .store(in: &cancellables)
        }

        // reading history
        NotificationCenter.default.publisher(for: .historyAdded)
            .sink { [weak self] output in
                guard
                    let self,
                    let chapters = output.object as? [Chapter]
                else { return }
                let date = Int(Date().timeIntervalSince1970)
                for chapter in chapters where chapter.mangaIdentifier == self.manga.mangaIdentifier {
                    self.readingHistory[chapter.id] = (page: -1, date: date)
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
                for chapter in chapters where chapter.mangaIdentifier == self.manga.mangaIdentifier {
                    self.readingHistory[chapter.id] = (page: -1, date: date)
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .historyRemoved)
            .sink { [weak self] output in
                guard let self else { return }
                if let chapters = output.object as? [Chapter] {
                    for chapter in chapters where chapter.mangaIdentifier == self.manga.mangaIdentifier {
                        self.readingHistory.removeValue(forKey: chapter.id)
                    }
                } else if
                    let manga = output.object as? Manga,
                    manga.identifier == self.manga.mangaIdentifier
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
                    item.chapter.mangaIdentifier == self.manga.mangaIdentifier,
                    self.readingHistory[item.chapter.id]?.page != -1
                else {
                    return
                }
                self.readingHistory[item.chapter.id] = (
                    page: item.page,
                    date: Int(Date().timeIntervalSince1970)
                )
            }
            .store(in: &cancellables)
    }
}
