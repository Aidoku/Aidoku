//
//  SourceHomeContentView.swift
//  Aidoku
//
//  Created by Skitty on 4/28/25.
//

import AidokuRunner
import SwiftUI

struct SourceHomeContentView: View {
    let source: AidokuRunner.Source

    @Binding var listings: [AidokuRunner.Listing]
    @Binding var headerListingSelection: Int // used only for listing header

    @State private var home: Home?
    @State private var listingHome: Home? // Home-like layout for current listing
    @State private var entries: [AidokuRunner.Manga] = []

    @State private var hasLoaded = false
    @State private var loading = true
    @State private var homeFullyLoaded = false
    @State private var listingSelection = 0
    @State private var page = 1
    @State private var hasMore = false
    @State private var bookmarkedItems: Set<String> = .init()

    @State private var error: Error?

    @State private var loadTask: Task<(), Never>?
    @State private var loadListingTask: Task<(), Never>?

    enum ListingLoadState {
        case loading
        case notLoading
        case allLoaded
    }

    @State private var listingLoadState: ListingLoadState = .loading

    @StateObject private var path: NavigationCoordinator

    private var currentListing: AidokuRunner.Listing? {
        listing(for: listingSelection)
    }

    private func listing(for selection: Int) -> AidokuRunner.Listing? {
        let listingIndex = selection - (source.features.providesHome ? 1 : 0)
        return listings[safe: listingIndex]
    }

    init(
        source: AidokuRunner.Source,
        holdingViewController: UIViewController,
        listings: Binding<[AidokuRunner.Listing]>,
        headerListingSelection: Binding<Int>
    ) {
        self.source = source
        self._listings = listings
        self._headerListingSelection = headerListingSelection

        weak var holding = holdingViewController
        self._path = StateObject(wrappedValue: NavigationCoordinator(rootViewController: holding))
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack {}.id(0) // indicator to scroll to the top

                if loading {
                    // loading skeleton
                    Group {
                        if listingSelection == 0 && source.features.providesHome {
                            SourceHomeSkeletonView(source: source)
                        } else if let listing = currentListing {
                            switch listing.kind {
                                case .default:
                                    HomeGridView.placeholder
                                case .list:
                                    PlaceholderMangaHomeList(showTitle: false)
                            }
                        }
                    }
                    .transition(.opacity)
                } else if error != nil {
                    // fix for transition animation
                    Spacer()
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                } else if let home, listingSelection == 0 {
                    // home page
                    homeView(for: home, partial: !homeFullyLoaded)
                } else if listingSelection > 0 || !source.features.providesHome, let listing = currentListing {
                    // listing page - check if source provides custom Home-like layout
                    if let listingHome {
                        homeView(for: listingHome, partial: false)
                            .transition(.opacity)
                    } else {
                        // Display listing with listing.kind
                        Group {
                            switch listing.kind {
                                case .default:
                                    HomeGridView(source: source, entries: entries, bookmarkedItems: $bookmarkedItems) {
                                        if hasMore && listingLoadState != .loading {
                                            await loadEntries()
                                        }
                                    }
                                case .list:
                                    HomeListView(
                                        source: source,
                                        component: .init(title: nil, value: .mangaList(entries: entries.map { $0.intoLink() }))
                                    ) {
                                        if hasMore && listingLoadState != .loading {
                                            await loadEntries()
                                        }
                                    }
                                    .id(listingSelection) // Force recreation on listing change
                                    .padding(.bottom)
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .overlay {
                if let error {
                    ErrorView(error: error) {
                        await reload()
                    }
                    .transition(.opacity)
                }
            }
            .refreshable {
                // nesting task prevents it from being cancelled
                let task = Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // delay to fix animation
                    await reload()
                }
                await task.value
            }
            // update listingSelection when header selection changes;
            // a separate variable is used in order to perform the rest of the changes along with listingSelection
            // immediately rather than having a slight delay
            .onChange(of: headerListingSelection) { value in
                loadListingTask?.cancel()
                loadListingTask = Task {
                    withAnimation {
                        error = nil
                    }

                    // todo: there's a slight delay here if we're already scrolled to the top
                    await animate(duration: 0.2) {
                        reader.scrollTo(0)
                    }

                    if value != 0 || !source.features.providesHome {
                        // load listing
                        // Always set listing selection and pass the new value
                        await animate(duration: 0.2, options: .easeOut) {
                            listingSelection = value
                            loading = true  // Show loading when switching
                        }
                        await loadListing(setListingSelection: value)
                    } else {
                        // switch to home
                        await animate(duration: 0.2, options: .easeOut) {
                            loading = false
                            entries = []
                            listingHome = nil
                        }
                        withAnimation(.easeIn(duration: 0.2)) {
                            listingSelection = value
                        }

                        if home == nil {
                            loading = true
                            homeFullyLoaded = false
                            await loadHome()
                        } else {
                            loading = false
                        }
                    }
                }
            }
        }
        .onChange(of: listings) { value in
            // reset listing selection to the first if the selected one disappears
            let maxListings = value.count - (source.features.providesHome ? 0 : 1)
            if listingSelection > maxListings {
                headerListingSelection = 0
            } else if !source.features.providesHome || (source.features.providesHome && listingSelection > 0) {
                // otherwise, reload current listing
                Task {
                    await reload()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("refresh-content"))) { _ in
            loadTask?.cancel()
            loadTask = Task {
                guard !Task.isCancelled else { return }
                await reload()
                // reload home page even if we're not on it
                if source.features.providesHome && listingSelection != 0 {
                    await loadHome()
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await reload(initial: true)
        }
        .environmentObject(path)
    }

    func homeView(for home: Home, partial: Bool) -> some View {
        VStack(spacing: 24) {
            ForEach(home.components.indices, id: \.self) { offset in
                let component = home.components[offset]
                switch component.value {
                    case .imageScroller:
                        HomeImageScrollerView(source: source, component: component, partial: partial)
                    case .bigScroller:
                        HomeBigScrollerView(source: source, component: component, partial: partial)
                    case .scroller:
                        HomeScrollerView(source: source, component: component, partial: partial)
                    case .mangaList:
                        HomeListView(source: source, component: component, partial: partial)
                            .id("listing-\(offset)") // Force recreation for listing components
                    case .mangaChapterList:
                        HomeChapterListView(source: source, component: component, partial: partial)
                    case .filters:
                        HomeFiltersView(source: source, component: component, partial: partial)
                    case .links:
                        HomeLinksView(source: source, component: component, partial: partial)
                }
            }
            .transition(.opacity)
        }
        .padding(.bottom)
    }

    func reload(initial: Bool = false) async {
        loadListingTask?.cancel()
        withAnimation {
            error = nil
        }
        // only load listings when actually reloading
        // they're loaded in ListingsHeaderView initially
        if !initial {
            // don't fail the entire home screen if listings fail to load
            if let newListings = try? await source.getListings() {
                listings = newListings
            }
            guard !Task.isCancelled else { return }
        }
        homeFullyLoaded = false
        if source.features.providesHome && listingSelection == 0 {
            await loadHome()
        } else {
            await loadListing()
        }
    }

    func loadHome() async {
        await source.partialHomePublisher?.sink { @Sendable partialHome in
            Task { @MainActor in
                withAnimation {
                    self.home = partialHome
                    if headerListingSelection == 0 {
                        loading = false
                    }
                }
            }
        }
        do {
            let home = try await source.getHome()
            withAnimation {
                self.home = home
            }

            // update stored component types for skeleton loading
            let storedComponentsKey = "\(source.key).homeComponents"
            let storedComponents = UserDefaults.standard.array(forKey: storedComponentsKey)
            let componentCount = storedComponents.flatMap { $0.count / 2 } ?? 0
            if componentCount != home.components.count {
                let result = home.components.flatMap {
                    switch $0.value {
                        case let .mangaList(_, pageSize, entries, _):
                            return [3, min(pageSize ?? .max, entries.count)]
                        case let .mangaChapterList(pageSize, entries, _):
                            return [4, min(pageSize ?? .max, entries.count)]
                        default:
                            return [$0.value.intValue, 0]
                    }
                }
                UserDefaults.standard.set(result, forKey: storedComponentsKey)
            }
        } catch {
            self.home = nil
            withAnimation {
                self.error = error
            }
        }
        await source.partialHomePublisher?.removeSink()

        withAnimation {
            if headerListingSelection == 0 {
                loading = false
            }
            homeFullyLoaded = true
        }
    }

    func loadListing(setListingSelection: Int? = nil) async {
        page = 1
        listingHome = nil  // Clear previous listing home when loading new listing
        await loadEntries(initial: true, setListingSelection: setListingSelection)
    }

    func loadEntries(initial: Bool = false, setListingSelection: Int? = nil) async {
        do {
            guard let listing = listing(for: setListingSelection ?? listingSelection)
            else { return }

            listingLoadState = .loading

            // Try to get Home-like layout first
            if initial {
                if let home = try await source.getListingHome(listing: listing) {
                    // Source provides custom Home-like layout for this listing
                    listingHome = home

                    // fade out existing items and show new Home-like layout
                    await animate(duration: 0.2, options: .easeOut) {
                        entries = []
                    }

                    // switch the listing selection, if specified
                    if let setListingSelection {
                        await animate(duration: 0.1, options: .easeInOut) {
                            listingSelection = setListingSelection
                        }
                    }

                    await animate(duration: 0.2, options: .easeIn) {
                        loading = false
                    }

                    listingLoadState = .allLoaded
                    return
                } else {
                    // No custom layout, use default pagination
                    listingHome = nil
                }
            } else if listingHome != nil {
                // If we have a listing home (Home-like layout), we shouldn't paginate
                // This prevents loading more when scrolling in Home-like view
                return
            }

            var resultsLoaded = false

            // start loading listing items
            let resultTask = Task {
                let result = try await source.getMangaList(listing: listing, page: page)
                resultsLoaded = true
                return result
            }

            hasMore = false

            // fade out existing items
            if initial && !entries.isEmpty {
                await animate(duration: 0.2, options: .easeOut) {
                    entries = []
                }
            }

            // switch the listing selection, if specified
            if let setListingSelection {
                await animate(duration: 0.1, options: .easeInOut) {
                    listingSelection = setListingSelection
                }
            }

            // show loading view if results aren't done loading yet after animations
            if initial, !resultsLoaded {
                await animate(duration: 0.2, options: .easeIn) {
                    loading = true
                }
            }

            // load new results
            let result = try await resultTask.value

            guard !Task.isCancelled else { return }

            hasMore = result.hasNextPage
            listingLoadState = hasMore ? .notLoading : .allLoaded
            page += 1

            // load bookmark icons for stuff that's in our library
            let bookmarkedKeys: [String] = await CoreDataManager.shared.container.performBackgroundTask { context in
                var keys: [String] = []
                for manga in result.entries where CoreDataManager.shared.hasLibraryManga(
                    sourceId: self.source.key,
                    mangaId: manga.key,
                    context: context
                ) {
                    keys.append(manga.key)
                }
                return keys
            }
            bookmarkedItems.formUnion(bookmarkedKeys)

            // hide loading view
            if loading {
                await animate(duration: 0.2, options: .easeIn) {
                    loading = false
                }
            }

            guard !Task.isCancelled else { return }

            if initial {
                withAnimation(.easeIn(duration: 0.2)) {
                    entries = result.entries
                }
            } else {
                // append to existing entries
                withAnimation(.easeIn(duration: 0.2)) {
                    entries += result.entries
                }
            }
        } catch {
            guard !Task.isCancelled else { return }

            loading = false
            withAnimation {
                self.error = error
            }
        }
    }
}
