import SwiftUI
import Translation

@available(iOS 18.0, *)
struct BookTranslationSettingsView: View {
    let translateChapter: () -> Void
    var model: BookTranslationModel?
    @AppStorage(BookTranslationSettings.enabledKey) private var enabled = false
    @AppStorage(BookTranslationSettings.automaticKey) private var automatic = false
    @AppStorage(BookTranslationSettings.aheadKey) private var ahead = false
    @AppStorage(BookTranslationSettings.sourceKey) private var source = ""
    @AppStorage(BookTranslationSettings.targetKey) private var target = ""
    @AppStorage(BookTranslationSettings.splitKey) private var split = false
    @State private var languages: [Locale.Language] = []

    var body: some View {
        List {
            if let model {
                BookTranslationStatusView(model: model)
            }
            Section {
                Toggle(NSLocalizedString("TRANSLATION_ENABLE"), isOn: $enabled)
                Button(NSLocalizedString("TRANSLATION_TRANSLATE_CHAPTER"), action: translateChapter)
            } footer: {
                Text(NSLocalizedString("TRANSLATION_MODE_FOOTER"))
            }
            Section {
                Toggle(NSLocalizedString("TRANSLATION_AUTOMATIC"), isOn: $automatic)
                Toggle(NSLocalizedString("TRANSLATION_ONE_AHEAD"), isOn: $ahead)
            } footer: {
                Text(NSLocalizedString("TRANSLATION_AUTOMATIC_FOOTER"))
            }
            Section {
                languagePicker(title: NSLocalizedString("TRANSLATION_SOURCE_LANGUAGE"), selection: $source)
                languagePicker(title: NSLocalizedString("TRANSLATION_TARGET_LANGUAGE"), selection: $target)
            } footer: {
                Text(NSLocalizedString("TRANSLATION_LANGUAGES_FOOTER"))
            }
            Section {
                Toggle(NSLocalizedString("TRANSLATION_SPLIT"), isOn: $split)
            } footer: {
                Text(NSLocalizedString("TRANSLATION_SPLIT_FOOTER"))
            }
            Section {
                Text(NSLocalizedString("TRANSLATION_CACHE_FOOTER"))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("BOOK_TRANSLATION"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            languages = await LanguageAvailability().supportedLanguages.sorted {
                languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending
            }
        }
        .onChange(of: enabled) { _ in changed() }
        .onChange(of: automatic) { _ in changed() }
        .onChange(of: ahead) { _ in changed() }
        .onChange(of: source) { _ in changed() }
        .onChange(of: target) { _ in changed() }
        .onChange(of: split) { _ in changed() }
    }

    private func languagePicker(title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text(NSLocalizedString("AUTOMATIC")).tag("")
            // Keep a previously chosen language visible while availability loads.
            if !selection.wrappedValue.isEmpty && !languages.contains(where: { $0.minimalIdentifier == selection.wrappedValue }) {
                Text(Locale.current.localizedString(forIdentifier: selection.wrappedValue) ?? selection.wrappedValue)
                    .tag(selection.wrappedValue)
            }
            ForEach(languages, id: \.minimalIdentifier) { language in
                Text(languageName(language)).tag(language.minimalIdentifier)
            }
        }
    }

    private func languageName(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    private func changed() {
        NotificationCenter.default.post(name: BookTranslationSettings.changed, object: nil)
    }
}

@available(iOS 18.0, *)
private struct BookTranslationStatusView: View {
    @ObservedObject var model: BookTranslationModel

    var body: some View {
        if model.status != nil || model.error != nil {
            Section {
                if let status = model.status { Text(status) }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                if model.job != nil {
                    Button(NSLocalizedString("CANCEL")) { model.cancel() }
                }
            }
        }
    }
}
