//
//  MangaDownloadDetailView.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import SwiftUI
import Combine
import AidokuRunner

@MainActor
class MangaDownloadDetailViewModel: ObservableObject {
    @Published var chapters: [DownloadedChapterInfo] = []
    @Published var isLoading = true
    @Published var showingDeleteAllConfirmation = false
    @Published var showingDeleteChapterConfirmation = false
    @Published var chapterToDelete: DownloadedChapterInfo?
    @Published var sortAscending = true

    @Published var manga: DownloadedMangaInfo

    // Non-reactive state for background management
    private var backgroundUpdateInProgress = false
    private var lastUpdateId = UUID()
    private var updateDebouncer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(manga: DownloadedMangaInfo) {
        self.manga = manga
        // Load sort preference from UserDefaults
        self.sortAscending = UserDefaults.standard.object(forKey: "downloadChapterSortAscending") as? Bool ?? true
        setupNotificationObservers()
    }

    func loadChapters() async {
        isLoading = true

        let downloadedChapters = await DownloadManager.shared.getDownloadedChapters(for: manga)

        await MainActor.run {
            self.chapters = self.sortChapters(downloadedChapters)
            self.isLoading = false
        }
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
        let newChapters = await DownloadManager.shared.getDownloadedChapters(for: manga)
        let updatedMangaStatus = await fetchUpdatedMangaLibraryStatus()

        await MainActor.run {
            guard updateId == lastUpdateId else { return }

            // Update library status immediately (doesn't affect list)
            if updatedMangaStatus != manga.isInLibrary {
                updateMangaLibraryStatus(to: updatedMangaStatus)
            }

            // Selective chapter list updates
            updateChaptersSelectively(newChapters: newChapters)
        }
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

        // Perform actual deletion in background
        Task {
            DownloadManager.shared.deleteChapter(chapter, from: manga)
        }
    }

    func deleteAllChapters() {
        // Optimistically clear UI immediately
        withAnimation(.easeOut(duration: 0.3)) {
            chapters.removeAll()
        }

        // Perform actual deletion in background
        Task {
            DownloadManager.shared.deleteChaptersForManga(manga)
        }
    }

    func confirmDeleteChapter(_ chapter: DownloadedChapterInfo) {
        chapterToDelete = chapter
        showingDeleteChapterConfirmation = true
    }

    func confirmDeleteAll() {
        showingDeleteAllConfirmation = true
    }

    /// Fetch updated library status without affecting the view
    private func fetchUpdatedMangaLibraryStatus() async -> Bool {
        await withCheckedContinuation { continuation in
            CoreDataManager.shared.container.performBackgroundTask { context in
                let hasLibraryManga = CoreDataManager.shared.hasLibraryManga(
                    sourceId: self.manga.sourceId,
                    mangaId: self.manga.mangaId,
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
            (NSNotification.Name("downloadRemoved"), { [weak self] notification in
                guard let chapter = notification.object as? Chapter,
                      chapter.sourceId == self?.manga.sourceId,
                      chapter.mangaId == self?.manga.mangaId else { return false }
                return true
            }),
            (NSNotification.Name("downloadsRemoved"), { [weak self] notification in
                guard let manga = notification.object as? Manga,
                      manga.sourceId == self?.manga.sourceId,
                      manga.id == self?.manga.mangaId else { return false }
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
            (NSNotification.Name("downloadFinished"), { [weak self] notification in
                guard let download = notification.object as? Download,
                      download.sourceId == self?.manga.sourceId,
                      download.mangaId == self?.manga.mangaId else { return false }
                return true
            }),
            (NSNotification.Name("downloadsQueued"), { [weak self] notification in
                guard let downloads = notification.object as? [Download] else { return false }
                return downloads.contains { $0.sourceId == self?.manga.sourceId && $0.mangaId == self?.manga.mangaId }
            }),
            (.addToLibrary, { [weak self] notification in
                guard let addedManga = notification.object as? Manga,
                      addedManga.sourceId == self?.manga.sourceId,
                      addedManga.id == self?.manga.mangaId else { return false }
                return true
            }),
            (NSNotification.Name("removeFromLibrary"), { [weak self] notification in
                guard let removedManga = notification.object as? Manga,
                      removedManga.sourceId == self?.manga.sourceId,
                      removedManga.id == self?.manga.mangaId else { return false }
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
            NSNotification.Name("updateLibrary"),
            NSNotification.Name("updateHistory")
        ]

        for notification in generalNotifications {
            NotificationCenter.default.publisher(for: notification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.scheduleBackgroundUpdate()
                }
                .store(in: &cancellables)
        }
    }

    deinit {
        updateDebouncer?.invalidate()
    }
}

struct MangaDownloadDetailView: View {
    @StateObject private var viewModel: MangaDownloadDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var path: NavigationCoordinator

    init(manga: DownloadedMangaInfo) {
        self._viewModel = StateObject(wrappedValue: MangaDownloadDetailViewModel(manga: manga))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading chapters...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.chapters.isEmpty {
                emptyStateView
            } else {
                chaptersList
            }
        }
        .navigationTitle(viewModel.manga.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: openMangaPage) {
                        Label("Open Manga", systemImage: "book")
                    }

                    if !viewModel.chapters.isEmpty {
                        Button(role: .destructive, action: viewModel.confirmDeleteAll) {
                            Label("Remove All Chapters", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.loadChapters()
        }
        .alert("Delete All Chapters", isPresented: $viewModel.showingDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteAllChapters()
            }
        } message: {
            Text("Are you sure you want to delete all chapters for \(viewModel.manga.displayTitle)? This action cannot be undone.")
        }
        .alert("Delete Chapter", isPresented: $viewModel.showingDeleteChapterConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let chapter = viewModel.chapterToDelete {
                    viewModel.deleteChapter(chapter)
                }
            }
        } message: {
            if let chapter = viewModel.chapterToDelete {
                Text("Are you sure you want to delete \(chapter.displayTitle)? This action cannot be undone.")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Chapters")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Downloaded chapters for this manga will appear here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chaptersList: some View {
        List {
            // Manga info header
            Section {
                mangaInfoHeader
            }

            // Chapters list with smooth animations
            Section {
                ForEach(viewModel.chapters) { chapter in
                    ChapterRow(chapter: chapter) {
                        viewModel.confirmDeleteChapter(chapter)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            viewModel.confirmDeleteChapter(chapter)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Downloaded Chapters")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Button(action: viewModel.toggleSortOrder) {
                        Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 2)
            }
        }
    }

    private var mangaInfoHeader: some View {
        HStack(spacing: 12) {
            AsyncImage(url: viewModel.manga.coverUrl != nil ? URL(string: viewModel.manga.coverUrl!) : nil) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 56, height: 56 * 3/2)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.manga.displayTitle)
                    .font(.system(size: 16))
                    .lineLimit(2)

                // Format like chapter subtitles: Date • Size
                Text(formatMangaSubtitle())
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if viewModel.manga.isInLibrary {
                    HStack {
                        Image(systemName: "books.vertical.fill")
                            .foregroundColor(.blue)
                        Text("In Library")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func formatMangaSubtitle() -> String {
        var components: [String] = []

        // Add current date (when viewed)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        components.append(formatter.string(from: Date()))

        // Add size
        components.append(viewModel.manga.formattedSize)

        return components.joined(separator: " • ")
    }

    private func openMangaPage() {
        guard let source = SourceManager.shared.source(for: viewModel.manga.sourceId) else {
            print("Source not found for ID: \(viewModel.manga.sourceId)")
            return
        }

        // Create a basic manga object from the downloaded manga info
        let aidokuManga = AidokuRunner.Manga(
            sourceKey: viewModel.manga.sourceId,
            key: viewModel.manga.mangaId,
            title: viewModel.manga.title ?? "Unknown Title"
        )

        // Navigate to manga page using NavigationCoordinator
        let hostingController = UIHostingController(
            rootView: MangaView(source: source, manga: aidokuManga)
                .environmentObject(path)
        )
        hostingController.navigationItem.largeTitleDisplayMode = UINavigationItem.LargeTitleDisplayMode.never
        hostingController.title = aidokuManga.title
        path.push(hostingController)
    }
}

struct ChapterRow: View {
    let chapter: DownloadedChapterInfo
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.displayTitle)
                    .font(.system(size: 16))
                    .lineLimit(2)

                // Format like chapter subtitles: Date • Size
                if let subtitle = formatChapterSubtitle() {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .contentShape(Rectangle())
    }

    private func formatChapterSubtitle() -> String? {
        var components: [String] = []

        // Add download date if available
        if let downloadDate = chapter.downloadDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            components.append(formatter.string(from: downloadDate))
        }

        // Add size
        components.append(ByteCountFormatter.string(fromByteCount: chapter.size, countStyle: .file))

        return components.isEmpty ? nil : components.joined(separator: " • ")
    }
}

#Preview {
    MangaDownloadDetailView(
        manga: DownloadedMangaInfo(
            sourceId: "test",
            mangaId: "test-manga",
            title: "Test Manga",
            coverUrl: nil,
            totalSize: 52428800, // 50 MB
            chapterCount: 12,
            isInLibrary: true
        )
    )
}
