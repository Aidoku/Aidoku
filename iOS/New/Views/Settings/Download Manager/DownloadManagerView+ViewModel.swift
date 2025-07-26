//
//  DownloadManagerView+ViewModel.swift
//  Aidoku
//
//  Created by Skitty on 7/21/25.
//

import SwiftUI
import Combine

extension DownloadManagerView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var downloadedManga: [DownloadedMangaInfo] = []
        @Published var isLoading = true
        @Published var totalSize: String = ""
        @Published var totalCount = 0
        @Published var showingDeleteAllConfirmation = false

        // Non-reactive state for background updates
        private var backgroundUpdateInProgress = false
        private var lastUpdateId = UUID()
        private var updateDebouncer: Timer?
        private var cancellables = Set<AnyCancellable>()

        init() {
            setupNotificationObservers()
        }

        deinit {
            updateDebouncer?.invalidate()
        }
    }
}

extension DownloadManagerView.ViewModel {
    // Group manga by source for sectioned display
    var groupedManga: [(source: String, manga: [DownloadedMangaInfo])] {
        let grouped = Dictionary(grouping: downloadedManga) { $0.sourceId }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (source: getSourceDisplayName($0.key), manga: $0.value) }
    }

    func loadDownloadedManga() async {
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isLoading = true
            }
        }

        let manga = await DownloadManager.shared.getAllDownloadedManga()
        let formattedSize = await DownloadManager.shared.getFormattedTotalDownloadedSize()

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.downloadedManga = manga
                self.totalSize = formattedSize
                self.totalCount = manga.count
                self.isLoading = false
            }
        }
    }

    /// Background update that preserves user navigation and minimizes UI disruption
    private func performBackgroundUpdate() async {
        // Prevent concurrent background updates
        guard !backgroundUpdateInProgress else { return }
        backgroundUpdateInProgress = true
        defer { backgroundUpdateInProgress = false }

        let updateId = UUID()
        lastUpdateId = updateId

        // Fetch new data in background
        let newManga = await DownloadManager.shared.getAllDownloadedManga()
        let newFormattedSize = await DownloadManager.shared.getFormattedTotalDownloadedSize()

        await MainActor.run {
            // Check if this update is still relevant (not superseded by another)
            guard updateId == lastUpdateId else { return }

            // Perform selective updates using intelligent diffing
            updateDataSelectively(
                newManga: newManga,
                newTotalSize: newFormattedSize
            )
        }
    }

    /// Intelligently update only changed data to preserve navigation state
    private func updateDataSelectively(newManga: [DownloadedMangaInfo], newTotalSize: String) {
        let oldManga = downloadedManga

        // Update totals immediately as they don't affect navigation
        totalSize = newTotalSize
        totalCount = newManga.count

        // Only update manga list if there are actual changes
        if !areMangaListsEqual(oldManga, newManga) {
            // Use smooth animation for data changes
            withAnimation(.easeInOut(duration: 0.3)) {
                downloadedManga = newManga
            }
        }
    }

    /// Compare manga lists efficiently to avoid unnecessary updates
    private func areMangaListsEqual(_ lhs: [DownloadedMangaInfo], _ rhs: [DownloadedMangaInfo]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        // Quick comparison by ID and key properties
        for (old, new) in zip(lhs, rhs) {
            if old.id != new.id ||
               old.totalSize != new.totalSize ||
               old.chapterCount != new.chapterCount ||
               old.isInLibrary != new.isInLibrary {
                return false
            }
        }
        return true
    }

    /// Debounced update to prevent excessive refreshes
    private func scheduleBackgroundUpdate() {
        updateDebouncer?.invalidate()
        updateDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task {
                await self?.performBackgroundUpdate()
            }
        }
    }

    private func setupNotificationObservers() {
        // High-priority updates that need immediate response
        let immediateUpdateNotifications: [NSNotification.Name] = [
            .downloadRemoved,
            .downloadsRemoved
        ]

        for notification in immediateUpdateNotifications {
            NotificationCenter.default.publisher(for: notification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    Task {
                        await self?.performBackgroundUpdate()
                    }
                }
                .store(in: &cancellables)
        }

        // Low-priority updates that can be debounced
        let debouncedUpdateNotifications: [NSNotification.Name] = [
            .downloadFinished,
            .downloadsCancelled,
            .downloadsQueued,
            .downloadsPaused,
            .downloadsResumed,
            .addToLibrary,
            .removeFromLibrary,
            .updateLibrary,
            .updateHistory
        ]

        for notification in debouncedUpdateNotifications {
            NotificationCenter.default.publisher(for: notification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.scheduleBackgroundUpdate()
                }
                .store(in: &cancellables)
        }
    }

    private func getSourceDisplayName(_ sourceId: String) -> String {
        if let source = SourceManager.shared.source(for: sourceId) {
            return source.name
        }
        // Fall back to source ID for unknown sources
        return sourceId.capitalized
    }

    func deleteAllChapters() {
        // clear manga in ui
        withAnimation(.easeOut(duration: 0.3)) {
            downloadedManga = []
        }

        DownloadManager.shared.deleteAll()
    }

    func confirmDeleteAll() {
        showingDeleteAllConfirmation = true
    }
}
