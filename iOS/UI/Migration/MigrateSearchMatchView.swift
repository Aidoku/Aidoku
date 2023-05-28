//
//  MigrateSearchMatchView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/5/23.
//

import SwiftUI

struct MigrateSearchMatchView: View {

    @Environment(\.presentationMode) var presentationMode

    var manga: Manga
    @Binding var newManga: Manga?
    var sourcesToSearch: [SourceInfo2]

    private var sources: [Source]

    @State private var searching = true
    @State private var searchResults: [String: [Manga]] = [:]

    @State private var searchText: String = ""
    @State private var searchTask: Task<Void, Never>?

    init(manga: Manga, newManga: Binding<Manga?>, sourcesToSearch: [SourceInfo2]) {
        self.manga = manga
        self.sourcesToSearch = sourcesToSearch
        _newManga = newManga
        sources = sourcesToSearch.compactMap { SourceManager.shared.source(for: $0.sourceId) }
//        _searchText = State(initialValue: manga.title ?? "")
    }

    var body: some View {
        ScrollView(.vertical) {
            ForEach(sourcesToSearch, id: \.self) { source in
                VStack(alignment: .leading) {
                    HStack {
                        Text(source.name)
                            .font(.system(size: 19))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Spacer()
                        if searchResults[source.sourceId] == nil {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, 16)
                    if !(searchResults[source.sourceId]?.isEmpty ?? true) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(searchResults[source.sourceId] ?? [], id: \.self) { searchManga in
                                    Button {
                                        newManga = searchManga
                                        presentationMode.wrappedValue.dismiss()
                                    } label: {
                                        MangaGridView(title: searchManga.title, coverUrl: searchManga.coverUrl)
                                            .frame(width: 120, height: 180)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .navigationBarSearch($searchText, hidesSearchBarWhenScrolling: false)
        .onChange(of: searchText) { _ in
            search(delay: 3)
        }
        .onAppear {
            search()
        }
    }

    // delay in ms
    func search(delay: UInt64 = 0) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: delay * 100_000_000)
            if Task.isCancelled {
                return
            }
            let searchText: String
            if self.searchText.isEmpty {
                searchText = manga.title ?? ""
            } else {
                searchText = self.searchText
            }
            for source in sources {
                Task {
                    let results = (try? await source.fetchSearchManga(query: searchText))?.manga
                    withAnimation {
                        searchResults[source.id] = results ?? []
                    }
                }
            }
        }
    }
}
