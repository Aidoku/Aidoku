//
//  SearchView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/21.
//

import SwiftUI
import SwiftUIX

struct SearchView: View {
    
    @State var isEditing: Bool = false
    @State var isSearching: Bool = false
    @State var isLoadingMore: Bool = false
    @State var isMore: Bool = false
    @State var searchText: String = ""
    @State var results: [Manga] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                Spacer()
                if isSearching && results.isEmpty && !searchText.isEmpty {
                    ActivityIndicator()
                } else if !searchText.isEmpty {
                    ForEach(results, id: \.self) {
                        MangaListCell(manga: $0)
                    }
                    if !results.isEmpty && isMore {
                        if isLoadingMore {
                            ActivityIndicator()
                        } else {
                            Button {
                                Task {
                                    await loadMore()
                                }
                            } label: {
                                Text("Load More")
                            }
                        }
                        Spacer()
                    }
                } else {
                    Spacer()
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .navigationSearchBar {
                SearchBar("Search", text: $searchText, isEditing: $isEditing) {
                    isSearching = true
                    results = []
                    Task {
                        await doSearch()
                    }
                }
                .onCancel {
                    isSearching = false
                    results = []
                }
                .showsCancelButton(isEditing)
            }
        }
    }
    
    func doSearch() async {
        let provider = ProviderManager.shared.provider(for: "xyz.skitty.mangadex")
        let search = await provider.fetchSearchManga(query: searchText, page: 0, filters: [])
        results = search.manga
        isMore = search.hasNextPage
    }
    
    func loadMore() async {
        isLoadingMore = true
        let provider = ProviderManager.shared.provider(for: "xyz.skitty.mangadex")
        let search = await provider.fetchSearchManga(query: searchText, page: Int(results.count / 10))
//        results = search.manga
        results.append(contentsOf: search.manga)
        isMore = search.hasNextPage
        isLoadingMore = false
    }
}
