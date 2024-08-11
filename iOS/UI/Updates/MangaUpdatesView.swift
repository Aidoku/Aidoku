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
        var viewed: Bool
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
                    listItemsWithSections

                    if !reachedEnd {
                        loadingView
                            .onAppear {
                                if !loadingMore {
                                    reachedEnd = true
                                    loadingMore = true
                                    loadingTask = Task {
                                        await loadNewEntries()
                                    }
                                }
                            }
                    } else if loadingMore {
                        loadingView
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("mangaUpdatesViewed"))) { notification in
            guard let objects = notification.object as? [MangaUpdateItem] else { return }

            for section in 0..<entries.count {
                for item in 0..<entries[section].1.count {
                    guard let manga = entries[section].1[item].1.first?.manga else { continue }
                    if objects.contains(where: { $0.sourceId == manga.sourceId && $0.mangaId == manga.id }) {
                        for i in 0..<entries[section].1[item].1.count {
                            entries[section].1[item].1[i].viewed = true
                        }
                    }
                }
            }
        }
    }

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
                        .offsetListSeparator()
                    }
                }
            } header: {
                Text(Date.makeRelativeDate(days: entries[index].0))
                    .foregroundColor(.primary)
                    .font(.system(size: 16, weight: .medium))
            }
            .hideListSectionSeparator()
        }
    }

    var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .id(UUID()) // fixes progress view being invisible
            Spacer()
        }
        .hideListRowSeparator()
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
                    to: Date.endOfDay()
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
        reachedEnd = true
        await loadNewEntries()
    }
}
