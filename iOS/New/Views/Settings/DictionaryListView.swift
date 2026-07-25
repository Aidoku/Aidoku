//
//  DictionaryListView.swift
//  Aidoku (iOS)
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct DictionaryListView: View {
    @State private var termDicts: [DictionaryInfo] = []
    @State private var freqDicts: [DictionaryInfo] = []
    @State private var pitchDicts: [DictionaryInfo] = []

    @State private var importing = false
    @State private var importType: DictionaryType = .term
    @State private var isImporting = false

    var body: some View {
        List {
            Section {
                ForEach(termDicts) { dict in
                    dictRow(dict, type: .term)
                }
                .onDelete { offsets in delete(offsets: offsets, type: .term) }
                .onMove { from, to in move(from: from, to: to, type: .term) }
            } header: {
                Text(NSLocalizedString("TERM_DICTIONARIES"))
            }

            Section {
                ForEach(freqDicts) { dict in
                    dictRow(dict, type: .frequency)
                }
                .onDelete { offsets in delete(offsets: offsets, type: .frequency) }
                .onMove { from, to in move(from: from, to: to, type: .frequency) }
            } header: {
                Text(NSLocalizedString("FREQUENCY_DICTIONARIES"))
            }

            Section {
                ForEach(pitchDicts) { dict in
                    dictRow(dict, type: .pitch)
                }
                .onDelete { offsets in delete(offsets: offsets, type: .pitch) }
                .onMove { from, to in move(from: from, to: to, type: .pitch) }
            } header: {
                Text(NSLocalizedString("PITCH_DICTIONARIES"))
            }
        }
        .navigationTitle(NSLocalizedString("DICTIONARIES"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        importType = .term
                        importing = true
                    } label: {
                        Label(NSLocalizedString("IMPORT_TERM_DICTIONARY"), systemImage: "text.book.closed")
                    }
                    Button {
                        importType = .frequency
                        importing = true
                    } label: {
                        Label(NSLocalizedString("IMPORT_FREQUENCY_DICTIONARY"), systemImage: "number")
                    }
                    Button {
                        importType = .pitch
                        importing = true
                    } label: {
                        Label(NSLocalizedString("IMPORT_PITCH_DICTIONARY"), systemImage: "waveform")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .overlay {
            if isImporting {
                ProgressView(NSLocalizedString("IMPORTING_DICTIONARY"))
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: $importing) {
            DocumentPickerView(
                allowedContentTypes: [UTType.zip],
                allowsMultipleSelection: true
            ) { urls in
                importing = false
                guard !urls.isEmpty else { return }
                importDictionaries(urls: urls, type: importType)
            }
        }
        .onAppear {
            reload()
        }
    }

    func dictRow(_ dict: DictionaryInfo, type: DictionaryType) -> some View {
        HStack {
            Toggle(dict.name, isOn: Binding(
                get: { dict.isEnabled },
                set: { newValue in
                    DictionaryManager.shared.toggleDictionary(id: dict.id, enabled: newValue, type: type)
                    reload()
                }
            ))
        }
    }

    func reload() {
        let manager = DictionaryManager.shared
        termDicts = manager.termDictionaries
        freqDicts = manager.frequencyDictionaries
        pitchDicts = manager.pitchDictionaries
    }

    func delete(offsets: IndexSet, type: DictionaryType) {
        DictionaryManager.shared.deleteDictionary(indexSet: offsets, type: type)
        reload()
    }

    func move(from source: IndexSet, to destination: Int, type: DictionaryType) {
        switch type {
        case .term:
            termDicts.move(fromOffsets: source, toOffset: destination)
            for (i, _) in termDicts.enumerated() {
                termDicts[i].order = i
            }
            DictionaryManager.shared.termDictionaries = termDicts
        case .frequency:
            freqDicts.move(fromOffsets: source, toOffset: destination)
            for (i, _) in freqDicts.enumerated() {
                freqDicts[i].order = i
            }
            DictionaryManager.shared.frequencyDictionaries = freqDicts
        case .pitch:
            pitchDicts.move(fromOffsets: source, toOffset: destination)
            for (i, _) in pitchDicts.enumerated() {
                pitchDicts[i].order = i
            }
            DictionaryManager.shared.pitchDictionaries = pitchDicts
        }
        DictionaryManager.shared.saveDictionaryConfig()
        DictionaryManager.shared.rebuildLookupQuery()
    }

    func importDictionaries(urls: [URL], type: DictionaryType) {
        isImporting = true
        Task {
            let result = await DictionaryManager.shared.importDictionary(from: urls, type: type)
            await MainActor.run {
                isImporting = false
                if result.didImportAny {
                    reload()
                }
            }
        }
    }
}
