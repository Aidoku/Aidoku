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
    }

    @State var entries: [(Int, [MangaUpdateInfo])] = []
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
                }// :List
                .listStyle(.plain)
            }
        }// :Group
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("MANGA_UPDATES")
        .refreshableCompat {
            await reload()
        }
    }

    @available(iOS 15.0, *)
    var listItemsWithSections: some View {
        ForEach(entries.indices, id: \.self) { days in
            Section {
                ForEach(entries[days].1) { mangaUpdate in
                    NavigationLink(destination: MangaView(manga: mangaUpdate.manga)) {
                        MangaUpdateItemView(item: mangaUpdate)
                    }
                }
            } header: {
                Text(makeRelativeDate(days))
                    .foregroundStyle(.primary)
                    .font(.system(size: 16, weight: .medium))
            }
        }
    }

    var listItems: some View {
        ForEach(entries.indices, id: \.self) { days in
            Text(makeRelativeDate(days))
                .foregroundColor(.primary)
                .font(.system(size: 16, weight: .medium))

            ForEach(entries[days].1) { mangaUpdate in
                NavigationLink(destination: MangaView(manga: mangaUpdate.manga)) {
                    MangaUpdateItemView(item: mangaUpdate)
                }
            }
        }
    }

    private func loadNewEntries() async {
        let mangaUpdates = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getRecentMangaUpdates(limit: 15, offset: offset, context: context).compactMap {
                if let mangaObj = CoreDataManager.shared.getManga(
                    sourceId: $0.sourceId,
                    mangaId: $0.mangaId,
                    context: context
                ) {
                    return MangaUpdateInfo(
                        id: $0.id,
                        date: $0.date,
                        manga: mangaObj.toManga(),
                        chapter: $0.chapter?.toChapter()
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
        var updatesDict: [Int: [MangaUpdateInfo]] = entries.reduce(into: [:]) { $0[$1.0] = $1.1 }
        for obj in mangaUpdates {
            let day = Calendar.autoupdatingCurrent.dateComponents(
                Set([Calendar.Component.day]),
                from: obj.date,
                to: Date()
            ).day ?? 0

            var updatesOfTheDay = updatesDict[day] ?? []
            updatesOfTheDay.append(obj)
            updatesDict[day] = updatesOfTheDay
        }
        let finalUpdatesDict = updatesDict
        await MainActor.run {
            self.entries = finalUpdatesDict.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
            self.offset += 15
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

    private func makeRelativeDate(_ days: Int) -> String {
        let now = Date()
        let date = now.addingTimeInterval(-86400 * Double(days))
        let difference = Calendar.autoupdatingCurrent.dateComponents(Set([Calendar.Component.day]), from: date, to: now)

        // today or yesterday
        if days < 2 {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.doesRelativeDateFormatting = true
            return formatter.string(from: date)
        } else if days < 8 { // n days ago
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .short
            formatter.allowedUnits = .day
            guard let timePhrase = formatter.string(from: difference) else { return "" }
            return String(format: NSLocalizedString("%@_AGO", comment: ""), timePhrase)
        } else { // mm/dd/yy
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}
