//
//  DownloadManagerView.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import SwiftUI
import Combine

@MainActor
class DownloadManagerViewModel: ObservableObject {
    @Published var downloadedManga: [DownloadedMangaInfo] = []
    @Published var isLoading = true
    @Published var totalSize: String = ""
    @Published var totalCount = 0

    // Non-reactive state for background updates
    private var backgroundUpdateInProgress = false
    private var lastUpdateId = UUID()
    private var updateDebouncer: Timer?
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
            NSNotification.Name("downloadRemoved"),
            NSNotification.Name("downloadsRemoved")
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
            NSNotification.Name("downloadFinished"),
            NSNotification.Name("downloadsCancelled"),
            NSNotification.Name("downloadsQueued"),
            NSNotification.Name("downloadsPaused"),
            NSNotification.Name("downloadsResumed"),
            .addToLibrary,
            NSNotification.Name("removeFromLibrary"),
            NSNotification.Name("updateLibrary"),
            NSNotification.Name("updateHistory")
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
        // Fallback to source ID for unknown sources
        return sourceId.capitalized
    }

    deinit {
        updateDebouncer?.invalidate()
    }
}

struct DownloadManagerView: View {
    @StateObject private var viewModel = DownloadManagerViewModel()
    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
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
        .task {
            await viewModel.loadDownloadedManga()
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

            // Manga grouped by source with stable IDs for smooth updates
            ForEach(viewModel.groupedManga, id: \.source) { group in
                Section(header: Text(group.source)) {
                    ForEach(group.manga) { manga in
                        Button(action: {
                            let hostingController = UIHostingController(
                                rootView: MangaDownloadDetailView(manga: manga)
                                    .environmentObject(path)
                            )
                            hostingController.title = manga.displayTitle
                            path.push(hostingController)
                        }) {
                            DownloadedMangaRow(manga: manga)
                        }
                        .buttonStyle(PlainButtonStyle())
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
        HStack(spacing: 12) {
            // Manga cover or placeholder matching history page style
            AsyncImage(url: manga.coverUrl != nil ? URL(string: manga.coverUrl!) : nil) { image in
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
                Text(manga.displayTitle)
                    .font(.system(size: 16))
                    .lineLimit(2)

                // Format like chapter subtitles: chapters • size
                Text(formatMangaSubtitle())
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if manga.isInLibrary {
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
        .contentShape(Rectangle())
    }

    private func formatMangaSubtitle() -> String {
        var components: [String] = []

        // Add chapter count
        let chapterText = manga.chapterCount == 1 ? "1 chapter" : "\(manga.chapterCount) chapters"
        components.append(chapterText)

        // Add size
        components.append(manga.formattedSize)

        return components.joined(separator: " • ")
    }
}

#Preview {
    NavigationView {
        DownloadManagerView()
    }
}
