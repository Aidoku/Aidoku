//
//  MangaListView.swift
//  Aidoku
//
//  Created by Skitty on 12/30/24.
//

import AidokuRunner
import SwiftUI

struct MangaListView: View {
    let source: AidokuRunner.Source
    var title: String = ""
    var listingKind: ListingKind = .default

    var getEntries: ((Int) async throws -> AidokuRunner.MangaPageResult)?
    var onSelect: ((AidokuRunner.Manga) -> Void)?

    @EnvironmentObject private var path: NavigationCoordinator

    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var entries: [AidokuRunner.Manga] = []
    @State private var error: Error?

    @State private var loading = true
    @State private var loadingMore = false
    @State private var bookmarkedItems: Set<String> = .init()

    var body: some View {
        ScrollView(.vertical) {
            if loading {
                switch listingKind {
                    case .default:
                        HomeGridView.placeholder
                    case .list:
                        PlaceholderMangaHomeList(showTitle: false)
                }
            } else if error != nil {
                Spacer()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                switch listingKind {
                    case .default:
                        HomeGridView(
                            source: source,
                            entries: entries,
                            bookmarkedItems: $bookmarkedItems,
                            loadMore: {
                                if hasMore {
                                    await loadEntries()
                                }
                            },
                            onSelect: onSelect
                        )
                    case .list:
                        HomeListView(
                            source: source,
                            component: .init(title: nil, value: .mangaList(entries: entries.map { $0.intoLink() })),
                            bookmarkedItems: $bookmarkedItems,
                            loadMore: {
                                if hasMore {
                                    await loadEntries()
                                }
                            },
                            onSelect: onSelect
                        )
                        .padding(.bottom)
                }
            }
        }
        .overlay {
            if let error {
                ErrorView(error: error) {
                    await loadEntries()
                }
                .transition(.opacity)
            }
        }
        .disabled(loading)
        .task {
            guard entries.isEmpty else { return }
            await loadEntries()
            loading = false
        }
        .navigationTitle(title)
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .animation(.default, value: entries)
    }

    func loadEntries() async {
        do {
            withAnimation {
                error = nil
            }

            let result = try await getEntries?(nextPage)
            guard let result else { return }

            await CoreDataManager.shared.container.performBackgroundTask { context in
                for manga in result.entries where CoreDataManager.shared.hasLibraryManga(
                    sourceId: source.key,
                    mangaId: manga.key,
                    context: context
                ) {
                    bookmarkedItems.insert(manga.key)
                }
            }

            hasMore = result.hasNextPage
            nextPage += 1
            entries += result.entries
            loadingMore = false
        } catch {
            withAnimation {
                self.error = error
            }
        }
    }
}
