import AidokuRunner
import Combine
import SwiftUI

/// Hosts Apple's translation session and temporary progress above the native
/// reader without changing its scrolling, pagination, or chapter transitions.
@available(iOS 18.0, *)
@MainActor
final class BookTranslationBridge {
    let model: BookTranslationModel
    var didChange: (() -> Void)?
    private var chapter: AidokuRunner.Chapter?
    private var pages: [Page] = []
    private var next: AidokuRunner.Chapter?
    private var active = false
    private var requested = false
    private var cancellables: Set<AnyCancellable> = []

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
        model = .init(source: source, manga: manga)
        model.$translations.dropFirst().sink { [weak self] _ in
            self?.didChange?()
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: BookTranslationSettings.changed).sink { [weak self] _ in
            self?.updateSettings()
        }.store(in: &cancellables)
    }

    func attach(to owner: UIViewController) {
        let host = UIHostingController(rootView: BookTranslationSessionView(model: model))
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        owner.addChild(host)
        owner.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: owner.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: owner.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: owner.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: owner.view.bottomAnchor)
        ])
        host.didMove(toParent: owner)
    }

    func load(chapter: AidokuRunner.Chapter, pages: [Page], next: AidokuRunner.Chapter?) {
        let chapterChanged = self.chapter?.key != chapter.key || self.pages != pages
        self.chapter = chapter
        self.pages = pages
        self.next = next
        if chapterChanged {
            active = false
            model.reset(chapter: chapter)
        }
        updateSettings()
    }

    func updateNextChapter(_ next: AidokuRunner.Chapter?) {
        self.next = next
        if active { model.updateNextChapter(next) }
    }

    func updateSettings() {
        guard BookTranslationSettings().enabled else {
            model.cancel()
            active = false
            requested = false
            didChange?()
            return
        }
        if !active, let chapter, !pages.isEmpty {
            model.reset(chapter: chapter)
            model.updateSettings()
            let texts = pages.map(ReaderTextContent.load)
            guard pages.allSatisfy(\.isTextPage), texts.allSatisfy({ $0 != nil }) else { return }
            active = true
            model.loaded(blocks: texts.compactMap { $0 }.flatMap(BookTranslationBlock.parse), next: next)
        } else {
            model.updateSettings()
        }
        if active && requested {
            requested = false
            model.translate()
        }
        didChange?()
    }

    func translate() {
        requested = true
        updateSettings()
    }
}

@available(iOS 18.0, *)
struct BookTranslationSessionView: View {
    @ObservedObject var model: BookTranslationModel

    var body: some View {
        Color.clear
            .background {
                if let job = model.job {
                    BookTranslationTaskView(model: model, job: job).id(job.id)
                }
            }
            .overlay {
                if model.job?.isAhead == false {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(NSLocalizedString("TRANSLATION_TRANSLATING"))
                            .font(.callout.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(24)
                    .accessibilityElement(children: .combine)
                }
            }
            .allowsHitTesting(false)
    }
}

@MainActor
enum BookTranslationRendering {
    static func texts(pages: [Page], manga: AidokuRunner.Manga) -> [String?] {
        let originals = pages.map(ReaderTextContent.load)
        let settings = BookTranslationSettings()
        guard settings.enabled, let chapterKey = pages.first?.chapterId,
              let entry = BookTranslationCache.shared.entry(
                for: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapterKey),
                source: settings.source, target: settings.target
              ) else { return originals }
        let pageBlocks = originals.map { $0.map(BookTranslationBlock.parse) ?? [] }
        guard pageBlocks.flatMap({ $0 }) == entry.blocks else { return originals }
        var offset = 0
        return pageBlocks.map { blocks in
            defer { offset += blocks.count }
            return markdown(blocks: blocks, translations: Array(entry.translations[offset..<offset + blocks.count]))
        }
    }

    static func markdown(blocks: [BookTranslationBlock], translations: [String?]) -> String {
        blocks.enumerated().map { index, block in
            guard let translation = translations[safe: index] ?? nil else { return block.markdown }
            // Translation output is literal prose, not Markdown supplied by a source.
            // Entities also avoid stray backslashes inside automatically detected URLs.
            return translation.map { character in
                if let value = character.asciiValue, "\\`*_{}[]<>()#+-.!|>&:/".contains(character) {
                    return "&#\(value);"
                }
                return String(character)
            }.joined()
        }.joined(separator: "\n\n")
    }
}
