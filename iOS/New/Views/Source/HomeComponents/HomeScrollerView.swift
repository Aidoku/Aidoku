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
    private let hasSubtitles: Bool

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
        self.hasSubtitles = entries.contains(where: { $0.subtitle != nil })
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

                                VStack(alignment: .leading, spacing: 0) {
                                    Text(entry.title)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    if let subtitle = entry.subtitle {
                                        Text(subtitle)
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                            .lineLimit(1)
                                            .padding(.top, 2)
                                    } else if hasSubtitles {
                                        Text("empty")
                                            .font(.footnote)
                                            .lineLimit(1)
                                            .opacity(0)
                                    }

                                    // Add empty line only when title shows 1 line
                                    if shouldAddEmptyLine(for: entry.title) {
                                        Text("empty")
                                            .lineLimit(1)
                                            .opacity(0)
                                    }
                                }
                                .padding(.horizontal, 4)
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
                                            path.push(MangaViewController(source: source, manga: manga, parent: path.rootViewController))
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

    private func shouldAddEmptyLine(for title: String) -> Bool {
        // Calculate if title fits in one line based on current font size
        let font = UIFont.preferredFont(forTextStyle: .body)
        let maxWidth = Self.coverHeight * 2/3 - 8 // subtract padding
        let titleWidth = title.size(withAttributes: [.font: font]).width
        return titleWidth <= maxWidth && !title.contains("\n")
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
