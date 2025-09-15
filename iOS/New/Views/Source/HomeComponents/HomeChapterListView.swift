//
//  HomeChapterListView.swift
//  Aidoku
//
//  Created by Skitty on 10/13/23.
//

import AidokuRunner
import SwiftUI

struct HomeChapterListView: View {
    let source: AidokuRunner.Source
    let component: HomeComponent
    let partial: Bool

    @EnvironmentObject private var path: NavigationCoordinator

    private let pageSize: Int?
    private let entries: [MangaWithChapter]
    private let listing: AidokuRunner.Listing?

    @State private var bookmarkedItems: Set<String> = .init()
    @State private var loadedBookmarks = false

    init(
        source: AidokuRunner.Source,
        component: HomeComponent,
        partial: Bool = false
    ) {
        self.source = source
        self.component = component
        self.partial = partial

        guard case let .mangaChapterList(pageSize, entries, listing) = component.value else {
            fatalError("invalid component type")
        }
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
                                        AnyView(view(for: entries[offset]).ignoresSafeArea())
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
                                view(for: entries[offset])
                            }
                        }
                    }
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func view(for entry: MangaWithChapter) -> some View {
        Button {
            path.push(MangaViewController(source: source, manga: entry.manga, parent: path.rootViewController))
        } label: {
            HStack(spacing: 12) {
                MangaCoverView(
                    source: source,
                    coverImage: entry.manga.cover ?? "",
                    width: 100 * 2/3,
                    height: 100,
                    downsampleWidth: 200,
                    bookmarked: bookmarkedItems.contains(entry.manga.key)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.manga.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(entry.chapter.formattedTitle())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let date = entry.chapter.dateUploaded {
                        Label(relativeTimeString(for: date), systemImage: "clock")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .foregroundStyle(.primary)
        .multilineTextAlignment(.leading)
        .buttonStyle(.borderless)
    }

    func loadBookmarked() async {
        guard !entries.isEmpty else { return }
        bookmarkedItems = await CoreDataManager.shared.container.performBackgroundTask { context in
            var keys: Set<String> = .init()
            for entry in entries where CoreDataManager.shared.hasLibraryManga(
                sourceId: source.key,
                mangaId: entry.manga.key,
                context: context
            ) {
                keys.insert(entry.manga.key)
            }
            return keys
        }
        loadedBookmarks = true
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())

        // to do it manually (but not localized):
//        let now = Date()
//        let components = Calendar.current.dateComponents(
//            [.second, .minute, .hour, .day, .weekOfYear, .month, .year],
//            from: date,
//            to: now
//        )
//
//        if let years = components.year, years > 0 {
//            return "\(years)y ago"
//        } else if let months = components.month, months > 0 {
//            return "\(months)mo ago"
//        } else if let weeks = components.weekOfYear, weeks > 0 {
//            return "\(weeks)w ago"
//        } else if let days = components.day, days > 0 {
//            return "\(days)d ago"
//        } else if let hours = components.hour, hours > 0 {
//            return "\(hours)h ago"
//        } else if let minutes = components.minute, minutes > 0 {
//            return "\(minutes)m ago"
//        } else if let seconds = components.second, seconds > 0 {
//            return "\(seconds)s ago"
//        } else {
//            return "Just now"
//        }
    }
}
