//
//  SourceSearchView.swift
//  Aidoku
//
//  Created by Skitty on 9/16/23.
//

import AidokuRunner
import SwiftUI
import UniformTypeIdentifiers

struct SourceSearchView: View {
    let source: AidokuRunner.Source

    @Binding var searchText: String
    @Binding var enabledFilters: [FilterValue]
    @Binding var hidden: Bool
    @Binding var searchCommitToggle: Bool
    @Binding var scrollTopToggle: Bool
    @Binding var importing: Bool

    @StateObject private var viewModel: ViewModel
    @StateObject private var path: NavigationCoordinator

    init(
        source: AidokuRunner.Source,
        holdingViewController: UIViewController,
        searchText: Binding<String>,
        enabledFilters: Binding<[FilterValue]>,
        hidden: Binding<Bool> = .constant(false),
        searchCommitToggle: Binding<Bool> = .constant(false),
        scrollTopToggle: Binding<Bool> = .constant(false),
        importing: Binding<Bool> = .constant(false)
    ) {
        self.source = source
        self._searchText = searchText
        self._enabledFilters = enabledFilters
        self._hidden = hidden
        self._searchCommitToggle = searchCommitToggle
        self._scrollTopToggle = scrollTopToggle
        self._importing = importing

        self._viewModel = .init(wrappedValue: ViewModel(source: source))
        weak var holding = holdingViewController
        self._path = StateObject(wrappedValue: NavigationCoordinator(rootViewController: holding ))
    }

    var body: some View {
        Group {
            if hidden {
                // prevent items from loading/updating when view is hidden
                ScrollView {}
            } else {
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        VStack {}.id(0) // indicator to scroll to the top

                        contentView(scrollProxy: reader)
                    }
#if os(macOS)
                    .navigationTitle(NSLocalizedString("Search"))
                    .background(Color(NSColor.underPageBackgroundColor))
                    .searchable(text: $searchText)
#endif
                    .scrollDismissesKeyboardInteractively()
                    .onChange(of: searchText) { _ in
                        // queue search update (with delay) when text changes
                        viewModel.loadManga(
                            searchText: searchText,
                            filters: enabledFilters,
                            delay: true,
                            scrollProxy: reader
                        )
                    }
                    .onChange(of: searchCommitToggle) { _ in
                        // update search when enter pressed
                        viewModel.loadManga(
                            searchText: searchText,
                            filters: enabledFilters,
                            force: true,
                            scrollProxy: reader
                        )
                    }
                    .onChange(of: enabledFilters) { _ in
                        // update search when filters change
                        viewModel.loadManga(
                            searchText: searchText,
                            filters: enabledFilters,
                            force: true,
                            scrollProxy: reader
                        )
                    }
                    .onChange(of: scrollTopToggle) { _ in
                        // scroll to top when toggle changes
                        reader.scrollTo(0, anchor: .top)
                    }
                    .refreshable {
                        viewModel.loadManga(searchText: searchText, filters: enabledFilters, force: true)
                        await viewModel.waitForSearch()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .init("refresh-content"))) { _ in
                        viewModel.loadManga(searchText: searchText, filters: enabledFilters, force: true)
                    }
                    .onAppear {
                        // load initial search results
                        viewModel.onAppear(searchText: searchText, filters: enabledFilters)
                    }
                }
            }
        }
        .sheet(isPresented: $importing) {
            LocalFileImportView()
        }
    }

    @ViewBuilder
    private func contentView(scrollProxy: ScrollViewProxy?) -> some View {
        let group = Group {
            if let error = viewModel.error {
                ErrorView(error: error) {
                    viewModel.loadManga(
                        searchText: searchText,
                        filters: enabledFilters,
                        scrollProxy: scrollProxy
                    )
                }
                .padding(.top, 150)
            } else if viewModel.loadingInitial {
                HomeGridView.placeholder
            } else {
                HomeGridView(
                    source: source,
                    entries: viewModel.entries,
                    bookmarkedItems: $viewModel.bookmarkedItems
                ) {
                    await viewModel.loadMore(searchText: searchText, filters: enabledFilters)
                }
                .environmentObject(path)
            }
        }
        if #available(iOS 26.0, *) {
            group.padding(.top, 4)
        } else {
            group
        }
    }
}

// MARK: - View Model
extension SourceSearchView {
    @MainActor
    class ViewModel: ObservableObject {
        private let source: AidokuRunner.Source

        @Published var entries: [AidokuRunner.Manga] = []
        @Published var error: Error?
        @Published var loadingInitial = true
//        @Published var showEntries = false
        @Published var bookmarkedItems: Set<String> = .init()

        private(set) var hasMore = true
        private(set) var nextPage = 1

        private var hasAppeared = false
        private var currentSearch: String = "_"
        private var searchTask: Task<(), Never>?
        private var loadMoreTask: Task<(), Never>?

        init(source: AidokuRunner.Source) {
            self.source = source
        }

        func onAppear(searchText: String, filters: [FilterValue]) {
            guard !hasAppeared, entries.isEmpty else { return }
            hasAppeared = true
            loadManga(searchText: searchText, filters: filters)
        }

        func waitForSearch() async {
            await searchTask?.value
        }

        func loadManga(
            searchText: String,
            filters: [FilterValue],
            delay: Bool = false,
            force: Bool = false,
            scrollProxy: ScrollViewProxy? = nil
        ) {
            guard force || currentSearch != searchText else { return }
            withAnimation {
                error = nil
            }
            nextPage = 1
            currentSearch = searchText
            searchTask?.cancel()
            loadMoreTask?.cancel()
            searchTask = Task {
                if delay {
                    // delay for one second
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                guard !Task.isCancelled else { return }
                do {
                    let result = try await source.getSearchMangaList(
                        query: searchText,
                        page: 1,
                        filters: filters
                    )
                    guard !Task.isCancelled else { return }
                    await loadBookmarks(entries: result.entries)
                    hasMore = result.hasNextPage
                    await updateEntriesWithAnimation(result.entries, scrollProxy: scrollProxy)
                    nextPage = 2
                    if loadingInitial {
                        withAnimation {
                            loadingInitial = false
                        }
                    }
                } catch {
                    withAnimation {
                        self.error = error
                    }
                }
            }
        }

        func loadMore(searchText: String, filters: [FilterValue]) async {
            await loadMoreTask?.value
            guard hasMore else { return }
            loadMoreTask = Task {
                await searchTask?.value
                guard !Task.isCancelled else { return }
                do {
                    let result = try await source.getSearchMangaList(
                        query: searchText,
                        page: nextPage,
                        filters: filters
                    )
                    guard !Task.isCancelled else { return }
                    await loadBookmarks(entries: result.entries)
                    hasMore = result.hasNextPage

                    // ensure no duplicate entries
                    var hashValues = Set(entries.map { $0.hashValue })
                    let newEntries = result.entries.filter { hashValues.insert($0.hashValue).inserted }
                    withAnimation {
                        entries += newEntries
                    }

                    nextPage += 1
                    if result.entries.isEmpty && hasMore {
                        await loadMore(searchText: searchText, filters: filters)
                    }
                } catch {
                    withAnimation {
                        self.error = error
                    }
                }
            }
        }

        func loadBookmarks(entries: [AidokuRunner.Manga]) async {
            let bookmarkedKeys: [String] = await CoreDataManager.shared.container.performBackgroundTask { context in
                var keys: [String] = []
                for manga in entries where CoreDataManager.shared.hasLibraryManga(
                    sourceId: self.source.key,
                    mangaId: manga.key,
                    context: context
                ) {
                    keys.append(manga.key)
                }
                return keys
            }
            bookmarkedItems.formUnion(bookmarkedKeys)
        }

        private func updateEntriesWithAnimation(
            _ newEntries: [AidokuRunner.Manga],
            scrollProxy: ScrollViewProxy? = nil
        ) async {
//            await animate(duration: 0.2, options: .easeIn) {
//                self.showEntries = false
//            }
            scrollProxy?.scrollTo(0)
            withAnimation {
                self.entries = newEntries
            }
//            withAnimation(.easeOut(duration: 0.2)) {
//                self.showEntries = true
//            }
        }
    }
}
