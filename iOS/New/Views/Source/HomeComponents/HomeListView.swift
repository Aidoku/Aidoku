//
//  HomeListView.swift
//  Aidoku
//
//  Created by Skitty on 10/13/23.
//

import AidokuRunner
import SafariServices
import SwiftUI

struct HomeListView: View {
    let source: AidokuRunner.Source
    let component: HomeComponent
    let partial: Bool
    @Binding var bookmarkedItems: Set<String>
    var loadMore: (() async -> Void)?
    var onSelect: ((AidokuRunner.Manga) -> Void)?

    private let ranking: Bool
    private let pageSize: Int?
    private let entries: [HomeComponent.Value.Link]
    private let listing: AidokuRunner.Listing?

    private let usesBookmarksState: Bool

    @State private var loadingMore = false
    @State private var bookmarkedItemsState: Set<String> = .init()
    @State private var loadedBookmarks: Bool

    @EnvironmentObject private var path: NavigationCoordinator

    init(
        source: AidokuRunner.Source,
        component: HomeComponent,
        partial: Bool = false,
        bookmarkedItems: Binding<Set<String>>? = nil,
        loadMore: (() async -> Void)? = nil,
        onSelect: ((AidokuRunner.Manga) -> Void)? = nil
    ) {
        self.source = source
        self.component = component
        self.partial = partial
        self.loadMore = loadMore
        self.onSelect = onSelect
        if let bookmarkedItems {
            self._loadedBookmarks = State(initialValue: true)
            self._bookmarkedItems = bookmarkedItems
            self.usesBookmarksState = false
        } else {
            self._loadedBookmarks = State(initialValue: false)
            self._bookmarkedItems = Binding.constant([])
            self.usesBookmarksState = true
        }

        guard case let .mangaList(ranking, pageSize, entries, listing) = component.value else {
            fatalError("invalid component type")
        }
        self.ranking = ranking
        self.pageSize = pageSize
        self.entries = entries
        self.listing = listing
    }

    var body: some View {
        VStack(alignment: .leading) {
            if let title = component.title {
                TitleView(
                    title: title,
                    subtitle: component.subtitle,
                    onTitleClick: listing == nil ? nil : {
                        if let listing {
                            path.push(SourceListingViewController(source: source, listing: listing))
                        }
                    }
                )
            }

            if partial && entries.isEmpty {
                PlaceholderMangaHomeList.mainView(itemCount: 6)
                    .redacted(reason: .placeholder)
                    .shimmering()
            } else {
                Group {
                    if let pageSize {
                        let (getSection, height) = CollectionView.mangaListLayout(
                            itemsPerPage: pageSize,
                            totalItems: entries.count
                        )
                        CollectionView(
                            sections: [
                                CollectionViewSection(
                                    items: entries.indices.map { offset in
                                        AnyView(view(
                                            for: entries[offset],
                                            position: offset
                                        ).ignoresSafeArea())
                                    }
                                )
                            ],
                            layout: UICollectionViewCompositionalLayout { _, layoutEnvironment in
                                getSection(layoutEnvironment)
                            }
                        )
                        .frame(height: height)
                    } else {
                        LazyVStack {
                            ForEach(entries.indices, id: \.self) { offset in
                                view(
                                    for: entries[offset],
                                    position: offset
                                )
                            }
                            loadMoreView
                        }
                    }
                }
                .task {
                    if !loadedBookmarks {
                        await loadBookmarked()
                    }
                }
                .onChange(of: entries) { _ in
                    loadingMore = false
                    Task {
                        if !loadedBookmarks {
                            await loadBookmarked()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var loadMoreView: some View {
        if loadingMore {
            EmptyView()
        } else {
            Spacer()
                .onAppear {
                    loadingMore = true
                    Task {
                        await loadMore?()
                    }
                }
        }
    }

    @ViewBuilder
    func view(for entry: HomeComponent.Value.Link, position: Int) -> some View {
        let label = HStack(spacing: 12) {
            let mangaKey: String? = switch entry.value {
                case .manga(let manga): manga.key
                default: nil
            }
            MangaCoverView(
                source: source,
                coverImage: entry.imageUrl ?? "",
                width: 100 * 2/3,
                height: 100,
                downsampleWidth: 200,
                bookmarked: mangaKey.flatMap { (usesBookmarksState ? bookmarkedItemsState : bookmarkedItems).contains($0) } ?? false
            )

            let titleStack = VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if case .manga(let manga) = entry.value, let tags = manga.tags, !tags.isEmpty {
                    if pageSize != nil {
                        GeometryReader { geo in
                            HStack(spacing: 4) {
                                let availableTags = numberOfItemsThatFit(in: geo.size.width, items: tags)
                                let tagCount = min(availableTags, tags.count)

                                if tagCount > 0 {
                                    ForEach(tags.prefix(tagCount), id: \.self) { tag in
                                        LabelView(text: tag)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                        }
                        .frame(height: 20)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(tags, id: \.self) { tag in
                                    LabelView(text: tag)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            if ranking {
                HStack(alignment: .top) {
                    Text("\(position + 1)")
                        .bold()
                        .padding(.horizontal, 2)

                    titleStack
                }
            } else {
                titleStack
            }

            Spacer()
        }
        .padding(.horizontal)
        if let value = entry.value {
            Button {
                switch value {
                    case .url(let urlString):
                        guard
                            let url = URL(string: urlString),
                            url.scheme == "http" || url.scheme == "https"
                        else { return }
                        path.present(SFSafariViewController(url: url))
                    case .listing(let listing):
                        path.push(SourceListingViewController(source: source, listing: listing))
                    case .manga(let manga):
                        if let onSelect {
                            onSelect(manga)
                        } else {
                            path.push(MangaViewController(source: source, manga: manga, parent: path.rootViewController))
                        }
                }
            } label: {
                label
            }
            .foregroundStyle(.primary)
            .buttonStyle(.borderless)
        }
    }

    func loadBookmarked() async {
        guard !entries.isEmpty, usesBookmarksState else { return }
        bookmarkedItemsState = await CoreDataManager.shared.container.performBackgroundTask { context in
            var keys: Set<String> = .init()
            for entry in entries {
                let mangaKey: String? = switch entry.value {
                    case .manga(let manga): manga.key
                    default: nil
                }
                if let mangaKey {
                    if CoreDataManager.shared.hasLibraryManga(
                        sourceId: source.key,
                        mangaId: mangaKey,
                        context: context
                    ) {
                        keys.insert(mangaKey)
                    }
                }
            }
            return keys
        }
        loadedBookmarks = true
    }

    private func numberOfItemsThatFit(in availableWidth: CGFloat, items: [String]) -> Int {
        var totalWidth: CGFloat = 0
        var count = 0

        for item in items {
            // padding of 8 on both sides, plus 8 for the spacing in between
            let padding: CGFloat = 8 + 8 + 8
            let itemWidth = item
                .size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .caption2)])
                .width + padding
            if totalWidth + itemWidth > availableWidth {
                break
            }
            totalWidth += itemWidth
            count += 1
        }

        return count
    }
}

struct PlaceholderMangaHomeList: View {
    var showTitle = true
    var itemCount = 5

    var body: some View {
        VStack(alignment: .leading) {
            if showTitle {
                Text("Loading")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
            }

            Self.mainView(itemCount: itemCount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .shimmering()
    }

    static func mainView(itemCount: Int) -> some View {
        LazyVStack {
            ForEach(0..<itemCount, id: \.self) { _ in
                HStack {
                    Rectangle()
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 100 * 2/3, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loading Title")
                        Text("Loading")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
    }
}
