//
//  MangaDownloadDetailView.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import SwiftUI

struct MangaDownloadDetailView: View {
    @StateObject private var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var path: NavigationCoordinator

    init(manga: DownloadedMangaInfo) {
        self._viewModel = StateObject(wrappedValue: .init(manga: manga))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView(NSLocalizedString("LOADING_ELLIPSIS"))
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
                        Label(NSLocalizedString("VIEW_SERIES"), systemImage: "book")
                    }

                    if !viewModel.chapters.isEmpty {
                        Button(role: .destructive, action: viewModel.confirmDeleteAll) {
                            Label(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), systemImage: "trash")
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
        .alert(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), isPresented: $viewModel.showingDeleteAllConfirmation) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) { }
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                viewModel.deleteAllChapters()
            }
        } message: {
            Text("REMOVE_ALL_DOWNLOADS_CONFIRM")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(NSLocalizedString("NO_DOWNLOADS"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(NSLocalizedString("NO_DOWNLOADS_TEXT"))
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
                        viewModel.deleteChapter(chapter)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(NSLocalizedString("REMOVE"), role: .destructive) {
                            viewModel.deleteChapter(chapter)
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
                    }
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
                    HStack(spacing: 4) {
                        Image(systemName: "books.vertical.fill")
                            .imageScale(.small)
                        Text(NSLocalizedString("IN_LIBRARY"))
                            .font(.footnote)
                    }
                    .foregroundStyle(.tint)
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
        guard SourceManager.shared.source(for: viewModel.manga.sourceId) != nil else {
            print("Source not found for ID: \(viewModel.manga.sourceId)")
            return
        }

        // Create a basic manga object from the downloaded manga info
        let manga = Manga(
            sourceId: viewModel.manga.sourceId,
            id: viewModel.manga.mangaId,
            title: viewModel.manga.title
        )

        // Convert downloaded chapters to Chapter objects with proper source order
        let chapters = viewModel.chapters.enumerated().map { index, downloadedChapter in
            Chapter(
                sourceId: viewModel.manga.sourceId,
                id: downloadedChapter.chapterId,
                mangaId: viewModel.manga.mangaId,
                title: downloadedChapter.title,
                chapterNum: downloadedChapter.chapterNumber,
                volumeNum: downloadedChapter.volumeNumber,
                sourceOrder: index // Use enumerated index for proper ordering
            )
        }

        // Use MangaViewController with the downloaded chapters
        let mangaViewController = MangaViewController(manga: manga, chapterList: chapters)
        path.push(mangaViewController)
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
