//
//  DictionaryListView.swift
//  Aidoku (iOS)
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SafariServices
import SwiftUI
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct DictionaryListView: View {
    @State private var termDicts: [DictionaryInfo] = []
    @State private var freqDicts: [DictionaryInfo] = []
    @State private var pitchDicts: [DictionaryInfo] = []

    @State private var importing = false
    @State private var isImporting = false
    @State private var showSafari = false

    @StateObject private var dismissedInfo = UserDefaultsBool(key: "Flag.dismissedDictionaryInfo")

    var body: some View {
        List {
            if !dismissedInfo.value {
                ZStack(alignment: .topTrailing) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "character.book.closed")
                            .font(.title)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("ABOUT_DICTIONARIES"))
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text(NSLocalizedString("ABOUT_DICTIONARIES_TEXT"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                            Button {
                                showSafari = true
                            } label: {
                                Text(NSLocalizedString("LEARN_MORE"))
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 11)
                                    .background(Capsule().fill(.tint.opacity(0.1)))
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 4)
                        }
                    }
                    Button {
                        withAnimation {
                            dismissedInfo.value = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14).weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Circle().fill(Color(uiColor: .tertiarySystemFill)))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                    .offset(x: 8, y: -8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            if !termDicts.isEmpty {
                Section {
                    ForEach(termDicts) { dict in
                        dictRow(dict, type: .term)
                    }
                    .onDelete { offsets in delete(offsets: offsets, type: .term) }
                    .onMove { from, to in move(from: from, to: to, type: .term) }
                } header: {
                    Text(NSLocalizedString("TERM_DICTIONARIES"))
                }
            }
            if !freqDicts.isEmpty {
                Section {
                    ForEach(freqDicts) { dict in
                        dictRow(dict, type: .frequency)
                    }
                    .onDelete { offsets in delete(offsets: offsets, type: .frequency) }
                    .onMove { from, to in move(from: from, to: to, type: .frequency) }
                } header: {
                    Text(NSLocalizedString("FREQUENCY_DICTIONARIES"))
                }
            }
            if !pitchDicts.isEmpty {
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
        }
        .navigationTitle(NSLocalizedString("DICTIONARIES"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importing = true
                } label: {
                    Image(systemName: "plus")
                }
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
                importDictionaries(urls: urls)
            }
        }
        .sheet(isPresented: $showSafari) {
            SafariView(url: .constant(URL(string: "https://yomitan.wiki/dictionaries/")))
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
                    notifyDictionariesChanged()
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
        notifyDictionariesChanged()
        reload()
    }

    func move(from source: IndexSet, to destination: Int, type: DictionaryType) {
        switch type {
            case .term:
                termDicts.move(fromOffsets: source, toOffset: destination)
                for i in termDicts.indices {
                    termDicts[i].order = i
                }
                DictionaryManager.shared.termDictionaries = termDicts
            case .frequency:
                freqDicts.move(fromOffsets: source, toOffset: destination)
                for i in freqDicts.indices {
                    freqDicts[i].order = i
                }
                DictionaryManager.shared.frequencyDictionaries = freqDicts
            case .pitch:
                pitchDicts.move(fromOffsets: source, toOffset: destination)
                for i in pitchDicts.indices {
                    pitchDicts[i].order = i
                }
                DictionaryManager.shared.pitchDictionaries = pitchDicts
        }
        DictionaryManager.shared.saveDictionaryConfig()
        DictionaryManager.shared.rebuildLookupQuery()
        notifyDictionariesChanged()
    }

    private func notifyDictionariesChanged() {
        UserDefaults.standard.syncReaderLookupGestureCompatibilityLocks()
        NotificationCenter.default.post(name: .dictionaryDictionariesChanged, object: nil)
    }

    func importDictionaries(urls: [URL]) {
        isImporting = true
        Task {
            let result = await DictionaryManager.shared.importDictionary(from: urls)
            await MainActor.run {
                isImporting = false
                if result.didImportAny {
                    notifyDictionariesChanged()
                    reload()
                }
                if !result.failed.isEmpty {
                    LogManager.logger.error("Failed to import dictionaries: \(result.failed.joined(separator: ", "))")
                }
            }
        }
    }
}
