//
//  DictionaryVocabDetailsView.swift
//  Aidoku
//
//  Created by skitty on 7/25/26.
//

import AidokuRunner
import SwiftUI
import UIKit

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
    @State private var editedClozeOffset: Int?

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
                            ClozeTextEditor(
                                text: $editedSentence,
                                clozeOffset: $editedClozeOffset,
                                clozeText: entry.clozeText
                            )
                            .frame(minHeight: 120)
                        } else if let sentence = entry.sentence {
                            contextText(sentence)
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
                                    source: sourceManga.flatMap { SourceManager.shared.store.source(for: $0.sourceKey) },
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
                    if isEditing {
                        Button(NSLocalizedString("CANCEL")) {
                            editedSentence = entry.sentence ?? ""
                            editedClozeOffset = entry.clozeOffset
                            withAnimation {
                                isEditing = false
                            }
                        }
                    } else {
                        CloseButton {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        DoneButton {
                            setSentence(editedSentence, clozeOffset: editedClozeOffset)
                            withAnimation {
                                isEditing = false
                            }
                        }
                    } else {
                        Menu {
                            Button {
                                editedSentence = entry.sentence ?? ""
                                editedClozeOffset = entry.clozeOffset
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
                        source: SourceManager.shared.store.source(for: sourceManga.sourceKey),
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
                mangaId: entry.chapterId.mangaIdentifier,
                context: context
            )
            let chapter = CoreDataManager.shared.getChapter(
                chapterId: entry.chapterId,
                context: context
            )
            return (manga?.toNewManga(), chapter?.toNewChapter())
        }

        if manga == nil || chapter == nil {
            let source = await SourceManager.shared.source(for: entry.chapterId.sourceKey)
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

    // make cloze text bold in the context sentence
    private func contextText(_ sentence: String) -> Text {
        var attributedSentence = AttributedString(sentence)
        guard
            let clozeOffset = entry.clozeOffset,
            let clozeText = entry.clozeText,
            let stringRange = Range(NSRange(location: clozeOffset, length: clozeText.utf16.count), in: sentence),
            String(sentence[stringRange]) == clozeText,
            let attributedRange = Range(NSRange(stringRange, in: sentence), in: attributedSentence)
        else {
            return Text(sentence)
        }
        attributedSentence[attributedRange].font = .body.bold()
        return Text(attributedSentence)
    }

    private func setSentence(_ newSentence: String, clozeOffset: Int?) {
        entry.sentence = newSentence
        entry.clozeOffset = clozeOffset
        Task {
            await VocabManager.shared.update(entry: entry)
        }
    }
}

@available(iOS 18.0, *)
private struct ClozeTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var clozeOffset: Int?
    let clozeText: String?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        let font = UIFont.preferredFont(forTextStyle: .body)
        textView.font = font
        textView.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.spellCheckingType = .no
        textView.autocorrectionType = .no
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.clozeOffset = $clozeOffset
        context.coordinator.clozeText = clozeText
        if context.coordinator.sentence(from: textView) != text {
            context.coordinator.setSentence(text, in: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, clozeOffset: $clozeOffset, clozeText: clozeText)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var clozeOffset: Binding<Int?>
        var clozeText: String?

        init(text: Binding<String>, clozeOffset: Binding<Int?>, clozeText: String?) {
            self.text = text
            self.clozeOffset = clozeOffset
            self.clozeText = clozeText
        }

        func setSentence(_ sentence: String, in textView: UITextView) {
            guard
                let clozeOffset = clozeOffset.wrappedValue,
                let clozeText,
                let clozeRange = Range(NSRange(location: clozeOffset, length: clozeText.utf16.count), in: sentence),
                String(sentence[clozeRange]) == clozeText
            else {
                textView.text = sentence
                return
            }

            let font = textView.font ?? .preferredFont(forTextStyle: .body)
            textView.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
            let prefix = String(sentence[..<clozeRange.lowerBound])
            let suffix = String(sentence[clozeRange.upperBound...])
            let attributedText = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: UIColor.label])
            attributedText.append(NSAttributedString(attachment: clozeAttachment(text: clozeText, font: font)))
            attributedText.append(NSAttributedString(string: suffix, attributes: [.font: font, .foregroundColor: UIColor.label]))
            textView.attributedText = attributedText
        }

        func sentence(from textView: UITextView) -> String {
            guard
                let clozeText,
                let attachmentRange = attachmentRange(in: textView.attributedText)
            else {
                return textView.text ?? ""
            }

            let text = textView.text as NSString
            return text.substring(to: attachmentRange.location)
                + clozeText
                + text.substring(from: NSMaxRange(attachmentRange))
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
            guard let attachmentRange = attachmentRange(in: textView.attributedText) else { return true }
            return range.length == 0 || NSIntersectionRange(range, attachmentRange).length == 0
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let clozeText, let attachmentRange = attachmentRange(in: textView.attributedText) else {
                text.wrappedValue = textView.text ?? ""
                return
            }

            let displayedText = textView.text as NSString
            clozeOffset.wrappedValue = displayedText.substring(to: attachmentRange.location).utf16.count
            text.wrappedValue = displayedText.substring(to: attachmentRange.location)
                + clozeText
                + displayedText.substring(from: NSMaxRange(attachmentRange))
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let attachmentRange = attachmentRange(in: textView.attributedText) else {
                return UIMenu(children: suggestedActions)
            }
            let targetsAttachment = NSIntersectionRange(range, attachmentRange).length > 0
                || (range.length == 0 && range.location >= attachmentRange.location && range.location <= NSMaxRange(attachmentRange))
            return targetsAttachment ? UIMenu(children: []) : UIMenu(children: suggestedActions)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard
                let attachmentRange = attachmentRange(in: textView.attributedText),
                NSIntersectionRange(textView.selectedRange, attachmentRange).length > 0
            else {
                return
            }
            textView.selectedRange = NSRange(location: attachmentRange.location, length: 0)
        }

        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            nil
        }

        private func attachmentRange(in attributedText: NSAttributedString) -> NSRange? {
            var result: NSRange?
            attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedText.length)) { value, range, stop in
                guard value is NSTextAttachment else { return }
                result = range
                stop.pointee = true
            }
            return result
        }

        private func clozeAttachment(text: String, font: UIFont) -> NSTextAttachment {
            let label = UILabel()
            label.text = text
            label.font = font
            label.textColor = .label
            label.textAlignment = .center
            label.backgroundColor = .tertiarySystemFill
            label.layer.cornerRadius = 3
            label.clipsToBounds = true
            label.sizeToFit()
            label.frame = label.bounds.insetBy(dx: -3, dy: -1) // center the text better

            let renderer = UIGraphicsImageRenderer(size: label.bounds.size)
            let attachment = NSTextAttachment()
            attachment.image = renderer.image { _ in
                label.drawHierarchy(in: label.bounds, afterScreenUpdates: true)
            }
            attachment.bounds = CGRect(x: 0, y: font.descender, width: label.bounds.width, height: label.bounds.height)
            return attachment
        }
    }
}
