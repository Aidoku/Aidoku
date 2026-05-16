//
//  MigrateResultsView.swift
//  Aidoku
//
//  Created by skitty on 5/9/26.
//

import AidokuRunner
import SwiftUI

struct MigrateResultsView: View {
    let targetSources: [AidokuRunner.Source]
    @State private var selectedSeries: [AidokuRunner.Manga]

    private let sourceNames: [String: String]

    enum MigrationState {
        case idle
        case running
        case failed
        case done
    }

    @State private var didFirstLoad = false
    @State private var isLoading = true
    @State private var showingConfirmAlert = false
    @State private var migratedManga: [MangaIdentifier: AidokuRunner.Manga?] = [:]
    @State private var newChapters: [MangaIdentifier: [AidokuRunner.Chapter]] = [:]
    @State private var states: [MangaIdentifier: MigrationState] = [:]

    @EnvironmentObject private var path: NavigationCoordinator

    @Environment(\.dismiss) private var dismiss

    init(targetSources: [AidokuRunner.Source], selectedSeries: [AidokuRunner.Manga]) {
        self.targetSources = targetSources
        self._selectedSeries = State(initialValue: selectedSeries)

        var sourceNames: [String: String] = [:]
        for source in SourceManager.shared.sources {
            sourceNames[source.key] = source.name
        }
        self.sourceNames = sourceNames
    }

    var body: some View {
        List {
            ForEach(selectedSeries, id: \.identifier) { series in
                let result = self.migratedMangaBinding(for: series.identifier)
                MangaToMangaView(
                    fromSource: sourceNames[series.sourceKey] ?? series.sourceKey,
                    toSource: result.wrappedValue.flatMap { sourceNames[$0.sourceKey] },
                    fromManga: series,
                    toManga: result,
                    state: states[series.identifier, default: .idle],
                    targetSources: targetSources,
                    remove: {
                        remove(manga: series)
                    }
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle(String(format: NSLocalizedString("MIGRATE_%i_OF_%i"), migratedManga.count, selectedSeries.count))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isLoading {
                    ProgressView()
                } else {
                    Menu(NSLocalizedString("CONTINUE")) {
                        Button(NSLocalizedString("COPY")) {
                            startMigration(copy: true)
                        }
                        Button(NSLocalizedString("MIGRATE")) {
                            showingConfirmAlert = true
                        }
                    }
                }
            }
        }
        .alert(
            {
                let itemCount = migratedManga.filter({ item in
                    item.value != nil && selectedSeries.contains(where: { manga in manga.identifier == item.key })
                }).count
                return itemCount == 1
                    ? NSLocalizedString("MIGRATE_ONE_ITEM?")
                    : String(format: NSLocalizedString("MIGRATE_%i_ITEMS?"), itemCount)
            }(),
            isPresented: $showingConfirmAlert
        ) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("CONTINUE")) {
                startMigration(copy: false)
            }
        } message: {
            Text(NSLocalizedString("MIGRATE_CONFIRM_TEXT"))
        }
        .onAppear {
            guard !didFirstLoad else { return }
            didFirstLoad = true
            Task {
                await startMatching()
            }
        }
    }
}

extension MigrateResultsView {
    func remove(manga: AidokuRunner.Manga) {
        selectedSeries.removeAll { $0.key == manga.key }
        let key = manga.identifier
        newChapters.removeValue(forKey: key)
        migratedManga.removeValue(forKey: key)
        states.removeValue(forKey: key)
    }

    func migratedMangaBinding(for key: MangaIdentifier) -> Binding<AidokuRunner.Manga?> {
        .init(
            get: { self.migratedManga[key, default: nil] },
            set: {
                self.migratedManga[key] = $0
                self.newChapters.removeValue(forKey: key)
            }
        )
    }
}

extension MigrateResultsView {
    func startMatching() async {
        selectedSeries.forEach {
            states[$0.identifier] = .running
        }

        await withTaskGroup(of: (MangaIdentifier, AidokuRunner.Manga?).self) { group in
            for manga in selectedSeries {
                group.addTask {
                    // check sources until a manga is found
                    for source in targetSources {
                        let search = try? await source.getSearchMangaList(query: manga.title, page: 1, filters: [])
                        if let newManga = search?.entries.first {
                            return (manga.identifier, newManga)
                        }
                    }
                    // didn't find a manga in any of the sources
                    return (manga.identifier, nil)
                }
            }

            for await (key, result) in group {
                await MainActor.run {
                    if let result {
                        withAnimation {
                            migratedManga[key] = result
                            states[key] = .done
                        }
                    } else {
                        states[key] = .failed
                    }
                }
            }
        }

        withAnimation {
            isLoading = false
        }
    }

    func startMigration(copy: Bool) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.showLoadingIndicator(style: .progress) {
            Task {
                UIApplication.shared.isIdleTimerDisabled = true

                await MangaManager.shared.migrate(
                    copy: copy,
                    fromSeries: selectedSeries,
                    toSeries: migratedManga,
                    withChapters: newChapters,
                    progressReport: { progress in
                        Task { @MainActor in
                            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                                appDelegate.indicatorProgress = progress
                            }
                        }
                    }
                )

                NotificationCenter.default.post(name: .updateLibrary, object: nil)
                NotificationCenter.default.post(name: .updateHistory, object: nil)

                UIApplication.shared.isIdleTimerDisabled = false

                await appDelegate.hideLoadingIndicator()

                path.dismiss()
            }
        }
    }

}

extension MigrateResultsView {
    struct MangaToMangaView: View {
        let fromSource: String?
        let toSource: String?
        let fromManga: AidokuRunner.Manga
        @Binding var toManga: AidokuRunner.Manga?
        let state: MigrationState
        let targetSources: [AidokuRunner.Source]
        let remove: () -> Void

        private let maxCoverHeight: CGFloat = 240

        @EnvironmentObject private var path: NavigationCoordinator

        var body: some View {
            HStack {
                VStack(alignment: .leading) {
                    Button {
                        path.push(MangaViewController(manga: fromManga, parent: path.rootViewController))
                    } label: {
                        MangaGridItem(
                            title: fromManga.title,
                            coverImage: fromManga.cover ?? ""
                        )
                        .aspectRatio(2/3, contentMode: .fit)
                        .frame(maxHeight: maxCoverHeight) // restrict size on ipads
                    }
                    .buttonStyle(.borderless)

                    Text(fromSource ?? NSLocalizedString("UNKNOWN"))
                        .font(.footnote)
                }

                Image(systemName: "arrow.right")

                VStack(alignment: .leading) {
                    if let toManga {
                        Button {
                            path.push(MangaViewController(manga: toManga, parent: path.rootViewController))
                        } label: {
                            MangaGridItem(
                                title: toManga.title,
                                coverImage: toManga.cover ?? ""
                            )
                            .aspectRatio(2/3, contentMode: .fit)
                            .frame(maxHeight: maxCoverHeight)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        MangaGridItem.placeholder
                            .aspectRatio(2/3, contentMode: .fit)
                            .frame(maxHeight: maxCoverHeight)
                            .overlay {
                                if state == .running {
                                    ProgressView()
                                }
                            }
                    }

                    let subtext = if state == .failed {
                        NSLocalizedString("NOT_FOUND")
                    } else if let toSource {
                        toSource
                    } else {
                        " "
                    }
                    Text(subtext)
                        .font(.footnote)
                }

                Spacer()

                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis")
                }
                .foregroundStyle(.primary)
                .padding(.leading, 12)
            }
            .padding(.vertical, 2)
            .contextMenu {
                menuContent
            }
        }

        @ViewBuilder
        var menuContent: some View {
            Button {
                path.push(MigrateSingleSearchView(
                    targetSources: targetSources,
                    selectedSeries: fromManga,
                    resultSeries: $toManga
                ))
            } label: {
                Label(NSLocalizedString("SEARCH_MANUALLY"), systemImage: "magnifyingglass")
            }
            Button(role: .destructive) {
                remove()
            } label: {
                Label(NSLocalizedString("DONT_MIGRATE"), systemImage: "trash")
            }
        }
    }
}
