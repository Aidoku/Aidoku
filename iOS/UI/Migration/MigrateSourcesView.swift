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
        var lang: String?
        var coverUrl: URL?
    }

    @State var sources: [MigrateSourceInfo] = []
    @State var manga: [String: [Manga]] = [:]

    var body: some View {
        List(sources) { source in
            NavigationLink(destination: MigrateMangaView(manga: manga[source.id] ?? [])) {
                HStack {
                    LazyImage(url: source.coverUrl) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image("MangaPlaceholder") // placeholder
                        }
                    }
                    .frame(width: 48, height: 48)
                    .cornerRadius(48 * 0.225)
                    .overlay(
                        RoundedRectangle(cornerRadius: 48 * 0.225)
                            .stroke(Color(UIColor.quaternarySystemFill), lineWidth: 1)
                    )
                    .padding(.trailing, 6)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(source.name ?? source.id)
                            Text(String(format: "(%i)", manga[source.id]?.count ?? 0))
                                .padding(.leading, -2)
                        }
                        if
                            let lang = source.lang,
                            let langString = lang == "multi"
                                ? NSLocalizedString("MULTI_LANGUAGE", comment: "")
                                : (Locale.current as NSLocale).displayName(forKey: .identifier, value: lang)
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
                let coverUrl = source?.url.appendingPathComponent("Icon.png")
                return MigrateSourceInfo(
                    id: id,
                    name: source?.manifest.info.name,
                    lang: source?.manifest.info.lang,
                    coverUrl: coverUrl
                )
            }
            .sorted { $0.name ?? "" < $1.name ?? "" }
            .sorted {
                let lhs = SourceManager.languageCodes.firstIndex(of: $0.lang ?? "") ?? 0
                let rhs = SourceManager.languageCodes.firstIndex(of: $1.lang ?? "") ?? 0
                return lhs < rhs
            }
    }
}
