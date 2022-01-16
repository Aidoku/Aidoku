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
    
    var body: some View {
        ScrollView {
            if !isSearching {
                LazyVStack(alignment: .leading) {
                    ForEach(listings, id: \.self) { listing in
                        MangaCarouselView(title: listing.name, manga: listingResults[listing.name] ?? []) {
                            SourceListingView(source: source, listing: listing, results: listingResults[listing.name] ?? [])
                        }
                    }
                }
            } else if !searchText.isEmpty {
                Spacer()
                if results.isEmpty && isLoadingResults {
                    ActivityIndicator()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                        ForEach(results, id: \.self) { manga in
                            NavigationLink {
                                MangaView(manga: manga)
                            } label: {
                                LibraryGridCell(manga: manga)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                }
            }
        }
        .navigationTitle(source.info.name)
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
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                results = []
                isLoadingResults = false
            }
        }
        .onAppear {
            if listings.isEmpty {
                Task {
                    listings = (try? await source.getListings()) ?? []
                    for listing in listings {
                        listingResults[listing.name] = (try? await source.getMangaListing(listing: listing))?.manga ?? []
                    }
                }
            }
        }
    }
    
    func doSearch() async {
        let search = try? await source.fetchSearchManga(query: searchText)
        results = search?.manga ?? []
        isLoadingResults = false
    }
}
