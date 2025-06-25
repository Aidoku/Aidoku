//
//  DownloadManagerView.swift
//  Aidoku
//
//  Created by Assistant on 12/30/24.
//

import SwiftUI
import Combine

@MainActor
class DownloadManagerViewModel: ObservableObject {
    @Published var downloadedManga: [DownloadedMangaInfo] = []
    @Published var isLoading = true
    @Published var totalSize: String = ""
    @Published var totalCount = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupNotificationObservers()
    }
    
    // Group manga by source for sectioned display
    var groupedManga: [(source: String, manga: [DownloadedMangaInfo])] {
        let grouped = Dictionary(grouping: downloadedManga) { $0.sourceId }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (source: getSourceDisplayName($0.key), manga: $0.value) }
    }
    
    func loadDownloadedManga() async {
        isLoading = true
        
        let manga = await DownloadManager.shared.getAllDownloadedManga()
        let formattedSize = await DownloadManager.shared.getFormattedTotalDownloadedSize()
        
        await MainActor.run {
            self.downloadedManga = manga
            self.totalSize = formattedSize
            self.totalCount = manga.count
            self.isLoading = false
        }
    }
    
    private func setupNotificationObservers() {
        // Listen for download completion/removal to refresh the list
        NotificationCenter.default.publisher(for: NSNotification.Name("downloadFinished"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.loadDownloadedManga()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("downloadRemoved"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.loadDownloadedManga()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("downloadsRemoved"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.loadDownloadedManga()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("downloadsCancelled"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.loadDownloadedManga()
                }
            }
            .store(in: &cancellables)
    }
    
    private func getSourceDisplayName(_ sourceId: String) -> String {
        if let source = SourceManager.shared.source(for: sourceId) {
            return source.name
        }
        // Fallback to source ID for unknown sources
        return sourceId.capitalized
    }
}

struct DownloadManagerView: View {
    @StateObject private var viewModel = DownloadManagerViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading downloads...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.downloadedManga.isEmpty {
                    emptyStateView
                } else {
                    downloadsList
                }
            }
            .navigationTitle("Download Manager")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadDownloadedManga()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Downloads")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Downloaded manga chapters will appear here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var downloadsList: some View {
        List {
            // Summary header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Total Downloads")
                            .font(.headline)
                        Spacer()
                        Text(viewModel.totalSize)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Text("\(viewModel.totalCount) manga")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        let totalChapters = viewModel.downloadedManga.reduce(0) { $0 + $1.chapterCount }
                        Text("\(totalChapters) chapters")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Manga grouped by source
            ForEach(viewModel.groupedManga, id: \.source) { group in
                Section(header: Text(group.source)) {
                    ForEach(group.manga) { manga in
                        NavigationLink(destination: MangaDownloadDetailView(manga: manga)) {
                            DownloadedMangaRow(manga: manga)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.loadDownloadedManga()
        }
    }
}

struct DownloadedMangaRow: View {
    let manga: DownloadedMangaInfo
    
    var body: some View {
        HStack {
            // Placeholder for manga cover (could be enhanced later)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 70)
                .overlay(
                    Image(systemName: "book.fill")
                        .foregroundColor(.secondary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(manga.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack {
                    Text(manga.formattedSize)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("\(manga.chapterCount) chapters")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if manga.isInLibrary {
                    HStack {
                        Image(systemName: "books.vertical.fill")
                            .font(.caption)
                        Text("In Library")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DownloadManagerView()
} 