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
    @State var results: [String: [Manga]] = [:]
    
    var body: some View {
        NavigationView {
            ScrollView {
                Spacer()
                if isSearching && results.isEmpty && !searchText.isEmpty {
                    ActivityIndicator()
                } else if !searchText.isEmpty {
                    LazyVStack(alignment: .leading) {
                        ForEach(sources) { source in
                            if !isEditing || !results.isEmpty {
                                MangaCarouselView(title: source.info.name, manga: results[source.info.id] ?? [])
                            }
                        }
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
        .onAppear {
            sources = SourceManager.shared.sources
        }
    }
    
    func doSearch() async {
        for source in SourceManager.shared.sources {
            let search = try? await source.fetchSearchManga(query: searchText)
            results[source.info.id] = search?.manga ?? []
        }
        isSearching = false
    }
}
