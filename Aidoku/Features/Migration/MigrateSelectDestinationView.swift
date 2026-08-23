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

    private let availableSources = SourceManager.shared.sources.map { $0.toInfo() }
    private let pinnedSources = SourceManager.shared.getPinned().map { $0.toInfo() }

    @State private var selectedSources: [SourceInfo2]
    @State private var editMode: EditMode = .active

    @EnvironmentObject private var path: NavigationCoordinator

    init(selectedSeries: [AidokuRunner.Manga], selectedSources: [SourceInfo2] = []) {
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
                    let sources = selectedSources.compactMap { SourceManager.shared.source(for: $0.sourceId) }
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
                .disabled(selectedSources.isEmpty)
            }
        }
    }
}

extension MigrateSelectDestinationView {
    func select(source: SourceInfo2) {
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
        let source: SourceInfo2

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
        } else if #available(iOS 15.0, *) {
            self
                .contentShape(Rectangle()) // to make the entire cell selectable and not just the text
                .buttonStyle(.borderless)
        } else {
            self.buttonStyle(.borderless)
        }
    }
}
