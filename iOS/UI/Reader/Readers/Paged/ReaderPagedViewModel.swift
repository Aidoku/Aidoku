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
            let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: oldChapter)
            if isDownloaded {
                pages = DownloadManager.shared.getDownloadedPagesWithoutContents(for: oldChapter)
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
        let sourceId = source?.key ?? manga.sourceKey
        let oldChapter = chapter.toOld(sourceId: sourceId, mangaId: manga.key)
        let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: oldChapter)
        if isDownloaded {
            preloadedPages = DownloadManager.shared.getDownloadedPagesWithoutContents(for: oldChapter)
        } else {
            preloadedPages = (try? await source?
                .getPageList(
                    manga: manga,
                    chapter: chapter
                )
            )?
                .map {
                    $0.toOld(sourceId: sourceId, chapterId: chapter.id)
                } ?? []
        }
        preloadedChapter = chapter
    }
}
