//
//  MangaUpdatesView.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 09/02/2024.
//

import AidokuRunner
import SwiftUI

struct MangaUpdatesView: View {
    struct UpdateSection: Hashable {
        let day: Int
        var items: [Item]
    }
    struct Item: Hashable {
        let mangaKey: String
        var updates: [UpdateInfo]
    }
    struct UpdateInfo: Identifiable, Hashable {
        let id: String
        let date: Date
        let manga: AidokuRunner.Manga
        let chapter: Chapter?
        var viewed: Bool
    }

    private let limit = 25

    @State private var entries: [UpdateSection] = []
    @State private var offset = 0
    @State private var loadingMore = false
    @State private var reachedEnd = false
    @State private var hasNoUpdates = false
    @State private var loadingTask: Task<(), Never>?

    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        Group {
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
            .overlay {
                if hasNoUpdates {
                    VStack(alignment: .center) {
                        Spacer()
                        Text(NSLocalizedString("NO_UPDATES"))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("MANGA_UPDATES"))
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("mangaUpdatesViewed"))) { notification in
            guard let objects = notification.object as? [MangaUpdateItem] else { return }

            for section in 0..<entries.count {
                for item in 0..<entries[section].items.count {
                    guard let manga = entries[section].items[item].updates.first?.manga else { continue }
                    if objects.contains(where: { $0.sourceId == manga.sourceKey && $0.mangaId == manga.key }) {
                        for i in 0..<entries[section].items[item].updates.count {
                            entries[section].items[item].updates[i].viewed = true
                        }
                    }
                }
            }
        }
    }

    var listItemsWithSections: some View {
        ForEach(entries, id: \.day) { entry in
            Section {
                let items = entry.items
                ForEach(items, id: \.mangaKey) { item in
                    let updates = item.updates
                    if let manga = updates.first?.manga {
                        NavigationLink(
                            destination: MangaView(manga: manga, path: path)
                                .onAppear {
                                    setOpened(manga: manga)
                                }
                        ) {
                            MangaUpdateItemView(updates: updates)
                        }
                        .offsetListSeparator()
                        .id(item.mangaKey)
                    }
                }
            } header: {
                Text(Date.makeRelativeDate(days: entry.day))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .listRowSeparator(.hidden)
        }
    }

    var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .id(UUID()) // fixes progress view being invisible
            Spacer()
        }
        .listRowSeparator(.hidden)
    }
}

extension MangaUpdatesView {
    private func loadNewEntries() async {
        let newUpdates = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getRecentMangaUpdates(limit: limit, offset: offset, context: context).compactMap {
                if let mangaObj = CoreDataManager.shared.getManga(
                    sourceId: $0.sourceId ?? "",
                    mangaId: $0.mangaId ?? "",
                    context: context
                ) {
                    return UpdateInfo(
                        id: $0.id,
                        date: $0.date ?? Date(),
                        manga: mangaObj.toNewManga(),
                        chapter: $0.chapter?.toChapter(),
                        viewed: $0.viewed
                    )
                } else {
                    return nil
                }
            }
        }
        guard !newUpdates.isEmpty else {
            reachedEnd = true
            loadingMore = false
            return
        }

        let newUpdatesGrouped = Dictionary(grouping: newUpdates, by: \.manga.uniqueKey)
        var updatesDict: [Int: [String: [UpdateInfo]]] = entries
            .reduce(into: [:]) {
                $0[$1.day] = $1.items.reduce(into: [:]) {
                    $0[$1.mangaKey] = $1.updates
                }
            }
        for obj in newUpdatesGrouped {
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
        let newEntries: [UpdateSection] = updatesDict
            .map {
                .init(
                    day: $0.key,
                    items: $0.value
                        .map { .init(mangaKey: $0.key, updates: $0.value) }
                        .sorted { ($0.updates.first?.date ?? Date()) > ($1.updates.first?.date ?? Date()) }
                )
            }
            .sorted { $0.day < $1.day }

        guard !Task.isCancelled else { return }

        offset += limit
        reachedEnd = newUpdates.count < limit

        withAnimation {
            entries = newEntries
            loadingMore = false
            if reachedEnd && newEntries.isEmpty {
                hasNoUpdates = true
            }
        }
    }

    private func setOpened(manga: AidokuRunner.Manga) {
        if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
            Task {
                await CoreDataManager.shared.setOpened(sourceId: manga.sourceKey, mangaId: manga.key)
                NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
            }
        }
    }
}
