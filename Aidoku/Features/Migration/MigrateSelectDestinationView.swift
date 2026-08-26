//
//  MigrateSelectDestinationView.swift
//  Aidoku
//
//  Created by skitty on 1/5/23.
//

import AidokuRunner
import SwiftUI

struct MigrateSelectDestinationView: View {
    let selectedSeries: [AidokuRunner.Manga]

    @State private var availableSources: [SourceInfo] = []
    @State private var pinnedSources: [SourceInfo] = []
    @State private var selectedSources: [SourceInfo]
    @State private var editMode: EditMode = .active

    @EnvironmentObject private var path: NavigationCoordinator

    init(selectedSeries: [AidokuRunner.Manga], selectedSources: [SourceInfo] = []) {
        self.selectedSeries = selectedSeries
        self._selectedSources = State(initialValue: selectedSources)
    }

    var body: some View {
        List {
            if !pinnedSources.isEmpty {
                let canSelectPinnedSources = pinnedSources.contains(where: { !selectedSources.contains($0) })
                Button {
                    for pinnedSource in pinnedSources where !selectedSources.contains(pinnedSource) {
                        select(source: pinnedSource)
                    }
                } label: {
                    Text(NSLocalizedString("SELECT_PINNED_SOURCES"))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .disabled(!canSelectPinnedSources)
            }

            if !selectedSources.isEmpty {
                Section(header: Text(NSLocalizedString("SELECTED"))) {
                    ForEach(selectedSources, id: \.sourceId) { source in
                        Text(source.name)
                    }
                    .onMove(perform: relocate)
                    .onDelete(perform: delete)
                }
            }
            Section(header: Text(NSLocalizedString("AVAILABLE"))) {
                ForEach(availableSources, id: \.sourceId) { source in
                    Button {
                        select(source: source)
                    } label: {
                        SourceCell(source: source)
                    }
                    .disabled(selectedSources.contains(source))
                    .cellButtonFix()
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .navigationTitle(NSLocalizedString("DESTINATION"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("CONTINUE")) {
                    Task {
                        let allSources = await SourceManager.shared.getLoadedSources()
                        var sources: [AidokuRunner.Source] = []
                        for source in allSources where selectedSources.contains(where: { $0.sourceId == source.key }) {
                            sources.append(source)
                        }
                        if selectedSeries.count == 1 {
                            path.push(MigrateSingleSearchView(
                                targetSources: sources,
                                selectedSeries: selectedSeries[0])
                            )
                        } else {
                            path.push(MigrateResultsView(
                                targetSources: sources,
                                selectedSeries: selectedSeries
                            ))
                        }
                    }
                }
                .disabled(selectedSources.isEmpty)
            }
        }
        .task {
            guard availableSources.isEmpty && pinnedSources.isEmpty else { return }
            await loadSources()
        }
    }
}

extension MigrateSelectDestinationView {
    func loadSources() async {
        availableSources = await SourceManager.shared.getSourceInfos(includeDisabled: false)
        pinnedSources = await SourceManager.shared.getPinned().map { $0.toInfo() }
    }
}

extension MigrateSelectDestinationView {
    func select(source: SourceInfo) {
        selectedSources.append(source)
    }

    func relocate(from source: IndexSet, to destination: Int) {
        selectedSources.move(fromOffsets: source, toOffset: destination)
    }

    func delete(at indexSet: IndexSet) {
        for index in indexSet {
            selectedSources.remove(at: index)
        }
    }
}

extension MigrateSelectDestinationView {
    struct SourceCell: View {
        let source: SourceInfo

        var body: some View {
            HStack(spacing: 12) {
                SourceIconView(
                    sourceId: source.sourceId,
                    imageUrl: source.iconUrl,
                    iconSize: 32
                )
                Text(source.name)
                Spacer(minLength: 0) // for ios 15
            }
        }
    }
}

// fixes buttons not being selectable in lists pre-ios 16
// if BorderlessButtonStyle is enabled on ios 16+, only the text becomes selectable and not the entire cell (smh apple)
private extension View {
    @ViewBuilder
    func cellButtonFix() -> some View {
        if #available(iOS 16.0, *) {
            self
        } else {
            self
                .contentShape(Rectangle()) // to make the entire cell selectable and not just the text
                .buttonStyle(.borderless)
        }
    }
}
