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
                            } label: {
                                Label(NSLocalizedString("REMOVE", comment: ""), systemImage: "trash")
                            }
                            .foregroundColor(.red)
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
            let itemCount = migratedManga.filter({ $0.value != nil }).count
            return Alert(
                title: Text(
                    itemCount == 1
                        ? NSLocalizedString("MIGRATE_ONE_ITEM?", comment: "")
                        : String(format: NSLocalizedString("MIGRATE_%i_ITEMS?", comment: ""), itemCount)
                ),
                primaryButton: .default(Text(NSLocalizedString("CONTINUE", comment: ""))) {
                    Task {
                        (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
                        await performMigration()
                        dismiss()
                        (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func migratedMangaBinding(for key: Int) -> Binding<Manga?> {
        .init(
            get: { self.migratedManga[key, default: nil] },
            set: { self.migratedManga[key] = $0 })
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
        mangaLoop: for manga in manga {
            // check sources until a manga is found
            for source in selectedSources {
                guard
                    let title = manga.title,
                    let source = SourceManager.shared.source(for: source.sourceId)
                else { continue }
                let search = try? await source.fetchSearchManga(query: title)
                if let newManga = search?.manga.first {
                    // fetch full manga details
                    let details = (try? await source.getMangaDetails(manga: newManga)) ?? newManga
                    // load chapters
                    let chapters = try? await source.getChapterList(manga: details)
                    migratedManga[manga.hashValue] = details
                    newChapters[manga.hashValue] = chapters ?? []
                    states[manga.hashValue] = .done
                    continue mangaLoop
                }
            }
            // didn't find a manga in any of the sources
            states[manga.hashValue] = .failed
        }
        withAnimation {
            migrationState = .done
        }
    }

    func performMigration() async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            var migrations: [(from: Manga, to: Manga)] = []
            for oldManga in manga {
                guard
                    let newManga = migratedManga[oldManga.hashValue],
                    let newManga = newManga,
                    let newChapters = newChapters[oldManga.hashValue]
                else { continue }

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
                    CoreDataManager.shared.removeManga(sourceId: oldManga.sourceId, mangaId: oldManga.id, context: context)
                } else {
                    // get old manga to replace data
                    storedManga = CoreDataManager.shared.getManga(
                        sourceId: oldManga.sourceId,
                        mangaId: oldManga.id,
                        context: context
                    )
                }
                guard let storedManga = storedManga else { continue } // shouldn't be possible to migrate manga not in library
                storedManga.load(from: newManga)

                // migrate history
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
                CoreDataManager.shared.removeChapters(sourceId: oldManga.sourceId, mangaId: oldManga.id, context: context)
                CoreDataManager.shared.removeHistory(sourceId: oldManga.sourceId, mangaId: oldManga.id, context: context)
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
                migrations.append((from: oldManga, to: newManga))
            }
            do {
                try context.save()
                for migration in migrations {
                    NotificationCenter.default.post(name: Notification.Name("migratedManga"), object: migration)
                }
            } catch {
                LogManager.logger.error(error.localizedDescription + " at \(#function):\(#line)")
            }
        }
        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
    }

    func dismiss() {
        presentationMode.wrappedValue.dismiss()
        if var topController = UIApplication.shared.windows.first!.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            topController.dismiss(animated: true)
        }
    }
}
