//
//  MigrateSourcesView.swift
//  Aidoku
//
//  Created by skitty on 1/6/23.
//

import AidokuRunner
import SwiftUI

struct MigrateSourcesView: View {
    struct MigrateSourceInfo: Identifiable {
        var id: String
        var name: String?
        var langs: [String]
        var coverUrl: URL?
        let source: AidokuRunner.Source?
    }

    @State private var isLoading = true
    @State private var sources: [MigrateSourceInfo] = []
    @State private var manga: [String: [AidokuRunner.Manga]] = [:]

    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        List {
            ForEach(sources) { item in
                let name = item.name ?? item.id
                Button {
                    path.push(MigrateSelectSeriesView(
                        sourceName: name,
                        series: manga[item.id] ?? [],
                        source: item.source
                    ))
                } label: {
                    SourceCell(
                        item: item,
                        name: name,
                        count: manga[item.id]?.count ?? 0
                    )
                }
                .foregroundStyle(.primary)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if isLoading {
                ProgressView().progressViewStyle(.circular)
            }
        }
        .navigationTitle(NSLocalizedString("MIGRATE_SOURCES"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSources()
            isLoading = false
        }
    }
}

extension MigrateSourcesView {
    struct SourceCell: View {
        let item: MigrateSourceInfo
        let name: String
        let count: Int

        var body: some View {
            HStack {
                SourceIconView(sourceId: item.id, imageUrl: item.coverUrl)
                    .padding(.trailing, 6)

                VStack(alignment: .leading) {
                    HStack {
                        Text(name)
                        Text(String(format: "(%i)", count))
                            .padding(.leading, -2)
                    }
                    if
                        !item.langs.isEmpty,
                        let langString = (item.langs.count > 1 || item.langs.first == "multi")
                            ? NSLocalizedString("MULTI_LANGUAGE")
                            : Locale.current.localizedString(forIdentifier: item.langs[0])
                    {
                        Text(langString)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

extension MigrateSourcesView {
    func loadSources() async {
        manga = await CoreDataManager.shared.container.performBackgroundTask { context in
            let objects = CoreDataManager.shared.getLibraryManga(context: context)
            var manga: [String: [AidokuRunner.Manga]] = [:]
            for object in objects {
                guard let mangaObject = object.manga else { continue }
                var mangaArray = manga[mangaObject.sourceId] ?? []
                mangaArray.append(mangaObject.toNewManga())
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
                    langs: source?.languages ?? [],
                    coverUrl: coverUrl,
                    source: source
                )
            }
            .sorted { $0.name ?? "" < $1.name ?? "" }
            .sorted {
                let lhs = SourceManager.languageCodes.firstIndex(of: $0.langs.count == 1 ? $0.langs[0] : "multi") ?? Int.max
                let rhs = SourceManager.languageCodes.firstIndex(of: $1.langs.count == 1 ? $1.langs[0] : "multi") ?? Int.max
                return lhs < rhs
            }
    }
}
