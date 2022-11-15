//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation

class ReaderPagedViewModel {

    var chapter: Chapter?
    var pages: [Page] = []

    var preloadedChapter: Chapter?
    var preloadedPages: [Page] = []

    class var settings: SettingItem {
        SettingItem(type: "group", title: NSLocalizedString("PAGED", comment: ""), items: [
            SettingItem(
                type: "select",
                key: "Reader.pagedPageLayout",
                title: NSLocalizedString("PAGE_LAYOUT", comment: ""),
                values: ["single", "double", "auto"],
                titles: [
                    NSLocalizedString("SINGLE_PAGE", comment: ""),
                    NSLocalizedString("DOUBLE_PAGE", comment: ""),
                    NSLocalizedString("AUTOMATIC", comment: "")
                ]
            )
        ])
    }

    func loadPages(chapter: Chapter) async {
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
            pages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
        }
    }

    func preload(chapter: Chapter) async {
        guard preloadedChapter != chapter else { return }
        preloadedChapter = nil
        preloadedPages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []
        preloadedChapter = chapter
    }
}
