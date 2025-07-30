//
//  HomeScrollerView.swift
//  Aidoku
//
//  Created by Skitty on 10/13/23.
//

import AidokuRunner
import SafariServices
import SwiftUI

struct HomeScrollerView: View {
    let source: AidokuRunner.Source
    let component: HomeComponent
    let partial: Bool

    private let entries: [HomeComponent.Value.Link]
    private let listing: AidokuRunner.Listing?

    static let coverHeight: CGFloat = 180

    @State private var bookmarkedItems: Set<String> = .init()
    @State private var loadedBookmarks = false

    @EnvironmentObject private var path: NavigationCoordinator

    init(
        source: AidokuRunner.Source,
        component: HomeComponent,
        partial: Bool = false
    ) {
        self.source = source
        self.component = component
        self.partial = partial

        guard case let .scroller(entries, listing) = component.value else {
            fatalError("invalid component type")
        }
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
                PlaceholderMangaScroller.mainView
                    .redacted(reason: .placeholder)
                    .shimmering()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(entries.indices, id: \.self) { offset in
                            let entry = entries[offset]
                            let label = VStack(alignment: .leading) {
                                let mangaKey: String? = switch entry.value {
                                    case .manga(let manga): manga.key
                                    default: nil
                                }
                                MangaCoverView(
                                    source: source,
                                    coverImage: entry.imageUrl ?? "",
                                    width: Self.coverHeight * 2/3,
                                    height: Self.coverHeight,
                                    downsampleWidth: 200,
                                    bookmarked: mangaKey.flatMap { bookmarkedItems.contains($0) } ?? false
                                )

                                Group {
                                    if #available(iOS 16.0, *) {
                                        Text(entry.title)
                                            .lineLimit(2, reservesSpace: true)
                                    } else {
                                        Text(entry.title + "\n")
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: Self.coverHeight * 2/3)
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
                                            path.push(NewMangaViewController(source: source, manga: manga, parent: path.rootViewController))
                                    }
                                } label: {
                                    label
                                }
                                .foregroundStyle(.primary)
                                .buttonStyle(.borderless)
                            } else {
                                label
                            }
                        }
                    }
                    .padding(.horizontal)
                    .scrollTargetLayoutPlease()
                }
                .scrollViewAlignedPlease()
                .task {
                    if !loadedBookmarks {
                        await loadBookmarked()
                    }
                }
                .onChange(of: entries) { _ in
                    Task {
                        if !loadedBookmarks {
                            await loadBookmarked()
                        }
                    }
                }
            }
        }
    }

    func loadBookmarked() async {
        guard !entries.isEmpty else { return }
        bookmarkedItems = await CoreDataManager.shared.container.performBackgroundTask { context in
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
}

struct PlaceholderMangaScroller: View {
    var showTitle = true

    var body: some View {
        VStack(alignment: .leading) {
            if showTitle {
                Text("Loading")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
            }

            Self.mainView
        }
        .redacted(reason: .placeholder)
        .shimmering()
    }

    static var mainView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(0..<20) { _ in
                    VStack(alignment: .leading) {
                        MangaGridItem.placeholder
                            .frame(height: 180)

                        let text = Text("Loading\n")
                            .padding(.horizontal, 4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if #available(iOS 16.0, *) {
                            text.lineLimit(2, reservesSpace: true)
                        } else {
                            text.lineLimit(2)
                        }
                    }
                    .frame(width: 180 * 2/3)
                }
            }
            .padding(.horizontal)
        }
        .scrollViewAlignedPlease()
    }
}
