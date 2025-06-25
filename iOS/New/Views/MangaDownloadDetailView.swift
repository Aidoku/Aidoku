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
    
    func deleteChapter(_ chapter: DownloadedChapterInfo) {
        DownloadManager.shared.deleteChapter(chapter, from: manga)
        chapters.removeAll { $0.id == chapter.id }
    }
    
    func deleteAllChapters() {
        DownloadManager.shared.deleteChaptersForManga(manga)
        chapters.removeAll()
    }
    
    func confirmDeleteChapter(_ chapter: DownloadedChapterInfo) {
        chapterToDelete = chapter
        showingDeleteChapterConfirmation = true
    }
    
    func confirmDeleteAll() {
        showingDeleteAllConfirmation = true
    }
    
    func updateMangaLibraryStatus() async {
        // Check current library status from CoreData
        let isInLibrary = await withCheckedContinuation { continuation in
            CoreDataManager.shared.container.performBackgroundTask { context in
                let hasLibraryManga = CoreDataManager.shared.hasLibraryManga(
                    sourceId: self.manga.sourceId,
                    mangaId: self.manga.mangaId,
                    context: context
                )
                continuation.resume(returning: hasLibraryManga)
            }
        }
        
        // Update the manga object with new library status
        manga = DownloadedMangaInfo(
            sourceId: manga.sourceId,
            mangaId: manga.mangaId,
            directoryMangaId: manga.directoryMangaId,
            title: manga.title,
            coverUrl: manga.coverUrl,
            totalSize: manga.totalSize,
            chapterCount: manga.chapterCount,
            isInLibrary: isInLibrary
        )
    }
    
    private func setupNotificationObservers() {
        // Listen for download events that might affect this manga's chapters
        NotificationCenter.default.publisher(for: NSNotification.Name("downloadFinished"))
            .sink { [weak self] notification in
                guard let download = notification.object as? Download,
                      download.sourceId == self?.manga.sourceId,
                      download.mangaId == self?.manga.mangaId else { return }
                Task { @MainActor in
                    await self?.loadChapters()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("downloadRemoved"))
            .sink { [weak self] notification in
                guard let chapter = notification.object as? Chapter,
                      chapter.sourceId == self?.manga.sourceId,
                      chapter.mangaId == self?.manga.mangaId else { return }
                Task { @MainActor in
                    // Remove from local list without full reload for better UX
                    self?.chapters.removeAll { $0.chapterId == chapter.id }
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("downloadsRemoved"))
            .sink { [weak self] notification in
                guard let manga = notification.object as? Manga,
                      manga.sourceId == self?.manga.sourceId,
                      manga.id == self?.manga.mangaId else { return }
                Task { @MainActor in
                    self?.chapters.removeAll()
                }
            }
            .store(in: &cancellables)
        
        // Listen for library changes to update the manga's library status
        NotificationCenter.default.publisher(for: .addToLibrary)
            .sink { [weak self] notification in
                guard let addedManga = notification.object as? Manga,
                      addedManga.sourceId == self?.manga.sourceId,
                      addedManga.id == self?.manga.mangaId else { return }
                Task { @MainActor in
                    await self?.updateMangaLibraryStatus()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("updateLibrary"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.updateMangaLibraryStatus()
                }
            }
            .store(in: &cancellables)
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
                    Button {
                        viewModel.confirmDeleteAll()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .task {
            await viewModel.loadChapters()
        }
        .confirmationDialog(
            "Delete All Chapters",
            isPresented: $viewModel.showingDeleteAllConfirmation
        ) {
            Button("Delete All", role: .destructive) {
                viewModel.deleteAllChapters()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all downloaded chapters for \"\(viewModel.manga.displayTitle)\". This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete Chapter",
            isPresented: $viewModel.showingDeleteChapterConfirmation
        ) {
            Button("Delete", role: .destructive) {
                if let chapter = viewModel.chapterToDelete {
                    viewModel.deleteChapter(chapter)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let chapter = viewModel.chapterToDelete {
                Text("This will permanently delete \"\(chapter.displayTitle)\" (\(chapter.formattedSize)). This action cannot be undone.")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Chapters")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("This manga has no downloaded chapters")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var chaptersList: some View {
        List {
            // Manga info header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Total Size")
                            .font(.headline)
                        Spacer()
                        Text(viewModel.manga.formattedSize)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Text("\(viewModel.chapters.count) chapters downloaded")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        if viewModel.manga.isInLibrary {
                            HStack {
                                Image(systemName: "books.vertical.fill")
                                    .font(.caption)
                                Text("In Library")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Chapters list
            Section("Chapters") {
                ForEach(viewModel.chapters) { chapter in
                    DownloadedChapterRow(chapter: chapter)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                viewModel.confirmDeleteChapter(chapter)
                            }
                        }
                }
            }
        }
        .refreshable {
            await viewModel.loadChapters()
        }
    }
}

struct DownloadedChapterRow: View {
    let chapter: DownloadedChapterInfo
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text(chapter.formattedSize)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    if let downloadDate = chapter.downloadDate {
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(downloadDate, style: .date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
        }
        .padding(.vertical, 2)
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