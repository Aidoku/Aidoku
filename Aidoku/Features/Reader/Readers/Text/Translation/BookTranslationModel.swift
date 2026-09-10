import AidokuRunner
import SwiftUI
import Translation

@available(iOS 18.0, *)
@MainActor
final class BookTranslationModel: ObservableObject {
    struct Job: Identifiable {
        let id = UUID()
        let chapter: ChapterIdentifier
        let blocks: [BookTranslationBlock]
        let settings: BookTranslationSettings
        let isAhead: Bool
    }

    @Published private(set) var blocks: [BookTranslationBlock] = []
    @Published private(set) var translations: [String?]?
    @Published private(set) var job: Job?
    @Published private(set) var settings: BookTranslationSettings
    @Published var status: String?
    @Published var error: String?
    @Published var loading = false
    @Published var styleRevision = 0

    private let source: AidokuRunner.Source?
    private let manga: AidokuRunner.Manga
    private let defaults: UserDefaults
    private let cache: BookTranslationCache
    private var chapter: AidokuRunner.Chapter?
    private var nextChapter: AidokuRunner.Chapter?
    private var generation = UUID()
    private var preloadTask: Task<Void, Never>?
    private var requested = false

    init(
        source: AidokuRunner.Source?, manga: AidokuRunner.Manga,
        defaults: UserDefaults = .standard, cache: BookTranslationCache? = nil
    ) {
        self.source = source
        self.manga = manga
        self.defaults = defaults
        self.cache = cache ?? .shared
        settings = BookTranslationSettings(defaults: defaults)
    }

    func reset(chapter: AidokuRunner.Chapter) {
        cancel()
        self.chapter = chapter
        nextChapter = nil
        blocks = []
        translations = nil
        error = nil
        status = nil
        loading = true
    }

    func loaded(blocks: [BookTranslationBlock], next: AidokuRunner.Chapter?) {
        self.blocks = blocks
        nextChapter = next
        loading = false
        guard !blocks.isEmpty else {
            error = NSLocalizedString("TRANSLATION_EMPTY_CHAPTER")
            return
        }
        if requested || settings.automatic {
            requested = false
            translate()
        } else if let cached = cachedTranslation() {
            translations = cached
            preloadNext()
        }
    }

    func updateSettings() {
        let updated = BookTranslationSettings(defaults: defaults)
        let languageChanged = settings.source != updated.source || settings.target != updated.target
        let automaticStarted = !settings.automatic && updated.automatic
        let aheadChanged = settings.ahead != updated.ahead
        let wasTranslated = translations != nil || job?.isAhead == false
        settings = updated
        if languageChanged {
            cancel()
            translations = cachedTranslation()
            error = nil
            if wasTranslated || settings.automatic { translate() }
        } else if automaticStarted {
            translate()
        } else if aheadChanged {
            if settings.ahead && translations != nil {
                preloadNext()
            } else if !settings.ahead {
                preloadTask?.cancel()
                preloadTask = nil
                if job?.isAhead == true {
                    job = nil
                    status = nil
                }
            }
        }
    }

    func updateNextChapter(_ next: AidokuRunner.Chapter?) {
        guard nextChapter != next else { return }
        nextChapter = next
        if translations != nil { preloadNext() }
    }

    func translate() {
        guard !loading, !blocks.isEmpty, let chapter else {
            requested = true
            return
        }
        requested = false
        cancel()
        error = nil
        if let cached = cachedTranslation() {
            translations = cached
            preloadNext()
            return
        }
        status = NSLocalizedString("TRANSLATION_TRANSLATING")
        job = .init(chapter: identifier(chapter), blocks: blocks, settings: settings, isAhead: false)
    }

    func cancel() {
        requested = false
        generation = UUID()
        preloadTask?.cancel()
        preloadTask = nil
        job = nil
        status = nil
    }

    private func identifier(_ chapter: AidokuRunner.Chapter) -> ChapterIdentifier {
        .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
    }

    private func cachedTranslation() -> [String?]? {
        guard let chapter else { return nil }
        return cache.value(
            for: identifier(chapter), source: settings.source, target: settings.target, blocks: blocks
        )
    }

    func cachedBlocks(for chapter: AidokuRunner.Chapter) -> [BookTranslationBlock]? {
        cache.entry(for: identifier(chapter), source: settings.source, target: settings.target)?.blocks
    }

    private func preloadNext() {
        // A refreshed chapter list can replace or remove the next chapter.
        // Cancel its old work before checking whether there is anything new to preload.
        guard job?.isAhead != false else { return }
        preloadTask?.cancel()
        preloadTask = nil
        job = nil
        status = nil
        guard settings.ahead, let nextChapter, !loading else { return }
        if cachedBlocks(for: nextChapter) != nil {
            status = NSLocalizedString("TRANSLATION_NEXT_READY")
            return
        }
        let generation = generation
        let settings = settings
        status = NSLocalizedString("TRANSLATION_PREPARING_NEXT")
        preloadTask = Task { [weak self] in
            guard let self else { return }
            let loader = ReaderTextViewModel(source: source, manga: manga)
            await loader.loadPages(chapter: nextChapter)
            guard !Task.isCancelled, generation == self.generation, self.settings.ahead else { return }
            let texts = loader.pages.map(ReaderTextContent.load)
            guard !texts.isEmpty, texts.allSatisfy({ $0 != nil }), loader.pages.allSatisfy(\.isTextPage) else {
                status = nil
                error = NSLocalizedString("TRANSLATION_NEXT_LOAD_FAILED")
                return
            }
            let blocks = texts.compactMap { $0 }.flatMap(BookTranslationBlock.parse)
            let identifier = identifier(nextChapter)
            if cache.value(
                for: identifier, source: settings.source, target: settings.target, blocks: blocks
            ) != nil {
                status = NSLocalizedString("TRANSLATION_NEXT_READY")
                return
            }
            guard !blocks.isEmpty else { status = nil; return }
            job = .init(chapter: identifier, blocks: blocks, settings: settings, isAhead: true)
        }
    }

    /// The session lives only inside SwiftUI's translationTask. Neither the model
    /// nor the cache retains it after its presenting view goes away.
    func run(_ job: Job, session: TranslationSession) async {
        guard self.job?.id == job.id else { return }
        do {
            let target = job.settings.target.isEmpty ? nil : Locale.Language(identifier: job.settings.target)
            let availability = LanguageAvailability()
            let sample = String(job.blocks.compactMap(\.text).joined(separator: "\n").prefix(8000))
            if !sample.isEmpty {
                let support: LanguageAvailability.Status
                if job.settings.source.isEmpty {
                    support = try await availability.status(for: sample, to: target)
                } else {
                    support = await availability.status(from: .init(identifier: job.settings.source), to: target)
                }
                guard support != .unsupported else { throw TranslationError.unsupportedLanguagePairing }
                // Background pretranslation must not unexpectedly ask for a model download.
                if job.isAhead && support != .installed {
                    throw BookTranslationFailure.nextLanguagesNotInstalled
                }
                try Task.checkCancellation()
                guard self.job?.id == job.id else { return }
                // translations(from:) can identify the language from the actual text
                // and present Apple's download consent when models are missing.
            }

            var results = [String?](repeating: nil, count: job.blocks.count)
            var requests: [TranslationSession.Request] = []
            var chunkCounts: [Int: Int] = [:]
            for (index, block) in job.blocks.enumerated() {
                guard let text = block.text else { continue }
                let chunks = BookTranslationBlock.chunks(text)
                chunkCounts[index] = chunks.count
                for (chunkIndex, chunk) in chunks.enumerated() {
                    requests.append(.init(sourceText: chunk, clientIdentifier: "\(index):\(chunkIndex)"))
                }
            }
            // Responses may arrive out of order; IDs retain the paragraph and chunk order.
            var translatedChunks: [String: String] = [:]
            for start in stride(from: 0, to: requests.count, by: 16) {
                try Task.checkCancellation()
                guard self.job?.id == job.id else { return }
                let batch = Array(requests[start..<min(start + 16, requests.count)])
                let responses = try await session.translations(from: batch)
                for response in responses {
                    if let identifier = response.clientIdentifier { translatedChunks[identifier] = response.targetText }
                }
            }
            for (index, count) in chunkCounts {
                let chunks = (0..<count).compactMap { translatedChunks["\(index):\($0)"] }
                guard chunks.count == count, chunks.allSatisfy({ !$0.isEmpty }) else {
                    throw BookTranslationFailure.incomplete
                }
                results[index] = chunks.joined(separator: " ")
            }
            try Task.checkCancellation()
            guard self.job?.id == job.id else { return }
            cache.insert(
                .init(source: job.settings.source, target: job.settings.target, blocks: job.blocks, translations: results),
                for: job.chapter
            )
            self.job = nil
            if job.isAhead {
                status = NSLocalizedString("TRANSLATION_NEXT_READY")
            } else {
                translations = results
                status = nil
                preloadNext()
            }
        } catch {
            guard self.job?.id == job.id else { return }
            self.job = nil
            status = nil
            if !Task.isCancelled {
                self.error = job.isAhead
                    ? NSLocalizedString("TRANSLATION_NEXT_FAILED") + " " + error.localizedDescription
                    : error.localizedDescription
            }
        }
    }
}

private enum BookTranslationFailure: LocalizedError {
    case incomplete
    case nextLanguagesNotInstalled

    var errorDescription: String? {
        switch self {
        case .incomplete: NSLocalizedString("TRANSLATION_INCOMPLETE")
        case .nextLanguagesNotInstalled: NSLocalizedString("TRANSLATION_NEXT_LANGUAGES")
        }
    }
}
