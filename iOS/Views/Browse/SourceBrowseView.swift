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
            if !searchText.isEmpty && results.isEmpty && isLoadingResults {
                ActivityIndicator()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    ForEach(mangaToList, id: \.self) { manga in
                        NavigationLink {
                            MangaView(manga: manga)
                        } label: {
                            LibraryGridCell(manga: manga)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(source.info.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { } label: {
                    if #available(iOS 15.0, *) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    } else {
                        Image(systemName: "line.horizontal.3.decrease.circle")
                    }
                }
                .disabled(true)
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
