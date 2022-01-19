//
//  SourceBrowseView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/14/22.
//

import SwiftUI
import SwiftUIX

struct SourceBrowseView: View {
    let source: Source
    
    @State var listings: [Listing] = []
    @State var listingResults: [String: [Manga]] = [:]
    
    @State var isEditing: Bool = false
    @State var isSearching: Bool = false
    @State var isLoadingResults: Bool = false
    @State var searchText: String = ""
    @State var results: [Manga] = []
    
    @State var configuringFilters = false
    @State var selectedFilters: [Filter] = []
    
    var mangaToList: [Manga] {
        if !isSearching {
            return listingResults.first?.value ?? []
        } else {
            return results
        }
    }
    
    var body: some View {
        ScrollView {
            Spacer()
            if (!searchText.isEmpty && results.isEmpty && isLoadingResults) || (listingResults.first?.value ?? []).isEmpty {
                ActivityIndicator()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                ForEach(mangaToList, id: \.self) { manga in
                    NavigationLink {
                        MangaView(manga: manga)
                    } label: {
                        LibraryGridCell(manga: manga)
                    }
                }
                .transition(.opacity)
            }
            .padding(.horizontal)
        }
        .navigationTitle(source.info.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    configuringFilters.toggle()
                } label: {
                    if #available(iOS 15.0, *) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    } else {
                        Image(systemName: "line.horizontal.3.decrease.circle")
                    }
                }
                Button { } label: {
                    Image(systemName: "ellipsis")
                }
                .disabled(true)
            }
        }
        .navigationSearchBar {
            SearchBar("Search", text: $searchText, isEditing: $isEditing) {
                isSearching = true
                isLoadingResults = true
                results = []
                Task {
                    await doSearch()
                }
            }
            .onCancel {
                isSearching = false
                isLoadingResults = false
                results = []
            }
            .showsCancelButton(isEditing)
        }
        .sheet(isPresented: $configuringFilters) {
            SourceFiltersView(source: source, selected: $selectedFilters)
        }
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                results = []
                isLoadingResults = false
            }
        }
        .onChange(of: configuringFilters) { newValue in
            if !newValue {
                Task {
                    if let listing = listings.first {
                        let search = try? await source.getMangaList(filters: selectedFilters)
                        withAnimation {
                            listingResults[listing.name] = search?.manga ?? []
                        }
                    }
                }
            }
        }
        .onAppear {
            if listings.isEmpty {
                Task {
                    listings = (try? await source.getListings()) ?? []
                    if let listing = listings.first {
                        let result = (try? await source.getMangaListing(listing: listing))?.manga ?? []
                        withAnimation {
                            listingResults[listing.name] = result
                        }
                    }
                }
            }
        }
    }
    
    func doSearch() async {
        guard !searchText.isEmpty else { return }
        let search = try? await source.fetchSearchManga(query: searchText, filters: selectedFilters)
        withAnimation {
            results = search?.manga ?? []
            isLoadingResults = false
        }
    }
}
