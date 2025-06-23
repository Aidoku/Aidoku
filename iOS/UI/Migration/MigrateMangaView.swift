//
//  MigrateMangaView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/5/23.
//

import SwiftUI

struct MigrateMangaView: View {

    @Environment(\.presentationMode) var presentationMode

    @State var manga: [Manga]
    @State var sources: [Int: SourceInfo2?]

    @State private var migrationState: MigrationState = .idle

    @State var selectedSources: [SourceInfo2] = []

//    private var strategies = MigrationStrategory.allCases
//    @State private var selectedStrategry: MigrationStrategory = .firstAlternative

    @State private var migratedManga: [Int: Manga?] = [:]
    @State private var newChapters: [Int: [Chapter]] = [:]
    @State private var states: [Int: MigrationState] = [:]

    @State var showingConfirmAlert = false

    init(manga: [Manga], destination: String? = nil) {
        _manga = State(initialValue: manga)
        var sources: [Int: SourceInfo2?] = [:]
        for manga in manga {
            sources[manga.hashValue] = SourceManager.shared.source(for: manga.sourceId)?.toInfo()
        }
        _sources = State(initialValue: sources)
        if let destination {
            if let info = SourceManager.shared.source(for: destination)?.toInfo() {
                _selectedSources = State(initialValue: [info])
            }
        }
    }

    var body: some View {
        List {
            if migrationState == .idle {
                Section(header: Text(NSLocalizedString("OPTIONS", comment: ""))) {
                    NavigationLink(NSLocalizedString("DESTINATION", comment: ""), destination: MigrateSourceSelectionView(
                        selectedSources: $selectedSources
                    ))
                    // TODO: most chapters option
//                        Picker(selection: $selectedStrategry, label: Text("Migration Strategy")) {
//                            ForEach(strategies, id: \.self) { strategy in
//                                Text(strategy.toString())
//                            }
//                        }
                    Button {
                        Task {
                            await performSearch()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.left.arrow.right")
                                .padding(4)
                            Text(NSLocalizedString("START_MATCHING", comment: ""))
                        }
                    }
                    .disabled(selectedSources.isEmpty)
                }
            }
            Section(header: Text(NSLocalizedString("TITLES", comment: ""))) {
                ForEach(manga, id: \.hashValue) { manga in
                    MangaToMangaView(
                        fromSource: sources[manga.hashValue]??.name,
                        fromManga: manga,
                        toManga: self.migratedMangaBinding(for: manga.hashValue),
                        state: stateBinding(for: manga.hashValue),
                        selectedSources: $selectedSources
                    )
                    .contextMenu {
                        if #available(iOS 15.0, *) {
                            Button(role: .destructive) {
                                remove(manga: manga)
                            } label: {
                                Label(NSLocalizedString("REMOVE", comment: ""), systemImage: "trash")
                            }
                        } else {
                            Button {
                                remove(manga: manga)
                            } label: {
                                Label(NSLocalizedString("REMOVE", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("MIGRATION", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if migrationState == .done {
                    Button(NSLocalizedString("MIGRATE", comment: "")) {
                        showingConfirmAlert = true
                    }
                    .disabled(!migratedManga.contains(where: { $0.value != nil }))
                } else if migrationState == .running {
                    ProgressView()
                }
            }
        }
        .alert(isPresented: $showingConfirmAlert) {
            let itemCount = migratedManga.filter({ item in
                item.value != nil && manga.contains(where: { manga in manga.hashValue == item.key })
            }).count
            return Alert(
                title: Text(
                    itemCount == 1
                        ? NSLocalizedString("MIGRATE_ONE_ITEM?", comment: "")
                        : String(format: NSLocalizedString("MIGRATE_%i_ITEMS?", comment: ""), itemCount)
                ),
                primaryButton: .default(Text(NSLocalizedString("CONTINUE", comment: ""))) {
                    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
                    appDelegate.showLoadingIndicator(style: .progress) {
                        Task {
                            await performMigration()
                            appDelegate.hideLoadingIndicator {
                                dismiss()
                            }
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func migratedMangaBinding(for key: Int) -> Binding<Manga?> {
        .init(
            get: { self.migratedManga[key, default: nil] },
            set: {
                self.migratedManga[key] = $0
                self.newChapters.removeValue(forKey: key)
            })
    }
    private func stateBinding(for key: Int) -> Binding<MigrationState> {
        .init(
            get: { self.states[key, default: .idle] },
            set: { self.states[key] = $0 })
    }

    func remove(manga: Manga) {
        self.manga.removeAll { $0 == manga }
        sources.removeValue(forKey: manga.hashValue)
        newChapters.removeValue(forKey: manga.hashValue)
        migratedManga.removeValue(forKey: manga.hashValue)
        states.removeValue(forKey: manga.hashValue)
    }

    // attempts all items according to selected sources
    func performSearch() async {
        withAnimation {
            migrationState = .running
        }
        // set each mangatomanga view state to running
        for i in 0..<states.count {
            states[i] = .running
        }
        await withTaskGroup(of: Void.self) { group in
            for manga in manga {
                group.addTask {
                    // check sources until a manga is found
                    for source in await selectedSources {
                        guard
                            let title = manga.title,
                            let source = SourceManager.shared.source(for: source.sourceId)
                        else { continue }
                        let search = try? await source.getSearchMangaList(query: title, page: 1, filters: [])
                        if let newManga = search?.entries.first {
                            // if we need to check chapters
//                            let chapters = try? await source.getChapterList(manga: newManga)
                            await MainActor.run {
                                withAnimation {
                                    migratedManga[manga.hashValue] = newManga.toOld()
//                                    newChapters[manga.hashValue] = chapters
                                    states[manga.hashValue] = .done
                                }
                            }
                            return
                        }
                    }
                    // didn't find a manga in any of the sources
                    await MainActor.run {
                        states[manga.hashValue] = .failed
                    }
                }
            }
        }
        withAnimation {
            migrationState = .done
        }
    }

    func performMigration() async {
        UIApplication.shared.isIdleTimerDisabled = true

        let batchSize = 10

        let newDetails = await withTaskGroup(
            of: (String, Manga, [Chapter])?.self,
            returning: [String: (Manga, [Chapter])].self
        ) { group in
            var ret: [String: (Manga, [Chapter])] = [:]
            var counter = 0

            for i in stride(from: 0, to: manga.count, by: batchSize) {
                let batch = Array(manga[i..<min(i + batchSize, manga.count)])

                for oldManga in batch {
                    group.addTask {
                        guard
                            let newManga = await migratedManga[oldManga.hashValue],
                            let newManga,
                            let source = SourceManager.shared.source(for: newManga.sourceId)
                        else { return nil }

                        let newChapters = await newChapters[oldManga.hashValue]

                        let updatedManga = try? await source.getMangaUpdate(
                            manga: newManga.toNew(),
                            needsDetails: true,
                            needsChapters: newChapters == nil
                        )

                        let mangaDetails = updatedManga?.toOld() ?? newManga
                        let chapters = newChapters
                            ?? updatedManga?.chapters?.map { $0.toOld(sourceId: newManga.sourceId, mangaId: newManga.id) }
                            ?? []

                        return (oldManga.key, mangaDetails, chapters)
                    }
                }

                // wait for all results in batch to finish before continuing
                for await result in group {
                    counter += 1
                    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                        appDelegate.indicatorProgress = Float(counter) / Float(manga.count * 2)
                    }
                    if let result {
                        ret[result.0] = (result.1, result.2)
                    }
                }
            }

            return ret
        }

        await withTaskGroup(of: (from: Manga, to: Manga)?.self) { group in
            var counter = manga.count

            for i in stride(from: 0, to: manga.count, by: batchSize) {
                let batch = Array(manga[i..<min(i + batchSize, manga.count)])

                for oldManga in batch {
                    group.addTask {
                        guard
                            let details = newDetails[oldManga.key]
                        else { return nil }

                        let newManga = details.0
                        let newChapters = details.1

                        return await CoreDataManager.shared.container.performBackgroundTask { context in
                            do {
                                // migrate manga
                                var storedManga = CoreDataManager.shared.getManga(
                                    sourceId: oldManga.sourceId,
                                    mangaId: oldManga.id,
                                    context: context
                                )

                                // new is already in library
                                if newManga.id != oldManga.id, let storedNewManga = CoreDataManager.shared.getManga(
                                    sourceId: newManga.sourceId,
                                    mangaId: newManga.id,
                                    context: context
                                ) {
                                    storedManga = storedNewManga
                                    // remove old manga
                                    CoreDataManager.shared.removeManga(
                                        sourceId: oldManga.sourceId,
                                        mangaId: oldManga.id,
                                        context: context
                                    )
                                } else {
                                    // get old manga to replace data
                                    storedManga = CoreDataManager.shared.getManga(
                                        sourceId: oldManga.sourceId,
                                        mangaId: oldManga.id,
                                        context: context
                                    )
                                }
                                storedManga?.load(from: newManga)

                                // migrate history
                                let storedOldHistory = CoreDataManager.shared.getHistoryForManga(
                                    sourceId: oldManga.sourceId,
                                    mangaId: oldManga.id,
                                    context: context
                                )

                                var maxChapterRead = storedOldHistory
                                    .compactMap { $0.chapter?.chapter != nil ? $0.chapter : nil }
                                    .max { $0.chapter!.decimalValue < $1.chapter!.decimalValue }?
                                    .chapter?.floatValue

                                if maxChapterRead == nil || maxChapterRead == -1 {
                                    // try finding max volume read instead, in case of no chapters
                                    maxChapterRead = storedOldHistory
                                        .compactMap { $0.chapter?.volume != nil ? $0.chapter : nil }
                                        .max { $0.volume!.decimalValue < $1.volume!.decimalValue }?
                                        .volume?.floatValue
                                }

                                // remove old chapters and history
                                CoreDataManager.shared.removeChapters(
                                    sourceId: oldManga.sourceId,
                                    mangaId: oldManga.id,
                                    context: context
                                )

                                CoreDataManager.shared.removeHistory(
                                    sourceId: oldManga.sourceId,
                                    mangaId: oldManga.id,
                                    context: context
                                )

                                // store new chapters
                                CoreDataManager.shared.setChapters(
                                    newChapters.map { $0.toNew() },
                                    sourceId: newManga.sourceId,
                                    mangaId: newManga.id,
                                    context: context
                                )

                                // mark new chapters as read
                                if let maxChapterRead {
                                    var chaptersToMark = newChapters.filter({ $0.chapterNum ?? Float.greatestFiniteMagnitude <= maxChapterRead })
                                    if chaptersToMark.isEmpty {
                                        // fall back to using volume numbers instead, in case the source we're migrating to uses volumes
                                        chaptersToMark = newChapters.filter({ $0.volumeNum ?? Float.greatestFiniteMagnitude <= maxChapterRead })
                                    }
                                    if !chaptersToMark.isEmpty {
                                        CoreDataManager.shared.setCompleted(
                                            chapters: chaptersToMark,
                                            context: context
                                        )
                                    }
                                }

                                // migrate trackers
                                let trackItems = CoreDataManager.shared.getTracks(
                                    sourceId: oldManga.sourceId,
                                    mangaId: oldManga.id,
                                    context: context
                                )

                                for item in trackItems {
                                    guard
                                        let trackerId = item.trackerId,
                                        !CoreDataManager.shared.hasTrack(
                                            trackerId: trackerId,
                                            sourceId: newManga.sourceId,
                                            mangaId: newManga.id,
                                            context: context
                                        )
                                    else { continue }

                                    item.sourceId = newManga.sourceId
                                    item.mangaId = newManga.id
                                }

                                try context.save()

                                return (from: oldManga, to: newManga)
                            } catch {
                                LogManager.logger.error("Error migrating manga \(oldManga.key): \(error)")
                                return nil
                            }
                        }
                    }
                }

                for await result in group {
                    counter += 1
                    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                        appDelegate.indicatorProgress = Float(counter) / Float(manga.count * 2)
                    }
                    if let result {
                        NotificationCenter.default.post(name: .migratedManga, object: result)
                    }
                }
            }
        }

        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)

        UIApplication.shared.isIdleTimerDisabled = false
    }

    func dismiss() {
        presentationMode.wrappedValue.dismiss()

        // for ios 14 and to dismiss the sheet if migrating from browse tab
        if var topController = UIApplication.shared.firstKeyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            topController.dismiss(animated: true)
        }
    }
}
