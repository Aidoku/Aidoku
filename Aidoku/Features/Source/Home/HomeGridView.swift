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
    let containerWidth: CGFloat
    @Binding var bookmarkedItems: Set<String>
    var loadMore: (() async -> Void)?
    var onSelect: ((AidokuRunner.Manga) -> Void)?

    @State private var loadingMore = false
    @State private var columns: [GridItem]
    @State private var itemsPerRow: Int = 1

    @EnvironmentObject private var path: NavigationCoordinator

    static let spacing: CGFloat = OldMangaCollectionViewController.itemSpacing

    init(
        source: AidokuRunner.Source,
        entries: [AidokuRunner.Manga],
        containerWidth: CGFloat,
        bookmarkedItems: Binding<Set<String>> = .constant([]),
        loadMore: (() async -> Void)? = nil,
        onSelect: ((AidokuRunner.Manga) -> Void)? = nil
    ) {
        self.source = source
        self.entries = entries
        self.containerWidth = containerWidth
        self._bookmarkedItems = bookmarkedItems
        self.loadMore = loadMore
        self.onSelect = onSelect
        self._columns = State(initialValue: Self.getColumns(itemsPerRow: 1))
    }

    private static var isLandscape: Bool {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let orientation = if #available(iOS 16.0, *) {
            scene?.effectiveGeometry.interfaceOrientation
        } else {
            scene?.interfaceOrientation
        }
        return orientation?.isLandscape ?? false
    }

    private static func getColumns(itemsPerRow: Int) -> [GridItem] {
        (0..<itemsPerRow).map { _ in GridItem(.flexible(), spacing: Self.spacing) }
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
        .onAppear {
            updateItemsPerRow()
        }
        .onChange(of: entries) { _ in
            loadingMore = false
        }
        .onChange(of: containerWidth) { width in
            updateItemsPerRow(width: width)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // fixes bug where item per row is incorrect when closing and opening app
            updateItemsPerRow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .orientationDidChange)) { _ in
            updateItemsPerRow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init(AppSettings.appearance.layout.key))) { _ in
            updateItemsPerRow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init(AppSettings.appearance.customPortraitRows.key))) { _ in
            updateItemsPerRow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init(AppSettings.appearance.customLandscapeRows.key))) { _ in
            updateItemsPerRow()
        }
        .onChange(of: itemsPerRow) { newValue in
            columns = Self.getColumns(itemsPerRow: newValue)
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
                        await MangaManager.shared.removeFromLibrary(mangaId: entry.identifier)
                    }
                } label: {
                    Label(NSLocalizedString("REMOVE_FROM_LIBRARY"), systemImage: "trash")
                }
            } else {
                Button {
                    Task {
                        if await MangaManager.shouldAskForCategories() {
                            // open category select view
                            let viewController = UINavigationController(rootViewController: CategorySelectViewController(manga: entry))
                            path.present(viewController)
                        } else {
                            // add to library
                            bookmarkedItems.insert(entry.key)
                            await MangaManager.shared.addToLibrary(
                                manga: entry,
                                fetchMangaDetails: true
                            )
                        }
                    }
                } label: {
                    Label(NSLocalizedString("ADD_TO_LIBRARY"), systemImage: "plus.circle")
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

    func updateItemsPerRow(width: CGFloat? = nil) {
        itemsPerRow = OldMangaCollectionViewController.getGridItemsPerRow(
            containerWidth: width ?? containerWidth,
            isLandscape: Self.isLandscape,
            layout: AppSettings.appearance.layout.get()
        )
    }

    static func placeholder(width: CGFloat, availableWidth: CGFloat? = nil) -> some View {
        Placeholder(containerWidth: width, availableWidth: availableWidth ?? width)
    }

    private struct Placeholder: View {
        let containerWidth: CGFloat
        let availableWidth: CGFloat

        private var itemsPerRow: Int {
            OldMangaCollectionViewController.getGridItemsPerRow(
                containerWidth: containerWidth,
                isLandscape: HomeGridView.isLandscape,
                layout: AppSettings.appearance.layout.get()
            )
        }

        var body: some View {
            let itemCount = 30
            let itemsPerRow = itemsPerRow
            let containerPadding: CGFloat = 16
            let itemWidth = max(0, (availableWidth - containerPadding * 2 - CGFloat(itemsPerRow - 1) * HomeGridView.spacing) / CGFloat(itemsPerRow))

            VStack(alignment: .leading, spacing: HomeGridView.spacing) {
                let rowCount = (itemCount + itemsPerRow - 1) / itemsPerRow
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: HomeGridView.spacing) {
                        ForEach(0..<itemsPerRow, id: \.self) { column in
                            if row * itemsPerRow + column < itemCount {
                                MangaGridItem.placeholder
                                    .frame(width: itemWidth, height: itemWidth * 3 / 2)
                                    .clipped()
                            }
                        }
                    }
                }
            }
            .shimmering()
            .padding([.horizontal, .bottom])
        }
    }
}
