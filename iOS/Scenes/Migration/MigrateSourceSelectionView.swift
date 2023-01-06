//
//  MigrateSourceSelectionView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/5/23.
//

import SwiftUI

struct MigrateSourceSelectionView: View {

    var excludedSources: [String] = []

    @Binding var selectedSources: [SourceInfo2]
    @State var availableSources = SourceManager.shared.sources.map { $0.toInfo() }

    @State private var editMode: EditMode = .active

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("SELECTED", comment: ""))) {
                ForEach(selectedSources, id: \.sourceId) { source in
                    Text(source.name)
                }
                .onMove(perform: relocate)
                .onDelete(perform: delete)
            }
            Section(header: Text(NSLocalizedString("AVAILABLE", comment: ""))) {
                ForEach(availableSources, id: \.sourceId) { source in
                    Button(source.name) {
                        select(source: source)
                    }
                    .disabled(
                        selectedSources.contains(source) || excludedSources.contains(source.sourceId)
                    )
                    .ios14ButtonFix()
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
    }

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

// fixes buttons not being selectable in lists on ios 14
// if BorderlessButtonStyle is enabled on ios 15+, only the text becomes selectable and not the entire cell (smh apple)
fileprivate extension View {
    @ViewBuilder
    func ios14ButtonFix() -> some View {
        if #available(iOS 15.0, *) {
            self
        } else {
            self.buttonStyle(BorderlessButtonStyle())
        }
    }
}
