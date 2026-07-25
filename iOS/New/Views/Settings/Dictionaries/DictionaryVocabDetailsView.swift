//
//  DictionaryVocabDetailsView.swift
//  Aidoku
//
//  Created by skitty on 7/25/26.
//

import AidokuRunner
import SwiftUI

@available(iOS 18.0, *)
struct DictionaryVocabDetailsView: View {
    @State var entry: VocabEntry

    private let userConfig = UserConfig(allowsMining: false)
    private let dictionaryStyles: [String: String]

    @State private var definitionContent: String = ""
    @State private var lookupEntries: [[String: Any]] = []
    @State private var popupHeight: CGFloat = 300

    @State private var sourceManga: AidokuRunner.Manga?
    @State private var sourceChapter: AidokuRunner.Chapter?
    @State private var sourceLoaded = false

    @State private var chapterOpened = false
    @State private var path: NavigationCoordinator?

    @State private var isEditing = false
    @State private var editedSentence = ""

    @Environment(\.dismiss) private var dismiss

    @Namespace private var zoomNamespace

    init(entry: VocabEntry) {
        self._entry = State(initialValue: entry)
        var dictionaryStyles: [String: String] = [:]
        for style in LookupEngine.shared.getStyles() {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        self.dictionaryStyles = dictionaryStyles
    }

    var body: some View {
        NavigationStack {
            List {
                if !isEditing {
                    Section(NSLocalizedString("DEFINITION")) {
                        PopupWebView(
                            content: definitionContent,
                            position: .zero,
                            scale: CGFloat(userConfig.popupScale),
                            clearSelection: false,
                            dictionaryStyles: dictionaryStyles,
                            lookupEntries: lookupEntries,
                            isScrollEnabled: false,
                            onContentHeightChanged: { height in
                                popupHeight = max(1, height)
                            }
                        )
                        .frame(height: popupHeight)
                    }
                }

                if isEditing || entry.sentence != nil {
                    Section(NSLocalizedString("VOCAB_CONTEXT")) {
                        if isEditing {
                            TextEditor(text: $editedSentence)
                                .frame(minHeight: 120)
                        } else if let sentence = entry.sentence {
                            Text(sentence)
                        }
                    }
                }

                if !isEditing && (!sourceLoaded || sourceManga != nil) {
                    Section(NSLocalizedString("VOCAB_SOURCE")) {
                        Button {
                            if sourceChapter != nil {
                                chapterOpened = true
                            } else {
                                openMangaView()
                            }
                        } label: {
                            HStack(spacing: 16) {
                                MangaCoverView(
                                    source: sourceManga.flatMap { SourceManager.shared.source(for: $0.sourceKey) },
                                    coverImage: sourceManga?.cover ?? "",
                                    width: 56,
                                    height: 56 * 3/2,
                                )
                                VStack(alignment: .leading) {
                                    Text(sourceManga?.title ?? "Loading Series Title")
                                        .lineLimit(2)
                                    if !sourceLoaded || sourceChapter != nil {
                                        Text(sourceChapter?.formattedTitle() ?? "Loading")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .if(!sourceLoaded) {
                                $0.redacted(reason: .placeholder).shimmering()
                            }
                        }
                        .foregroundStyle(.primary)
                        .disabled(!sourceLoaded)
                        .matchedTransitionSourcePlease(id: "reader", in: zoomNamespace)
                        .if(sourceLoaded && sourceChapter != nil) {
                            $0.contextMenu {
                                Button {
                                    openMangaView()
                                } label: {
                                    Label(NSLocalizedString("VIEW_SERIES"), systemImage: "book")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(entry.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isEditing {
                        CloseButton {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        DoneButton {
                            setSentence(editedSentence)
                            withAnimation {
                                isEditing = false
                            }
                        }
                    } else {
                        Menu {
                            Button {
                                editedSentence = entry.sentence ?? ""
                                withAnimation {
                                    isEditing = true
                                }
                            } label: {
                                Label(NSLocalizedString("EDIT"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Task {
                                    await VocabManager.shared.delete(entry: entry)
                                }
                                dismiss()
                            } label: {
                                Label(NSLocalizedString("REMOVE_WORD"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isEditing)
            .fullScreenCover(isPresented: $chapterOpened) {
                if let sourceManga, let sourceChapter {
                    SwiftUIReaderNavigationController(
                        source: SourceManager.shared.source(for: sourceManga.sourceKey),
                        manga: sourceManga,
                        chapter: sourceChapter,
                        startPage: entry.page
                    )
                    .ignoresSafeArea()
                    .navigationTransitionZoom(sourceID: "reader", in: zoomNamespace)
                }
            }
            .task {
                guard lookupEntries.isEmpty else { return }
                lookup()
                await loadSource()
            }
        }
        .introspect(.navigationStack, on: .iOS(.v18, .v26, .v27)) { entity in
            path = NavigationCoordinator(rootViewController: entity)
        }
    }

    private func lookup() {
        let results = LookupEngine.shared.lookup(entry.word, maxResults: 1, scanLength: entry.word.utf8.count)
        (definitionContent, lookupEntries) = PopupView.buildContent(lookupResults: results, userConfig: userConfig)
    }

    private func loadSource() async {
        var (manga, chapter) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable [entry] context in
            let manga = CoreDataManager.shared.getManga(
                sourceId: entry.chapterId.sourceKey,
                mangaId: entry.chapterId.mangaKey,
                context: context
            )
            let chapter = CoreDataManager.shared.getChapter(
                sourceId: entry.chapterId.sourceKey,
                mangaId: entry.chapterId.mangaKey,
                chapterId: entry.chapterId.chapterKey,
                context: context
            )
            return (manga?.toNewManga(), chapter?.toNewChapter())
        }

        if manga == nil || chapter == nil {
            let source = SourceManager.shared.source(for: entry.chapterId.sourceKey)
            if let source {
                do {
                    let update = try await source.getMangaUpdate(
                        manga: manga ?? .init(sourceKey: entry.chapterId.sourceKey, key: entry.chapterId.mangaKey, title: ""),
                        needsDetails: manga == nil,
                        needsChapters: chapter == nil
                    )
                    if manga == nil {
                        manga = update
                    }
                    if chapter == nil {
                        chapter = update.chapters?.first(where: { $0.key == entry.chapterId.chapterKey })
                    }
                } catch {
                    LogManager.logger.error("Error fetching vocab source details: \(error)")
                }
            }
        }

        withAnimation {
            sourceManga = manga
            sourceChapter = chapter
            sourceLoaded = true
        }
    }

    private func openMangaView() {
        guard let sourceManga, let path else { return }
        let viewController = MangaViewController(
            manga: sourceManga,
            parent: path.rootViewController
        )
        path.push(viewController)
    }

    private func setSentence(_ newSentence: String) {
        entry.sentence = newSentence
        Task {
            await VocabManager.shared.update(entry: entry)
        }
    }
}
