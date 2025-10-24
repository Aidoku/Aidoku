//
//  AddSourceFilterView.swift
//  Aidoku
//
//  Created by Skitty on 10/24/25.
//

import AidokuRunner
import SwiftUI

struct AddSourceFilterView: View {
    private struct LanguageItem: Hashable, Identifiable {
        let id: String
        let title: String
    }

    private let languages: [LanguageItem]

    @State private var contentRatings: [String]
    @State private var selectedLanguages: [String]

    @Environment(\.dismiss) private var dismiss

    init() {
        var languageCodes = Array(SourceManager.shared.sourceListLanguages)

        // sort alphabetically
        languageCodes.sort(by: {
            let lhs = Locale.current.localizedString(forIdentifier: $0)
            let rhs = Locale.current.localizedString(forIdentifier: $1)
            return lhs ?? $0 < rhs ?? $1
        })

        // bring local language to top
        languageCodes.removeAll { $0 == Locale.current.languageCode || $0 == "multi" || $0 == "All" }
        if let code = Locale.current.languageCode {
            languageCodes.insert(code, at: 0)
        }

        self.languages = [
            .init(id: "multi", title: NSLocalizedString("MULTI_LANGUAGE"))
        ] + languageCodes.map { code in
            .init(
                id: code,
                title: Locale.current.localizedString(forIdentifier: code) ?? code
            )
        }
        self._contentRatings = State(initialValue: SettingsStore.shared.get(key: "Browse.contentRatings"))
        self._selectedLanguages = State(initialValue: SettingsStore.shared.get(key: "Browse.languages"))
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                Section(NSLocalizedString("CONTENT_RATING")) {
                    ForEach(SourceContentRating.allCases, id: \.rawValue) { rating in
                        let index = contentRatings.firstIndex(where: { $0 == rating.stringValue })
                        Button {
                            if let index {
                                contentRatings.remove(at: index)
                            } else {
                                contentRatings.append(rating.stringValue)
                            }
                        } label: {
                            HStack {
                                Text(rating.title)
                                Spacer()
                                if index != nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section(NSLocalizedString("LANGUAGES")) {
                    ForEach(languages) { language in
                        let index = selectedLanguages.firstIndex(where: { $0 == language.id })
                        Button {
                            if let index {
                                selectedLanguages.remove(at: index)
                            } else {
                                selectedLanguages.append(language.id)
                            }
                        } label: {
                            HStack {
                                Text(language.title)
                                Spacer()
                                if index != nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("FILTERS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        dismiss()
                    }
                }
            }
            .onChange(of: contentRatings) { _ in
                SettingsStore.shared.set(key: "Browse.contentRatings", value: contentRatings)
                NotificationCenter.default.post(name: .filterExternalSources, object: nil)
            }
            .onChange(of: selectedLanguages) { _ in
                SettingsStore.shared.set(key: "Browse.languages", value: selectedLanguages)
                NotificationCenter.default.post(name: .filterExternalSources, object: nil)
            }
        }
    }
}
