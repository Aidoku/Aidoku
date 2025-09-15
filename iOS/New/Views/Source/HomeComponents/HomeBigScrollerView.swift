//
//  HomeBigScrollerView.swift
//  Aidoku
//
//  Created by Skitty on 10/13/23.
//

import AidokuRunner
import SwiftUI

struct HomeBigScrollerView: View {
    let source: AidokuRunner.Source
    let component: HomeComponent
    let partial: Bool

    private let entries: [AidokuRunner.Manga]
    private let autoScrollInterval: TimeInterval?
    private let hasTags: Bool

    static let coverHeight: CGFloat = 170

    @State private var autoScrollPaused = false
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
        guard case let .bigScroller(entries, autoScrollInterval) = component.value else {
            fatalError("invalid component type")
        }
        self.entries = entries
        self.autoScrollInterval = autoScrollInterval
        self.hasTags = entries.contains { !($0.tags?.isEmpty ?? true) }
    }

    var body: some View {
        VStack(alignment: .leading) {
            if let title = component.title {
                TitleView(
                    title: title,
                    subtitle: component.subtitle
                )
            }

            if partial && entries.isEmpty {
                PlaceholderMangaHomeBigScroller.mainView
                    .redacted(reason: .placeholder)
                    .shimmering()
            } else {
                let carouselHeight: CGFloat = Self.coverHeight + (hasTags ? 40 : 0)
                Carousel(
                    entries,
                    autoScrollInterval: autoScrollInterval,
                    itemHeight: carouselHeight,
                    autoScrollPaused: $autoScrollPaused,
                ) { offset, entry in
                    Button {
                        path.push(MangaViewController(source: source, manga: entry, parent: path.rootViewController))
                    } label: {
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 12) {
                                MangaCoverView(
                                    source: source,
                                    coverImage: entry.cover ?? "",
                                    width: Self.coverHeight * 2/3,
                                    height: Self.coverHeight,
                                    downsampleWidth: 400,
                                    bookmarked: bookmarkedItems.contains(entry.key)
                                )
                                .id(entry.cover ?? "") // fixes cover not updating when view is reused

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.title)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                    if let authors = entry.authors, !authors.isEmpty {
                                        Text(authors.joined(separator: ", "))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    if let description = entry.description {
                                        Text(description)
                                            .foregroundStyle(.secondary)
                                            .font(.callout)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: Self.coverHeight)
                            .padding(.bottom, hasTags ? 16 : 0)

                            if let tags = entry.tags {
                                GeometryReader { geo in
                                    HStack {
                                        let hasRating = entry.contentRating != .unknown && entry.contentRating != .safe
                                        if hasRating {
                                            LabelView(
                                                text: entry.contentRating.title,
                                                background: entry.contentRating == .suggestive
                                                    ? .orange.opacity(0.3)
                                                    : .red.opacity(0.3)
                                            )
                                        }

                                        let availableTags = numberOfItemsThatFit(in: geo.size.width, items: tags)
                                        let tagCount = availableTags - (hasRating ? 1 : 0)

                                        if tagCount > 0 {
                                            ForEach(tags.prefix(tagCount), id: \.self) { tag in
                                                LabelView(text: tag)
                                            }
                                        }

                                        Spacer(minLength: 0)
                                    }
                                }
                            }

                            // if items without tags are present while others do have them, align the view to the top
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                    }
                    .foregroundStyle(.primary)
                    .tag(offset + 1)
                    .ignoresSafeArea() // needed for ios 15 bug
                }
                .frame(height: carouselHeight) // todo: if accessible text sizes are enabled, this is wrong
                .onAppear {
                    autoScrollPaused = false
                }
                .onDisappear {
                    autoScrollPaused = true
                }
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
            for entry in entries where CoreDataManager.shared.hasLibraryManga(
                sourceId: source.key,
                mangaId: entry.key,
                context: context
            ) {
                keys.insert(entry.key)
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

struct PlaceholderMangaHomeBigScroller: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Loading")
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal)

            Self.mainView
        }
        .redacted(reason: .placeholder)
        .shimmering()
    }

    static var mainView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color(.secondarySystemFill))
                    .frame(
                        width: HomeBigScrollerView.coverHeight * 2/3,
                        height: HomeBigScrollerView.coverHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Loading Title")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)

                    Text("Loading")
                        .foregroundStyle(.secondary)

                    // swiftlint:disable:next line_length
                    Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
                .padding(.vertical, 8)
                Spacer()
            }
            .frame(height: HomeBigScrollerView.coverHeight)
            .padding(.bottom, 16)

            HStack {
                ForEach(0..<4) { _ in
                    LabelView(text: "Loading")
                }
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .frame(height: HomeBigScrollerView.coverHeight + 40)
    }
}

#Preview {
    VStack {
        HomeBigScrollerView(
            source: .demo(),
            component: .init(
                title: "Title",
                value: .bigScroller(
                    entries: [
                        .init(
                            sourceKey: "",
                            key: "",
                            title: "Manga",
                            authors: ["Author"],
                            description: "Description",
                            tags: ["Test"],
                            status: .ongoing
                        )
                    ],
                    autoScrollInterval: nil
                )
            )
        )
        PlaceholderMangaHomeBigScroller()
    }
    .padding()
}
