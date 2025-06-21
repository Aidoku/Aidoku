//
//  MigrateSourcesView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/6/23.
//

import SwiftUI
import NukeUI

// view that lists sources available for migration

struct MigrateSourcesView: View {

    @Environment(\.presentationMode) var presentationMode

    struct MigrateSourceInfo: Identifiable {
        var id: String
        var name: String?
        var langs: [String]?
        var coverUrl: URL?
    }

    @State var sources: [MigrateSourceInfo] = []
    @State var manga: [String: [Manga]] = [:]

    var body: some View {
        List(sources) { source in
            NavigationLink(destination: MigrateMangaView(manga: manga[source.id] ?? [])) {
                HStack {
                    SourceIconView(sourceId: source.id, imageUrl: source.coverUrl)
                        .padding(.trailing, 6)

                    VStack(alignment: .leading) {
                        HStack {
                            Text(source.name ?? source.id)
                            Text(String(format: "(%i)", manga[source.id]?.count ?? 0))
                                .padding(.leading, -2)
                        }
                        if
                            let langs = source.langs,
                            !langs.isEmpty,
                            let langString = (langs.count > 1 || langs.first == "multi")
                                ? NSLocalizedString("MULTI_LANGUAGE")
                                : Locale.current.localizedString(forIdentifier: langs.first!)
                        {
                            Text(langString)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("MIGRATE_SOURCES", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await loadSources()
            }
        }
    }

    func loadSources() async {
        manga = await CoreDataManager.shared.container.performBackgroundTask { context in
            let objects = CoreDataManager.shared.getLibraryManga(context: context)
            var manga: [String: [Manga]] = [:]
            for object in objects {
                guard let mangaObject = object.manga else { continue }
                var mangaArray = manga[mangaObject.sourceId] ?? []
                mangaArray.append(mangaObject.toManga())
                manga[mangaObject.sourceId] = mangaArray
            }
            return manga
        }
        sources = manga.keys
            .map { id in
                let source = SourceManager.shared.source(for: id)
                let coverUrl = source?.imageUrl
                return MigrateSourceInfo(
                    id: id,
                    name: source?.name,
                    langs: source?.languages,
                    coverUrl: coverUrl
                )
            }
            .sorted { $0.name ?? "" < $1.name ?? "" }
            .sorted {
                let lhs = ($0.langs?.count ?? 0) > 1 ? 0 : SourceManager.languageCodes.firstIndex(of: $0.langs?.first ?? "") ?? Int.max
                let rhs = ($1.langs?.count ?? 0) > 1 ? 0 : SourceManager.languageCodes.firstIndex(of: $1.langs?.first ?? "") ?? Int.max
                return lhs < rhs
            }
    }
}
