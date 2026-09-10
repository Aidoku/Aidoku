//
//  ReaderTextViewModel.swift
//  Aidoku
//
//  Created by Skitty on 5/13/25.
//

import AidokuRunner

@MainActor
class ReaderTextViewModel: ReaderPagedViewModel {
    override func loadPages(chapter: AidokuRunner.Chapter) async {
        if let cached = cachedPages(for: chapter) {
            pages = cached
        } else {
            await super.loadPages(chapter: chapter)
        }
        self.chapter = chapter
    }

    override func preload(chapter: AidokuRunner.Chapter) async {
        if let cached = cachedPages(for: chapter) {
            preloadedChapter = chapter
            preloadedPages = cached
        } else {
            await super.preload(chapter: chapter)
        }
    }

    private func cachedPages(for chapter: AidokuRunner.Chapter) -> [Page]? {
        let settings = BookTranslationSettings()
        guard settings.enabled, let entry = BookTranslationCache.shared.entry(
            for: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key),
            source: settings.source, target: settings.target
        ) else { return nil }
        return [.init(sourceId: manga.sourceKey, chapterId: chapter.key,
                      text: entry.blocks.map(\.markdown).joined(separator: "\n\n"), language: chapter.language)]
    }
}
