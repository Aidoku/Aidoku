//
//  SearchResultView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/16/22.
//

import SwiftUI

struct SearchResultView: View {
    let source: Source
    let search: String
    
    @State var results: [Manga]
    
    @State var currentPage: Int = 1
    @State var hasMore: Bool = true
    
    var body: some View {
        ScrollView {
            Spacer()
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
            if hasMore {
                Button {
                    Task {
                        await loadMore()
                    }
                } label: {
                    Text("Load More")
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("\"\(search)\"")
    }
    
    func loadMore() async {
        currentPage += 1
        let result = try? await source.fetchSearchManga(query: search, page: currentPage)
        if let result = result {
            hasMore = result.hasNextPage
            withAnimation {
                results.append(contentsOf: result.manga)
            }
        }
    }
}
