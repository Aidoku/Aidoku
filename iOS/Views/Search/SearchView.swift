//
//  SearchView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/21.
//

import SwiftUI
import SwiftUIX

struct SearchView: View {
    
    @State var sources = SourceManager.shared.sources
    
    @State var isEditing: Bool = false
    @State var isSearching: Bool = false
    @State var searchText: String = ""
    @State var results: [String: MangaPageResult] = [:]
    
    let sourcePublisher = NotificationCenter.default.publisher(for: Notification.Name("updateSourceList"))
    
    var body: some View {
        NavigationView {
            ScrollView {
                Spacer()
                if isSearching && results.isEmpty && !searchText.isEmpty && !isEditing {
                    ActivityIndicator()
                }
                LazyVStack(alignment: .leading) {
                    ForEach(sources) { source in
                        if !searchText.isEmpty && !results.isEmpty {
                            MangaCarouselView(title: source.info.name, manga: results[source.info.id]?.manga ?? []) {
                                SearchResultView(source: source, search: searchText, results: results[source.info.id]?.manga ?? [], hasMore: results[source.info.id]?.hasNextPage ?? false)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .navigationSearchBar {
                SearchBar("Search", text: $searchText, isEditing: $isEditing) {
                    isSearching = true
                    results = [:]
                    Task {
                        await doSearch()
                    }
                }
                .onCancel {
                    isSearching = false
                    results = [:]
                }
                .showsCancelButton(isEditing)
            }
        }
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                results = [:]
            }
        }
        .onReceive(sourcePublisher) { _ in
            sources = SourceManager.shared.sources
            if !searchText.isEmpty {
                Task {
                    await doSearch()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    func doSearch() async {
        guard !searchText.isEmpty else { return }
        for source in SourceManager.shared.sources {
            let search = try? await source.fetchSearchManga(query: searchText)
            withAnimation {
                results[source.info.id] = search
            }
        }
        isSearching = false
    }
}
