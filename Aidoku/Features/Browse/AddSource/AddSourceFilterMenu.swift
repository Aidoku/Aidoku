//
//  AddSourceFilterMenu.swift
//  Aidoku
//
//  Created by Skitty on 12/15/25.
//

import AidokuRunner
import SwiftUI

struct AddSourceFilterMenu: View {
    private struct LanguageItem: Hashable, Identifiable {
        let id: String
        let title: String
    }

    @State private var languages: [LanguageItem] = []
    @State private var contentRatings: Set<AidokuRunner.SourceContentRating>
    @State private var selectedLanguages: Set<String>

    @Environment(\.dismiss) private var dismiss

    init() {
        self._contentRatings = State(initialValue: AppSettings.browse.contentRatings.get())
        self._selectedLanguages = State(initialValue: AppSettings.browse.languages.get())
    }

    var body: some View {
        Menu {
            Menu {
                ForEach(SourceContentRating.allCases, id: \.rawValue) { rating in
                    let isEnabled = contentRatings.contains(rating)
                    Button {
                        if isEnabled {
                            contentRatings.remove(rating)
                        } else {
                            contentRatings.insert(rating)
                        }
                    } label: {
                        HStack {
                            Text(rating.title)
                            Spacer()
                            if isEnabled {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .menuActionDismissDisabled()
            } label: {
                Label(NSLocalizedString("CONTENT_RATING"), systemImage: "exclamationmark.triangle.fill")
            }
            Menu {
                ForEach(languages) { language in
                    let code = SourceLanguage.normalized(language.id)
                    let isEnabled = selectedLanguages.contains(code)
                    Button {
                        if isEnabled {
                            selectedLanguages.remove(code)
                        } else {
                            selectedLanguages.insert(code)
                        }
                    } label: {
                        HStack {
                            Text(language.title)
                            Spacer()
                            if isEnabled {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .menuActionDismissDisabled()
            } label: {
                Label(NSLocalizedString("LANGUAGES"), systemImage: "globe")
            }
        } label: {
            if #available(iOS 26.0, *) {
                Image(systemName: "line.3.horizontal.decrease")
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
        .onChange(of: contentRatings) { _ in
            AppSettings.browse.contentRatings.set(contentRatings)
            NotificationCenter.default.post(name: .filterExternalSources, object: nil)
        }
        .onChange(of: selectedLanguages) { _ in
            AppSettings.browse.languages.set(selectedLanguages)
            NotificationCenter.default.post(name: .filterExternalSources, object: nil)
        }
        .task {
            guard languages.isEmpty else { return }

            var languageCodes = await SourceManager.shared.getSourceListLanguages().sorted {
                SourceLanguage.compare($0, $1) == .orderedAscending
            }

            // bring local language to top
            languageCodes.removeAll { $0 == Locale.current.languageCode || $0 == "multi" || $0 == "All" }
            if let code = Locale.current.languageCode {
                languageCodes.insert(code, at: 0)
            }

            self.languages = ([SourceLanguage.multi] + languageCodes).map { code in
                .init(
                    id: code,
                    title: SourceLanguage.displayName(for: code)
                )
            }
        }
    }
}
