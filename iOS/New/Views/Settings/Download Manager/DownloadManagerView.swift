//
//  DownloadManagerView.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import SwiftUI

struct DownloadManagerView: View {
    @StateObject private var viewModel = ViewModel()
    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView(NSLocalizedString("LOADING_ELLIPSIS"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if viewModel.downloadedManga.isEmpty {
                emptyStateView
                    .transition(.opacity)
            } else {
                downloadsList
                    .transition(.opacity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.downloadedManga.isEmpty {
                    Menu {
                        Button(role: .destructive, action: viewModel.confirmDeleteAll) {
                            Label(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.downloadedManga.isEmpty)
        .navigationTitle(NSLocalizedString("DOWNLOAD_MANAGER"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadDownloadedManga()
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
            Image(systemName: "arrow.down.circle")
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

    private var downloadsList: some View {
        List {
            // Summary header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("TOTAL_DOWNLOADS"))
                            .font(.headline)
                        Spacer()
                        Text(viewModel.totalSize)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    HStack {
                        Text(String(format: NSLocalizedString("%i_SERIES"), viewModel.totalCount))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        let totalChapters = viewModel.downloadedManga.reduce(0) { $0 + $1.chapterCount }
                        Text(
                            (
                                totalChapters == 1
                                    ? NSLocalizedString("1_CHAPTER")
                                    : String(format: NSLocalizedString("%i_CHAPTERS"), totalChapters)
                            )
                            .lowercased()
                        )
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
                        Button(
                            action: {
                                let hostingController = UIHostingController(
                                    rootView: MangaDownloadDetailView(manga: manga)
                                        .environmentObject(path)
                                )
                                hostingController.title = manga.displayTitle
                                path.push(hostingController)
                            },
                            label: {
                                DownloadedMangaRow(manga: manga)
                            }
                        )
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
        .contentShape(Rectangle())
    }

    private func formatMangaSubtitle() -> String {
        var components: [String] = []

        // Add chapter count
        let chapterText = (
            manga.chapterCount == 1
                ? NSLocalizedString("1_CHAPTER")
                : String(format: NSLocalizedString("%i_CHAPTERS"), manga.chapterCount)
        )
        .lowercased()
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
