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
    var chapter: AidokuRunner.Chapter?
    var pages: [Page] = []

    var preloadedChapter: AidokuRunner.Chapter?
    var preloadedPages: [Page] = []

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
        self.source = source
        self.manga = manga
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

            let sourceId = source?.key ?? manga.sourceKey
            let oldChapter = chapter.toOld(
                sourceId: sourceId,
                mangaId: manga.key
            )
            let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: oldChapter.identifier)
            if isDownloaded {
                pages = await DownloadManager.shared.getDownloadedPages(for: oldChapter.identifier)
            } else {
                pages = (try? await source?
                    .getPageList(
                        manga: manga,
                        chapter: chapter
                    )
                )?
                    .map {
                        $0.toOld(sourceId: sourceId, chapterId: chapter.id)
                    } ?? []
            }
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
        let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: identifier)
        if isDownloaded {
            return await DownloadManager.shared.getDownloadedPages(for: identifier)
        } else {
            return (try? await source?
                .getPageList(
                    manga: manga,
                    chapter: chapter
                )
            )?
                .map {
                    $0.toOld(sourceId: sourceId, chapterId: chapter.id)
                } ?? []
        }
    }
}
