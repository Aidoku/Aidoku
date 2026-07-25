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

private struct SelectedDictionary: Identifiable {
    let info: DictionaryInfo
    let index: IndexSet
    let type: DictionaryType

    var id: UUID { info.id }
}

@available(iOS 18.0, *)
struct DictionaryListView: View {
    @State private var dictionaryManager = DictionaryManager.shared

    @State private var selectedDictionaryInfo: SelectedDictionary?
    @State private var importing = false
    @State private var showSafari = false
    @State private var showGetDictionaries = false

    @StateObject private var dismissedInfo = UserDefaultsBool(key: "Flag.dismissedDictionaryInfo")

    var body: some View {
        List {
            if !dismissedInfo.value {
                aboutSection
            }

            Section {
                Button(NSLocalizedString("GET_RECOMMENDED_DICTIONARIES")) {
                    showGetDictionaries = true
                }
            }

            if !dictionaryManager.updatableDictionaries.isEmpty {
                Section {
                    SettingView(setting: .init(
                        key: AppSettings.dictionary.updateInterval.key,
                        title: NSLocalizedString("UPDATE_INTERVAL"),
                        value: .select(.init(
                            values: DictionarySettings.UpdateInterval.allCases.map { $0.rawValue },
                            titles: DictionarySettings.UpdateInterval.allCases.map { $0.title }
                        )),
                    ))
                    Button(NSLocalizedString("UPDATE_NOW")) {
                        DictionaryManager.shared.updateDictionaries()
                    }
                } header: {
                    Text(NSLocalizedString("DICTIONARY_UPDATES"))
                } footer: {
                    let progressView = ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                        .padding(.vertical, -2)

                    let date = AppSettings.dictionary.lastUpdate.get()
                    if date > Date.distantPast {
                        HStack(spacing: 4) {
                            Text(String(format: NSLocalizedString("LAST_UPDATED_%@"), date.formatted(.relative(presentation: .named))))
                            if dictionaryManager.isUpdating {
                                progressView
                            }
                        }
                    } else if dictionaryManager.isUpdating {
                        progressView
                    }
                }
            }

            let items = [
                (DictionaryType.term, dictionaryManager.termDictionaries, NSLocalizedString("TERM_DICTIONARIES")),
                (DictionaryType.frequency, dictionaryManager.frequencyDictionaries, NSLocalizedString("FREQUENCY_DICTIONARIES")),
                (DictionaryType.pitch, dictionaryManager.pitchDictionaries, NSLocalizedString("PITCH_DICTIONARIES"))
            ]
            ForEach(items, id: \.0) { type, dictionaries, title in
                if !dictionaries.isEmpty {
                    Section(title) {
                        ForEach(Array(dictionaries.enumerated()), id: \.element.id) { offset, dict in
                            dictRow(dict, index: .init(integer: offset), type: type)
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
                .disabled(dictionaryManager.isImporting || dictionaryManager.isUpdating)
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
            DictionaryInfoView(dictionary: dict)
        }
        .sheet(isPresented: $showGetDictionaries) {
            DictionaryRecommendedListView()
        }
    }

    var aboutSection: some View {
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

    func dictRow(_ dict: DictionaryInfo, index: IndexSet, type: DictionaryType) -> some View {
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
                    selectedDictionaryInfo = .init(info: dict, index: index, type: type)
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
    let dictionary: SelectedDictionary

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(NSLocalizedString("REVISION"))
                        Spacer()
                        Text(dictionary.info.index.revision).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(NSLocalizedString("REMOVE_DICTIONARY"), role: .destructive) {
                        DictionaryManager.shared.deleteDictionary(indexSet: dictionary.index, type: dictionary.type)
                        NotificationCenter.default.post(name: .dictionaryDictionariesChanged, object: nil)
                        dismiss()
                    }
                }
            }
            .navigationTitle(dictionary.info.index.title)
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

@available(iOS 18.0, *)
private struct DictionaryRecommendedListView: View {
    struct ExternalDictionary: Identifiable {
        var id: String { name }
        let name: String
        let description: String
        let indexUrl: String
        let homepageUrl: String
    }
    private let recommendedDictionaries: [(DictionaryType, [ExternalDictionary])] = [
        (.term, [
            .init(
                name: "JMdict",
                description: "A comprehensive Japanese–English dictionary maintained by the Electronic Dictionary Research and Development Group.",
                indexUrl: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english_without_proper_names.json",
                homepageUrl: "https://github.com/yomidevs/jmdict-yomitan?tab=readme-ov-file#jmdict-for-yomitan"
            ),
            .init(
                name: "JMnedict",
                description: "A dictionary of Japanese proper names maintained by the Electronic Dictionary Research and Development Group.",
                indexUrl: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMnedict.json",
                homepageUrl: "https://github.com/yomidevs/jmdict-yomitan?tab=readme-ov-file#jmnedict-for-yomitan"
            )
        ]),
        (.frequency, [
            .init(
                name: "Jiten",
                description: "A frequency dictionary based on the corpus from the media stats database at https://jiten.moe.",
                indexUrl: "https://api.jiten.moe/api/frequency-list/index",
                homepageUrl: "https://jiten.moe/other"
            )
        ])
    ]

    @State private var dictionaryManager = DictionaryManager.shared
    @State private var safariUrl: URL?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let string = {
                        let note = NSLocalizedString("RECOMMENDED_DICTIONARIES_NOTE")
                        let learnMore = NSLocalizedString("LEARN_MORE")
                        var string = AttributedString(note + " " + learnMore)
                        if let range = string.range(of: learnMore) {
                            string[range].link = URL(string: "https://yomidevs.github.io/wiktionary-to-yomitan/download/")
                        }
                        return string
                    }()
                    Text(string)
                        .environment(
                            \.openURL,
                            OpenURLAction { url in
                                safariUrl = url
                                return .handled
                            }
                        )
                }
                ForEach(recommendedDictionaries, id: \.0) { type, dictionaries in
                    Section(type.sectionTitle) {
                        ForEach(dictionaries) { dictionary in
                            cell(for: dictionary, type: type)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("RECOMMENDED_DICTIONARIES"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: .init(get: { safariUrl != nil }, set: { _ in })) {
                SafariView(url: $safariUrl)
            }
        }
        .presentationDetents([.medium])
    }

    func cell(for dictionary: ExternalDictionary, type: DictionaryType) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(dictionary.name)
                    .foregroundStyle(.primary)
                Text(dictionary.description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                safariUrl = URL(string: dictionary.homepageUrl)
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)

            let targetDictionaries = switch type {
                case .term: dictionaryManager.termDictionaries
                case .frequency: dictionaryManager.frequencyDictionaries
                case .pitch: dictionaryManager.pitchDictionaries
            }
            let installed = targetDictionaries.contains(where: { $0.index.indexUrl == dictionary.indexUrl })
            GetButton {
                await dictionaryManager.downloadDictionary(indexUrl: dictionary.indexUrl, type: type)
            }
            .disabled(installed || dictionaryManager.isImporting || dictionaryManager.isUpdating)
        }
    }
}

private extension DictionaryType {
    var sectionTitle: String {
        switch self {
            case .term: NSLocalizedString("TERM_DICTIONARIES")
            case .frequency: NSLocalizedString("FREQUENCY_DICTIONARIES")
            case .pitch: NSLocalizedString("PITCH_DICTIONARIES")
        }
    }
}
