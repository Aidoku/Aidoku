//
//  MigrateMangaView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/5/23.
//

import SwiftUI

struct MigrateMangaView: View {

    @Environment(\.presentationMode) var presentationMode

    var manga: [Manga]
    var sources: [SourceInfo2?]

    @State private var migrationState: MigrationState = .idle

    @State var selectedSources: [SourceInfo2] = []

    private var strategies = MigrationStrategory.allCases
    @State private var selectedStrategry: MigrationStrategory = .firstAlternative

    @State private var migratedManga: [Manga?] = []
    @State private var newChapters: [[Chapter]] = []
    @State private var states: [MigrationState] = []

    @State var showingConfirmAlert = false

    init(manga: [Manga]) {
        self.manga = manga
        self.sources = manga.map {
            SourceManager.shared.source(for: $0.sourceId)?.toInfo()
        }
        _migratedManga = State(initialValue: (0..<manga.count).map { _ in nil })
        _newChapters = State(initialValue: (0..<manga.count).map { _ in [] })
        _states = State(initialValue: (0..<manga.count).map { _ in .idle })
    }

    var body: some View {
        NavigationView {
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
                                Text("Start Matching")
                            }
                        }
                        .disabled(selectedSources.isEmpty)
                    }
                }
                Section(header: Text(NSLocalizedString("TITLES", comment: ""))) {
                    ForEach(Array(manga.enumerated()), id: \.offset) { offset, manga in
                        MangaToMangaView(
                            fromSource: sources[offset]?.name,
                            fromManga: manga,
                            toManga: $migratedManga[offset],
                            state: $states[offset],
                            selectedSources: $selectedSources
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("MIGRATION", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("CANCEL", comment: "")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if migrationState == .done {
                        Button(NSLocalizedString("MIGRATE", comment: "")) {
                            showingConfirmAlert = true
                        }
                        .disabled(migratedManga.filter({ $0 != nil }).isEmpty)
                    } else if migrationState == .running {
                        ProgressView()
                    }
                }
            }
            .alert(isPresented: $showingConfirmAlert) {
                let itemCount = migratedManga.filter({ $0 != nil }).count
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
        .navigationViewStyle(StackNavigationViewStyle())
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
        mangaLoop: for (offset, manga) in manga.enumerated() {
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
                    migratedManga[offset] = details
                    newChapters[offset] = chapters ?? []
                    states[offset] = .done
                    continue mangaLoop
                }
            }
            // didn't find a manga in any of the sources
            states[offset] = .failed
        }
        withAnimation {
            migrationState = .done
        }
    }

    func performMigration() async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            var migrations: [(from: Manga, to: Manga)] = []
            for (offset, oldManga) in manga.enumerated() {
                guard let newManga = migratedManga[offset] else { continue }
                let newChapters = newChapters[offset]

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
