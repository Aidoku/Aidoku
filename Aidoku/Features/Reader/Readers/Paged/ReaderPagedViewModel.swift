//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation
import AidokuRunner

@MainActor
class ReaderPagedViewModel {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let temporaryPageStore: ReaderTemporaryPageStore?

    var chapter: AidokuRunner.Chapter?
    var pages: [Page] = []

    var preloadedChapter: AidokuRunner.Chapter?
    var preloadedPages: [Page] = []

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        temporaryPageStore: ReaderTemporaryPageStore? = nil
    ) {
        self.source = source
        self.manga = manga
        self.temporaryPageStore = temporaryPageStore
    }

    func loadPages(chapter: AidokuRunner.Chapter) async {
        if preloadedChapter == chapter {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
        } else {
            if !pages.isEmpty {
                preloadedChapter = chapter
                preloadedPages = pages
            }
            self.chapter = chapter
            pages = await getPages(chapter: chapter)
        }
    }

    func preload(chapter: AidokuRunner.Chapter) async {
        guard preloadedChapter != chapter else { return }
        preloadedChapter = nil
        preloadedPages = await getPages(chapter: chapter)
        preloadedChapter = chapter
    }

    private func getPages(chapter: AidokuRunner.Chapter) async -> [Page] {
        let sourceId = source?.key ?? manga.sourceKey
        let identifier = ChapterIdentifier(
            sourceKey: sourceId,
            mangaKey: manga.key,
            chapterKey: chapter.key
        )
        let language = chapter.language ?? source?.languages.first
        let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: identifier)
        if isDownloaded {
            return await DownloadManager.shared.getDownloadedPages(for: identifier)
                .map {
                    $0.toOld(sourceId: sourceId, chapterId: chapter.key, language: language)
                }
        } else {
            guard var sourcePages = try? await source?.getPageList(
                manga: manga,
                chapter: chapter
            ) else {
                return []
            }

            var pages: [Page] = []
            pages.reserveCapacity(sourcePages.count)

            // iterate in reverse so pages with image data are dropped
            while let sourcePage = sourcePages.popLast() {
                var page = sourcePage.toOld(
                    sourceId: sourceId,
                    chapterId: chapter.key,
                    language: language
                )
                if
                    let temporaryPageStore,
                    let image = page.image,
                    let fileURL = await temporaryPageStore.store(
                        image,
                        chapterKey: chapter.key,
                        pageIndex: sourcePages.count
                    )
                {
                    page.image = nil
                    page.imageURL = fileURL.absoluteString
                }
                pages.append(page)
            }

            return pages.reversed()
        }
    }
}
