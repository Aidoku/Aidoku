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

    private var strategies = MigrationStrategory.allCases
    @State private var selectedStrategry: MigrationStrategory = .firstAlternative

    @State private var migratedManga: [Int: Manga?] = [:]
    @State private var newChapters: [Int: [Chapter]] = [:]
    @State private var states: [Int: MigrationState] = [:]

    @State var showingConfirmAlert = false

    init(manga: [Manga]) {
        _manga = State(initialValue: manga)
        var sources: [Int: SourceInfo2?] = [:]
        for manga in manga {
            sources[manga.hashValue] = SourceManager.shared.source(for: manga.sourceId)?.toInfo()
        }
        _sources = State(initialValue: sources)
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
                    appDelegate.showLoadingIndicator {
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
                        let search = try? await source.fetchSearchManga(query: title)
                        if let newManga = search?.manga.first {
                            // if we need to check chapters
//                            let chapters = try? await source.getChapterList(manga: newManga)
                            await MainActor.run {
                                withAnimation {
                                    migratedManga[manga.hashValue] = newManga
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

    // swiftlint:disable:next cyclomatic_complexity
    func performMigration() async {
        let newDetails = await withTaskGroup(
            of: (Int, Manga, [Chapter])?.self,
            returning: [Int: (Manga, [Chapter])].self
        ) { group in
            for oldManga in manga {
                group.addTask {
                    guard
                        let newManga = await migratedManga[oldManga.hashValue],
                        let newManga = newManga,
                        let source = SourceManager.shared.source(for: newManga.sourceId)
                    else { return nil }

                    let mangaDetails = (try? await source.getMangaDetails(manga: newManga)) ?? newManga

                    let chapters: [Chapter]
                    if let newChapters = await newChapters[oldManga.hashValue] {
                        chapters = newChapters
                    } else {
                        chapters = (try? await source.getChapterList(manga: mangaDetails)) ?? []
                    }

                    return (oldManga.hashValue, mangaDetails, chapters)
                }
            }
            var ret: [Int: (Manga, [Chapter])] = [:]
            for await result in group {
                guard let result = result else { continue }
                ret[result.0] = (result.1, result.2)
            }
            return ret
        }

        await withTaskGroup(of: (from: Manga, to: Manga)?.self) { group in
            for oldManga in manga {
                group.addTask {
                    guard
                        let details = newDetails[oldManga.hashValue]
                    else { return nil }

                    let newManga = details.0
                    let newChapters = details.1

                    // migrate manga
                    let mangaMigrateTask = Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
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
                                CoreDataManager.shared.removeManga(sourceId: oldManga.sourceId, mangaId: oldManga.id, context: context)
                            } else {
                                // get old manga to replace data
                                storedManga = CoreDataManager.shared.getManga(
                                    sourceId: oldManga.sourceId,
                                    mangaId: oldManga.id,
                                    context: context
                                )
                            }
                            storedManga?.load(from: newManga)
                            try? context.save()
                        }
                    }

                    // migrate history
                    let historyMigrateTask = Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            let storedOldHistory = CoreDataManager.shared.getHistoryForManga(
                                sourceId: oldManga.sourceId,
                                mangaId: oldManga.id,
                                context: context
                            )
                            let maxChapterRead = storedOldHistory
                                .compactMap { $0.chapter?.chapter != nil ? $0.chapter : nil }
                                .max { $0.chapter!.decimalValue < $1.chapter!.decimalValue }?
                                .chapter?.floatValue
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
                                newChapters,
                                sourceId: newManga.sourceId,
                                mangaId: newManga.id,
                                context: context
                            )
                            // mark new chapters as read
                            if let maxChapterRead = maxChapterRead {
                                CoreDataManager.shared.setCompleted(
                                    chapters: newChapters.filter({ $0.chapterNum ?? Float.greatestFiniteMagnitude <= maxChapterRead }),
                                    context: context
                                )
                            }
                            try? context.save()
                        }
                    }

                    // migrate trackers
                    let trackMigrateTask = Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
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
                            try? context.save()
                        }
                    }

                    await mangaMigrateTask.value
                    await historyMigrateTask.value
                    await trackMigrateTask.value

                    return (from: oldManga, to: newManga)
                }
            }
            for await result in group {
                guard let result = result else { continue }
                NotificationCenter.default.post(name: Notification.Name("migratedManga"), object: result)
            }
        }
        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
    }

    func dismiss() {
        presentationMode.wrappedValue.dismiss()

        // for ios 14 and to dismiss the sheet if migrating from browse tab
        if var topController = UIApplication.shared.windows.first!.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            topController.dismiss(animated: true)
        }
    }
}
