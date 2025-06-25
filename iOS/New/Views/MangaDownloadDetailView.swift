//
//  MangaDownloadDetailView.swift
//  Aidoku
//
//  Created by Assistant on 12/30/24.
//

import SwiftUI
import Combine

@MainActor
class MangaDownloadDetailViewModel: ObservableObject {
    @Published var chapters: [DownloadedChapterInfo] = []
    @Published var isLoading = true
    @Published var showingDeleteAllConfirmation = false
    @Published var showingDeleteChapterConfirmation = false
    @Published var chapterToDelete: DownloadedChapterInfo?
    
    @Published var manga: DownloadedMangaInfo
    
    // Non-reactive state for background management
    private var backgroundUpdateInProgress = false
    private var lastUpdateId = UUID()
    private var updateDebouncer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init(manga: DownloadedMangaInfo) {
        self.manga = manga
        setupNotificationObservers()
    }
    
    func loadChapters() async {
        isLoading = true
        
        let downloadedChapters = await DownloadManager.shared.getDownloadedChapters(for: manga)
        
        await MainActor.run {
            self.chapters = downloadedChapters
            self.isLoading = false
        }
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
            chapters = newChapters
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
                if !viewModel.chapters.isEmpty {
                    Button(action: viewModel.confirmDeleteAll) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
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
            Section("Downloaded Chapters") {
                ForEach(viewModel.chapters) { chapter in
                    ChapterRow(chapter: chapter) {
                        viewModel.confirmDeleteChapter(chapter)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.confirmDeleteChapter(viewModel.chapters[index])
                    }
                }
            }
        }
    }
    
    private var mangaInfoHeader: some View {
        HStack {
            AsyncImage(url: viewModel.manga.coverUrl != nil ? URL(string: viewModel.manga.coverUrl!) : nil) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 80, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.manga.displayTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                
                HStack {
                    Image(systemName: "externaldrive.fill")
                        .foregroundColor(.secondary)
                    Text(viewModel.manga.formattedSize)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.secondary)
                    Text("\(viewModel.chapters.count) chapters")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.manga.isInLibrary {
                    HStack {
                        Image(systemName: "books.vertical.fill")
                            .foregroundColor(.blue)
                        Text("In Library")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct ChapterRow: View {
    let chapter: DownloadedChapterInfo
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack {
                    Image(systemName: "externaldrive.fill")
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: chapter.size, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let downloadDate = chapter.downloadDate {
                        Text(downloadDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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