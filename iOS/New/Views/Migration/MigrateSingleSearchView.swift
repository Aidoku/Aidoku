//
//  MigrateSingleSearchView.swift
//  Aidoku
//
//  Created by skitty on 5/16/26.
//

import AidokuRunner
import SwiftUI

struct MigrateSingleSearchView: View {
    let targetSources: [AidokuRunner.Source]
    let selectedSeries: AidokuRunner.Manga

    var resultSeries: Binding<AidokuRunner.Manga?>?

    struct SearchResult: Identifiable, Equatable {
        let source: AidokuRunner.Source
        let result: AidokuRunner.MangaPageResult

        var id: String { source.id }

        static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
            lhs.id == rhs.id
        }
    }

    @State private var query: String
    @State private var results: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var targetSeries: AidokuRunner.Manga?
    @State private var isMigrating = false
    @State private var isLoading = false
    @State private var didFirstLoad = false
    @State private var showMigrateAlert = false

    @EnvironmentObject private var path: NavigationCoordinator

    @Environment(\.dismiss) private var dismiss

    init(
        targetSources: [AidokuRunner.Source],
        selectedSeries: AidokuRunner.Manga,
        resultSeries: Binding<AidokuRunner.Manga?>? = nil
    ) {
        self.targetSources = targetSources
        self.selectedSeries = selectedSeries
        self.resultSeries = resultSeries
        self._query = State(initialValue: selectedSeries.title)
    }

    var body: some View {
        List {
            ForEach(results) { searchResult in
                let source = searchResult.source
                let result = searchResult.result
                let id = {
                    var hasher = Hasher()
                    for entry in result.entries {
                        hasher.combine(entry)
                    }
                    return hasher.finalize()
                }()
                if !result.entries.isEmpty {
                    Section {
                        HomeScrollerView(
                            source: source,
                            component: .init(
                                title: nil,
                                value: .scroller(entries: result.entries.map { $0.intoLink() })
                            ),
                            pressAction: { manga in
                                if let resultSeries {
                                    resultSeries.wrappedValue = manga
                                    dismiss()
                                } else {
                                    targetSeries = manga
                                    showMigrateAlert = true
                                }
                            }
                        )
                        .id("\(source.key).\(id)")
                        .listRowBackground(Color.clear)
                        .listRowInsets(.zero)
                        .listRowSeparator(.hidden)
                    } header: {
                        HStack {
                            SourceIconView(
                                sourceId: source.key,
                                imageUrl: source.imageUrl,
                                iconSize: 29
                            )
                            .scaleEffect(0.75)
                            Text(source.name)

                            Spacer()

                            // todo
//                            Button(NSLocalizedString("VIEW_MORE")) {}
                        }
                        .font(.body)
                        .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.grouped)
        .environment(\.defaultMinListRowHeight, 10)
        .customSearchable(
            text: $query,
            hideCancelButton: true,
            hidesNavigationBarDuringPresentation: false,
            hidesSearchBarWhenScrolling: false,
            onSubmit: {
                if query.isEmpty {
                    results = []
                } else {
                    search()
                }
            }
        )
        .navigationBarBackButtonHidden(isMigrating)
        .alert(NSLocalizedString("MIGRATE_ONE_ITEM?"), isPresented: $showMigrateAlert) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {
                targetSeries = nil
            }
            Button(NSLocalizedString("COPY")) {
                migrate(copy: true)
            }
            Button(NSLocalizedString("MIGRATE")) {
                migrate(copy: false)
            }
            Button(NSLocalizedString("SHOW_ENTRY")) {
                guard let targetSeries else { return }
                path.push(MangaViewController(manga: targetSeries, parent: path.rootViewController))
            }
        }
        .onAppear {
            guard !didFirstLoad else { return }
            didFirstLoad = true
            search()
        }
    }
}

extension MigrateSingleSearchView {
    func migrate(copy: Bool) {
        guard
            let targetSeries,
            let appDelegate = UIApplication.shared.delegate as? AppDelegate
        else {
            return
        }
        isMigrating = true
        appDelegate.showLoadingIndicator {
            Task {
                await MangaManager.shared.migrate(
                    copy: copy,
                    fromSeries: [selectedSeries],
                    toSeries: [selectedSeries.identifier: targetSeries]
                )

                NotificationCenter.default.post(name: .updateLibrary, object: nil)
                NotificationCenter.default.post(name: .updateHistory, object: nil)

                await appDelegate.hideLoadingIndicator()

                path.dismiss()
            }
        }
    }
}

extension MigrateSingleSearchView {
    func search(delay: Bool = false) {
        searchTask?.cancel()
        searchTask = Task {
            if delay {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else {
                return
            }

            withAnimation {
                results = []
                isLoading = true
            }
            let searchText: String
            if query.isEmpty {
                searchText = selectedSeries.title
            } else {
                searchText = query
            }
            await withTaskGroup(of: (AidokuRunner.Source, AidokuRunner.MangaPageResult?).self) { group in
                for source in targetSources {
                    group.addTask {
                        let result = try? await source.getSearchMangaList(query: searchText, page: 1, filters: [])
                        return (source, result)
                    }
                }
                for await (source, result) in group {
                    guard let result else { continue }
                    withAnimation {
                        results.append(.init(source: source, result: result))
                    }
                }
            }
            guard !Task.isCancelled else {
                return
            }
            withAnimation {
                isLoading = false
            }
        }
    }
}
