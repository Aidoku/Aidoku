//
//  MangaToMangaView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/5/23.
//

import SwiftUI

struct MangaToMangaView: View {

    var fromSource: String?
    @State var toSource: String?

    var fromManga: Manga
    @Binding var toManga: Manga?

    @Binding var state: MigrationState
    @Binding var selectedSources: [SourceInfo2]

    var body: some View {
        HStack(alignment: .top) {
            Spacer()
            VStack(alignment: .leading) {
                MangaGridView(title: fromManga.title, coverUrl: fromManga.coverUrl)
                    .frame(width: 130, height: 195)
                Text(fromSource ?? NSLocalizedString("UNKNOWN", comment: ""))
                    .font(.footnote)
            }
            Image(systemName: "arrow.right")
                .frame(maxHeight: 180, alignment: .center)
                .padding(4)
            VStack(alignment: .leading) {
                if let toManga = toManga {
                    MangaGridView(title: toManga.title, coverUrl: toManga.coverUrl)
                        .frame(width: 130, height: 195)
                        .overlay(
                            NavigationLink("", destination: MigrateSearchMatchView(
                                manga: fromManga,
                                newManga: $toManga,
                                sourcesToSearch: selectedSources
                            )).foregroundColor(.clear)
                        )
                } else {
                    if state == .running {
                        PlaceholderMangaGridView()
                            .frame(width: 130, height: 195)
                            .overlay(ProgressView())
                    } else if state == .failed {
                        PlaceholderMangaGridView()
                            .frame(width: 130, height: 195)
                            .overlay(ZStack {
                                Text(NSLocalizedString("NOT_FOUND", comment: ""))
                                NavigationLink("", destination: MigrateSearchMatchView(
                                    manga: fromManga,
                                    newManga: $toManga,
                                    sourcesToSearch: selectedSources
                                )).foregroundColor(.clear)
                            }.padding(4))
                    } else {
                        PlaceholderMangaGridView()
                            .frame(width: 130, height: 195)
                    }
                }
                if let name = toSource {
                    Text(name)
                    .font(.footnote)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .onChange(of: toManga) { newValue in
            if let newValue = newValue {
                if let source = SourceManager.shared.source(for: newValue.sourceId) {
                    toSource = source.name
                }
            } else {
                toSource = nil
            }
        }
    }
}
