//
//  MangaUpdatesView.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 09/02/2024.
//

import SwiftUI

struct MangaUpdatesView: View {

    struct MangaUpdateInfo: Identifiable {
        let id: String
        let date: Date
        let manga: Manga
        let chapter: Chapter?
        let viewed: Bool
    }

    private let limit = 25
    @State var entries: [(Int, [(String, [MangaUpdateInfo])])] = []
    @State var offset = 0
    @State var loadingMore = false
    @State var reachedEnd = false
    @State var loadingTask: Task<(), Never>?

    var body: some View {
        Group {
            if reachedEnd && entries.isEmpty {
                VStack(alignment: .center) {
                    Spacer()
                    Text("NO_UPDATES")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    if #available(iOS 15.0, *) {
                        listItemsWithSections
                    } else {
                        listItems
                    }

                    if !reachedEnd {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .onAppear {
                            if !loadingMore {
                                loadingMore = true
                                loadingTask = Task {
                                    await loadNewEntries()
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("MANGA_UPDATES")
        .refreshableCompat {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("mangaUpdatesViewed"))) { _ in
            // TODO: reload the list
            // there is a bug when mixing UIKit navigation with SwiftUI
            // that pops back the destination when updating a State variable
        }
    }

    @available(iOS 15.0, *)
    var listItemsWithSections: some View {
        ForEach(entries.indices, id: \.self) { index in
            Section {
                let mangas = entries[index].1
                ForEach(mangas.indices, id: \.self) { mangaIndex in
                    let updates = mangas[mangaIndex].1
                    if let manga = updates.first?.manga {
                        NavigationLink(destination: MangaView(manga: manga)) {
                            MangaUpdateItemView(updates: updates)
                        }
                    }
                }
            } header: {
                Text(Date.makeRelativeDate(days: entries[index].0))
                    .foregroundStyle(.primary)
                    .font(.system(size: 16, weight: .medium))
            }
        }
    }

    var listItems: some View {
        ForEach(entries.indices, id: \.self) { index in
            Text(Date.makeRelativeDate(days: entries[index].0))
                .foregroundColor(.primary)
                .font(.system(size: 16, weight: .medium))

            let mangas = entries[index].1
            ForEach(mangas.indices, id: \.self) { mangaIndex in
                let updates = mangas[mangaIndex].1
                if let manga = updates.first?.manga {
                    NavigationLink(destination: MangaView(manga: manga)) {
                        MangaUpdateItemView(updates: updates)
                    }
                }
            }
        }
    }

    private func loadNewEntries() async {
        let mangaUpdates = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getRecentMangaUpdates(limit: limit, offset: offset, context: context).compactMap {
                if let mangaObj = CoreDataManager.shared.getManga(
                    sourceId: $0.sourceId ?? "",
                    mangaId: $0.mangaId ?? "",
                    context: context
                ) {
                    return MangaUpdateInfo(
                        id: $0.id,
                        date: $0.date ?? Date(),
                        manga: mangaObj.toManga(),
                        chapter: $0.chapter?.toChapter(),
                        viewed: $0.viewed
                    )
                } else {
                    return nil
                }
            }
        }
        if mangaUpdates.isEmpty {
            await MainActor.run {
                self.reachedEnd = true
                self.loadingMore = false
            }
            return
        }
        let updatesGrouped = Dictionary(grouping: mangaUpdates, by: \.manga.id)
        var updatesDict: [Int: [String: [MangaUpdateInfo]]] = entries
            .reduce(into: [:]) { $0[$1.0] = $1.1.reduce(into: [:]) { $0[$1.0] = $1.1 } }
        for obj in updatesGrouped {
            for info in obj.value.sorted(by: { $0.date < $1.date }) {
                let day = Calendar.autoupdatingCurrent.dateComponents(
                    Set([Calendar.Component.day]),
                    from: info.date,
                    to: Date()
                ).day ?? 0

                var updatesOfTheDay = updatesDict[day] ?? [:]
                var newValue = updatesOfTheDay[obj.key] ?? []
                newValue.append(info)
                updatesOfTheDay[obj.key] = newValue
                updatesDict[day] = updatesOfTheDay
            }
        }
        let finalUpdatesDict = updatesDict
        await MainActor.run {
            self.entries = finalUpdatesDict
                .map {
                    ($0.key,
                     $0.value
                        .map { ($0.key, $0.value) }
                        .sorted { ($0.1.first?.date ?? Date()) > ($1.1.first?.date ?? Date()) }
                    )
                }
                .sorted { $0.0 < $1.0 }
            self.reachedEnd = mangaUpdates.count < limit
            self.offset += limit
            self.loadingMore = false
        }
    }

    private func reload() async {
        if loadingMore {
            loadingTask?.cancel()
            loadingTask = nil
        }
        loadingMore = true
        entries = []
        offset = 0
        reachedEnd = false
        await loadNewEntries()
    }
}
