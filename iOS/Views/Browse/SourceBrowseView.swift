//
//  SourceBrowseView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/14/22.
//

import SwiftUI

struct SourceBrowseView: View {
    let source: Source
    
    @State var listings: [Listing] = []
    @State var listingResults: [String: [Manga]] = [:]
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(listings, id: \.self) { listing in
                    MangaCarouselView(title: listing.name, manga: listingResults[listing.name] ?? [])
                }
            }
        }
        .navigationTitle(source.info.name)
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
}
