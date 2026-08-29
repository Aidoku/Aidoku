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
        let mangaId: MangaIdentifier
        var updates: [UpdateInfo]
    }
    struct UpdateInfo: Identifiable, Hashable {
        let id: String
        let chapterIdentifier: ChapterIdentifier
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
                    if objects.contains(where: { $0.chapterId.mangaIdentifier == manga.identifier }) {
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
                ForEach(items, id: \.mangaId) { item in
                    let updates = item.updates
                    if let update = updates.first {
                        NavigationLink(
                            destination: MangaView(manga: update.manga, path: path)
                                .onAppear {
                                    setOpened(manga: update.manga)
                                }
                        ) {
                            MangaUpdateItemView(updates: updates)
                        }
                        .offsetListSeparator()
                        .id(item.mangaId)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeUpdateItem(item: item, day: entry.day)
                            } label: {
                                Label(NSLocalizedString("DELETE"), systemImage: "trash")
                            }
                        }
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
        let newUpdates = await CoreDataManager.shared.container.performBackgroundTask { [offset] context in
            CoreDataManager.shared.getRecentMangaUpdates(limit: limit, offset: offset, context: context).compactMap {
                if let mangaObj = CoreDataManager.shared.getManga(
                    mangaId: $0.identifier.mangaIdentifier,
                    context: context
                ) {
                    return UpdateInfo(
                        id: $0.id,
                        chapterIdentifier: $0.identifier,
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
            withAnimation {
                hasNoUpdates = entries.isEmpty
            }
            return
        }

        let newUpdatesGrouped = Dictionary(grouping: newUpdates, by: \.manga.identifier)
        var updatesDict: [Int: [MangaIdentifier: [UpdateInfo]]] = entries
            .reduce(into: [:]) {
                $0[$1.day] = $1.items.reduce(into: [:]) {
                    $0[$1.mangaId] = $1.updates
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
                        .map { .init(mangaId: $0.key, updates: $0.value) }
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
        if !AppSettings.general.incognitoMode.get() {
            Task {
                await CoreDataManager.shared.setOpened(mangaId: manga.identifier)
                NotificationCenter.default.post(name: .updateLibrary, object: nil)
            }
        }
    }

    private func removeUpdateItem(item: Item, day: Int) {
        let updates = item.updates.map {
            $0.chapterIdentifier
        }

        var newEntries = entries
        if let sectionIndex = newEntries.firstIndex(where: { $0.day == day }) {
            var section = newEntries[sectionIndex]
            section.items.removeAll(where: { $0.mangaId == item.mangaId })
            if section.items.isEmpty {
                newEntries.remove(at: sectionIndex)
            } else {
                newEntries[sectionIndex] = section
            }
        }

        withAnimation {
            entries = newEntries
            if newEntries.isEmpty { hasNoUpdates = true }
        }

        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.removeMangaUpdates(
                    updates: updates,
                    context: context
                )
                try? context.save()
            }
        }
    }
}
