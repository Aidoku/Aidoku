//
//  DictionaryListView.swift
//  Aidoku (iOS)
//
//  Created by GameFuzzy on 7/11/26.
//

import CHoshiDicts
import SafariServices
import SwiftUI
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct DictionaryListView: View {
    @State private var dictionaryManager = DictionaryManager.shared

    @State private var selectedDictionaryInfo: DictionaryInfo?
    @State private var importing = false
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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

            let items = [
                (DictionaryType.term, dictionaryManager.termDictionaries, NSLocalizedString("TERM_DICTIONARIES")),
                (DictionaryType.frequency, dictionaryManager.frequencyDictionaries, NSLocalizedString("FREQUENCY_DICTIONARIES")),
                (DictionaryType.pitch, dictionaryManager.pitchDictionaries, NSLocalizedString("PITCH_DICTIONARIES"))
            ]
            ForEach(items, id: \.0) { type, dictionaries, title in
                if !dictionaries.isEmpty {
                    Section(title) {
                        ForEach(dictionaries) { dict in
                            dictRow(dict, type: type)
                        }
                        .onDelete { offsets in delete(offsets: offsets, type: type) }
                        .onMove { from, to in move(from: from, to: to, type: type) }
                    }
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
            if dictionaryManager.isImporting {
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
        .alert(NSLocalizedString("IMPORT_ERROR"), isPresented: $dictionaryManager.shouldShowError) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(verbatim: dictionaryManager.errorMessage)
        }
        .sheet(item: $selectedDictionaryInfo) { dict in
            DictionaryInfoView(info: dict)
        }
    }

    func dictRow(_ dict: DictionaryInfo, type: DictionaryType) -> some View {
        Toggle(isOn: Binding(
            get: { dict.isEnabled },
            set: { newValue in
                dictionaryManager.toggleDictionary(id: dict.id, enabled: newValue, type: type)
                notifyDictionariesChanged()
            }
        )) {
            HStack {
                Text(dict.index.title)
                Spacer()
                Button {
                    selectedDictionaryInfo = dict
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    func delete(offsets: IndexSet, type: DictionaryType) {
        dictionaryManager.deleteDictionary(indexSet: offsets, type: type)
        notifyDictionariesChanged()
    }

    func move(from source: IndexSet, to destination: Int, type: DictionaryType) {
        dictionaryManager.moveDictionary(from: source, to: destination, type: type)
        notifyDictionariesChanged()
    }

    private func notifyDictionariesChanged() {
        NotificationCenter.default.post(name: .dictionaryDictionariesChanged, object: nil)
    }

    func importDictionaries(urls: [URL]) {
        Task {
            await dictionaryManager.importDictionary(from: urls)
        }
    }
}

@available(iOS 18.0, *)
private struct DictionaryInfoView: View {
    let info: DictionaryInfo

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(NSLocalizedString("REVISION"))
                        Spacer()
                        Text(info.index.revision).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(info.index.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
