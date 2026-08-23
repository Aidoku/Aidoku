//
//  DictionaryVocabListView.swift
//  Aidoku
//
//  Created by skitty on 7/20/26.
//

import SwiftUI

@available(iOS 18.0, *)
struct DictionaryVocabListView: View {
    @EnvironmentObject private var path: NavigationCoordinator

    @State private var entries: [VocabEntry] = []
    @State private var isLoaded = false
    @State private var searchText = ""
    @State private var selectedEntry: VocabEntry?
    @State private var showingClearConfirmation = false

    @Namespace private var zoomNamespace

    private var filteredEntries: [VocabEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }

        let searchTerms = Self.searchTerms(for: query)
        return entries.filter { entry in
            let values = [entry.word, entry.reading, entry.sentence].compactMap { $0 }
            return values.contains { value in
                searchTerms.contains { term in
                    value.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
            }
        }
    }

    var body: some View {
        Group {
            if !isLoaded {
                ProgressView().progressViewStyle(.circular)
            } else if entries.isEmpty {
                UnavailableView(
                    NSLocalizedString("NO_VOCABULARY"),
                    systemImage: "text.rectangle.fill",
                    description: Text(NSLocalizedString("NO_VOCABULARY_TEXT"))
                )
            } else if filteredEntries.isEmpty {
                UnavailableView.search(text: searchText)
            } else {
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredEntries, id: \.self) { entry in
                                Button {
                                    selectedEntry = entry
                                } label: {
                                    VocabItemView(item: entry, menuContent: { contextMenu(for: entry) })
                                        .matchedTransitionSource(id: entry, in: zoomNamespace)
                                }
                                .foregroundStyle(.primary)
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contextMenu {
                                    contextMenu(for: entry)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle(NSLocalizedString("VOCABULARY"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        export()
                    } label: {
                        Label(NSLocalizedString("EXPORT"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)

                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Label(NSLocalizedString("CLEAR_VOCABULARY_LIST"), systemImage: "trash")
                    }
                    .disabled(entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert(NSLocalizedString("CLEAR_VOCABULARY_LIST"), isPresented: $showingClearConfirmation) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("CLEAR"), role: .destructive) {
                Task {
                    await VocabManager.shared.clear()
                }
            }
        } message: {
            Text(NSLocalizedString("CLEAR_VOCABULARY_LIST_TEXT"))
        }
        .if(!entries.isEmpty) {
            $0.searchable(text: $searchText)
        }
        .modifier {
            if #available(iOS 26.0, *), !entries.isEmpty {
                $0.navigationSubtitle({
                    if entries.count == 1 {
                        NSLocalizedString("1_WORD")
                    } else {
                        String(format: NSLocalizedString("%i_WORDS"), entries.count)
                    }
                }())
            } else {
                $0
            }
        }
        .sheet(item: $selectedEntry) { entry in
            DictionaryVocabDetailsView(entry: entry)
                .navigationTransitionZoom(sourceID: entry, in: zoomNamespace)
        }
        .task {
            guard !isLoaded else { return }
            await load()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .dictionaryVocabChanged) {
                await load()
            }
        }
    }

    @ViewBuilder
    func contextMenu(for entry: VocabEntry) -> some View {
        Button(role: .destructive) {
            Task {
                await VocabManager.shared.delete(entry: entry)
            }
        } label: {
            Label(NSLocalizedString("REMOVE_WORD"), systemImage: "trash")
        }
    }

    private func load() async {
        entries = await VocabManager.shared.getEntries()
        isLoaded = true
    }

    private func export() {
        let backupEntries = entries.map(BackupVocabEntry.init(entry:))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

            let data = try encoder.encode(backupEntries)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("aidoku-vocabulary-\(dateFormatter.string(from: .now))")
                .appendingPathExtension("json")
            try data.write(to: url, options: .atomic)

            let viewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            guard let sourceView = path.rootViewController?.view else { return }
            viewController.popoverPresentationController?.sourceView = sourceView
            viewController.popoverPresentationController?.sourceRect = CGRect(
                x: sourceView.bounds.width - 30,
                y: 60,
                width: 0,
                height: 0
            )
            path.present(viewController)
        } catch {
            LogManager.logger.error("Failed to export vocabulary: \(error)")
        }
    }

    private static func searchTerms(for query: String) -> Set<String> {
        var terms = Set([query])
        if let hiraganaCandidates = RomajiConverter.hiraganaCandidates(for: query) {
            terms.formUnion(hiraganaCandidates)
        }
        return terms
    }
}

private struct VocabItemView<MenuContent: View>: View {
    let item: VocabEntry
    @ViewBuilder var menuContent: MenuContent

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack {
                FuriganaText(
                    expression: item.word,
                    reading: item.reading
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            HStack {
                let dateText = item.createdDate.formatted(
                    Date.FormatStyle()
                        .weekday(.abbreviated)
                        .month(.abbreviated)
                        .day()
                        .year()
                        .hour()
                        .minute()
                )
                Text(dateText)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.medium))
                        .padding(12) // increase button tap area
                    // bug: image becomes invisible while menu is presented / dismisses
                }
                .padding(-12)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(
            Color(uiColor: colorScheme == .dark ? .tertiarySystemFill : .systemBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.02), radius: 6, y: 6)
    }
}
