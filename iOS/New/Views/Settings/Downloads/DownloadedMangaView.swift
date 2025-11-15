//
//  DownloadedMangaView.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import AidokuRunner
import SwiftUI
import UIKit

struct DownloadedMangaView: View {
    @StateObject private var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var path: NavigationCoordinator

    init(manga: DownloadedMangaInfo) {
        self._viewModel = StateObject(wrappedValue: .init(manga: manga))
    }

    var body: some View {
        Group {
            if viewModel.chapters.isEmpty {
                if viewModel.isLoading {
                    ProgressView(NSLocalizedString("LOADING_ELLIPSIS"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyStateView
                }
            } else {
                chaptersList
            }
        }
        .navigationTitle(viewModel.manga.displayTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.manga.isInLibrary || !viewModel.chapters.isEmpty {
                    Menu {
                        if viewModel.manga.isInLibrary, let source = SourceManager.shared.source(for: viewModel.manga.sourceId) {
                            Button {
                                openMangaView(source: source)
                            } label: {
                                Label(NSLocalizedString("VIEW_SERIES"), systemImage: "book")
                            }
                        }

                        if !viewModel.chapters.isEmpty {
                            Button(role: .destructive, action: viewModel.confirmDeleteAll) {
                                Label(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), systemImage: "trash")
                            }
                        }
                    } label: {
                        MoreIcon()
                    }
                }
            }
        }
        .task {
            await viewModel.loadChapters()
            await viewModel.loadHistory()
        }
        .alert(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), isPresented: $viewModel.showingDeleteAllConfirmation) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) { }
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                viewModel.deleteAllChapters()
            }
        } message: {
            Text(NSLocalizedString("REMOVE_ALL_DOWNLOADS_CONFIRM"))
        }
    }

    private var emptyStateView: some View {
        UnavailableView(
            NSLocalizedString("NO_DOWNLOADS"),
            systemImage: "arrow.down.circle",
            description: Text(NSLocalizedString("NO_DOWNLOADS_TEXT"))
        )
        .ignoresSafeArea()
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
                    Button {
                        openReaderView(chapter: chapter)
                    } label: {
                        ChapterRow(chapter: chapter, history: viewModel.readingHistory[chapter.chapterId])
                    }
                    .foregroundStyle(.primary)
                    .contextMenu {
                        Button {
                            showShareSheet(chapter: chapter)
                        } label: {
                            Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .onDelete(perform: delete)
            } header: {
                HStack {
                    Text(NSLocalizedString("DOWNLOADED_CHAPTERS"))

                    Spacer()

                    Button(action: viewModel.toggleSortOrder) {
                        Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                            .imageScale(.small)
                    }
                }
            }
        }
    }

    private var mangaInfoHeader: some View {
        HStack(spacing: 12) {
            MangaCoverView(
                source: SourceManager.shared.source(for: viewModel.manga.sourceId),
                coverImage: viewModel.manga.coverUrl ?? "",
                width: 56,
                height: 56 * 3/2
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.manga.displayTitle)
                    .font(.callout)
                    .lineLimit(2)

                // Format like chapter subtitles: Date • Size
                Text(formatMangaSubtitle())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        let chapters = offsets.map { viewModel.chapters[$0] }
        for chapter in chapters {
            viewModel.deleteChapter(chapter)
        }
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

    private func openReaderView(chapter: DownloadedChapterInfo) {
        let readerController = ReaderViewController(
            source: SourceManager.shared.source(for: viewModel.manga.sourceId),
            manga: viewModel.manga.toManga(),
            chapter: chapter.toChapter()
        )
        let navigationController = ReaderNavigationController(rootViewController: readerController)
        navigationController.modalPresentationStyle = .fullScreen
        path.present(navigationController)
    }

    private func openMangaView(source: AidokuRunner.Source) {
        let viewController = MangaViewController(
            source: source,
            manga: viewModel.manga.toManga(),
            parent: path.rootViewController
        )
        path.push(viewController)
    }

    private func showShareSheet(chapter: DownloadedChapterInfo) {
        Task {
            let identifier = ChapterIdentifier(
                sourceKey: viewModel.manga.sourceId,
                mangaKey: viewModel.manga.mangaId,
                chapterKey: chapter.chapterId
            )
            if let url = await DownloadManager.shared.getCompressedFile(for: identifier) {
                let activityViewController = UIActivityViewController(
                    activityItems: [url],
                    applicationActivities: nil
                )
                guard let sourceView = path.rootViewController?.view else { return }
                activityViewController.popoverPresentationController?.sourceView = sourceView
                // manually positioned in top right of screen, near the right navigation bar button
                activityViewController.popoverPresentationController?.sourceRect = CGRect(
                    x: UIScreen.main.bounds.width - 30,
                    y: 60,
                    width: 0,
                    height: 0
                )
                path.present(activityViewController)
            }
        }
    }
}

private struct ChapterRow: View {
    let chapter: DownloadedChapterInfo
    let history: (page: Int, date: Int)?

    var isRead: Bool {
        history?.page == -1
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isRead ? .secondary : .primary)

                // Format like chapter subtitles: Date • Size
                if let subtitle = formatChapterSubtitle() {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func formatChapterSubtitle() -> String? {
        var components: [String] = []

        // download date
        if let downloadDate = chapter.downloadDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            components.append(formatter.string(from: downloadDate))
        }

        // file size
        components.append(ByteCountFormatter.string(fromByteCount: chapter.size, countStyle: .file))

        // pages read
        if let page = history?.page, page > 0 {
            components.append(String(format: NSLocalizedString("PAGE_X"), page))
        }

        return components.isEmpty ? nil : components.joined(separator: " • ")
    }
}

#Preview {
    DownloadedMangaView(
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
