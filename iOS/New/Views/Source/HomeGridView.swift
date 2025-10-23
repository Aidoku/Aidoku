//
//  HomeGridView.swift
//  Aidoku
//
//  Created by Skitty on 5/27/25.
//

import AidokuRunner
import SwiftUI

struct HomeGridView: View {
    let source: AidokuRunner.Source
    let entries: [AidokuRunner.Manga]
    @Binding var bookmarkedItems: Set<String>
    var loadMore: (() async -> Void)?
    var onSelect: ((AidokuRunner.Manga) -> Void)?

    @State private var loadingMore = false
    @State private var columns: [GridItem]

    @EnvironmentObject private var path: NavigationCoordinator

    static let spacing: CGFloat = 12

    init(
        source: AidokuRunner.Source,
        entries: [AidokuRunner.Manga],
        bookmarkedItems: Binding<Set<String>> = .constant([]),
        loadMore: (() async -> Void)? = nil,
        onSelect: ((AidokuRunner.Manga) -> Void)? = nil
    ) {
        self.source = source
        self.entries = entries
        self._bookmarkedItems = bookmarkedItems
        self.loadMore = loadMore
        self.onSelect = onSelect
        self._columns = State(initialValue: Self.getColumns())
    }

    static private func getColumns() -> [GridItem] {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let orientation =
            if #available(iOS 16.0, *) {
                scene?.effectiveGeometry.interfaceOrientation
            } else {
                scene?.interfaceOrientation
            }
        let itemsPerRow = UserDefaults.standard.integer(
            forKey: orientation?.isLandscape ?? false
                ? "General.landscapeRows"
                : "General.portraitRows"
        )
        let idealWidth = UIScreen.main.bounds.size.width / CGFloat(itemsPerRow)
        return (0..<itemsPerRow).map { _ in
            GridItem(.flexible(minimum: idealWidth / 2), spacing: spacing)
        }
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            spacing: Self.spacing
        ) {
            ForEach(entries.indices, id: \.self) { index in
                mangaGridItem(entry: entries[index])
            }
            loadMoreView
        }
        .padding([.horizontal, .bottom])
        .onChange(of: entries) { _ in
            loadingMore = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            Task {
                columns = Self.getColumns()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .portraitRowsSetting)) { _ in
            columns = Self.getColumns()
        }
        .onReceive(NotificationCenter.default.publisher(for: .landscapeRowsSetting)) { _ in
            columns = Self.getColumns()
        }
    }

    private func mangaGridItem(entry: AidokuRunner.Manga) -> some View {
        let inLibrary = bookmarkedItems.contains(entry.key)
        return Button {
            if let onSelect {
                onSelect(entry)
            } else {
                path.push(MangaViewController(source: source, manga: entry, parent: path.rootViewController))
            }
        } label: {
            MangaGridItem(
                source: source,
                title: entry.title,
                coverImage: entry.cover ?? "",
                bookmarked: inLibrary
            )
        }
        .buttonStyle(MangaGridButtonStyle())
        .contextMenu {
            // add a remove button for manga from the local source
            if entry.isLocal() {
                Button(role: .destructive) {
                    Task {
                        await LocalFileManager.shared.removeManga(with: entry.key)
                        NotificationCenter.default.post(name: .init("refresh-content"), object: nil)
                    }
                } label: {
                    Label(NSLocalizedString("REMOVE"), systemImage: "trash")
                }
            }
            if inLibrary {
                Button(role: .destructive) {
                    bookmarkedItems.remove(entry.key)
                    Task {
                        await MangaManager.shared.removeFromLibrary(
                            sourceId: source.key,
                            mangaId: entry.key
                        )
                    }
                } label: {
                    Label(NSLocalizedString("REMOVE_FROM_LIBRARY"), systemImage: "trash")
                }
            } else {
                Button {
                    bookmarkedItems.insert(entry.key)
                    Task {
                        await MangaManager.shared.addToLibrary(
                            sourceId: source.key,
                            manga: entry,
                            fetchMangaDetails: true
                        )
                    }
                } label: {
                    Label(NSLocalizedString("ADD_TO_LIBRARY"), systemImage: "books.vertical.fill")
                }
            }
        }
    }

    @ViewBuilder
    var loadMoreView: some View {
        if !loadingMore, !entries.isEmpty, let loadMore {
            Spacer()
                .onAppear {
                    loadingMore = true
                    Task {
                        await loadMore()
                    }
                }
        } else {
            EmptyView()
        }
    }

    static var placeholder: some View {
        LazyVGrid(columns: Self.getColumns(), spacing: Self.spacing) {
            ForEach(0..<30) { _ in
                MangaGridItem.placeholder
            }
        }
        .shimmering()
        .padding([.horizontal, .bottom])
    }
}
