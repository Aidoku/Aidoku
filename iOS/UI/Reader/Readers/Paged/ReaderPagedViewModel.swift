//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation

@MainActor
class ReaderPagedViewModel {

    var chapter: Chapter?
    var pages: [Page] = []

    var preloadedChapter: Chapter?
    var preloadedPages: [Page] = []

    class var settings: SettingItem {
        SettingItem(type: "group", title: NSLocalizedString("PAGED", comment: ""), items: [
            SettingItem(
                type: "stepper",
                key: "Reader.pagesToPreload",
                title: NSLocalizedString("PAGES_TO_PRELOAD", comment: ""),
                minimumValue: 1,
                maximumValue: 10
            ),
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
            pages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageListWithoutContents(chapter: chapter)) ?? []
        }
    }

    func preload(chapter: Chapter) async {
        guard preloadedChapter != chapter else { return }
        preloadedChapter = nil
        preloadedPages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageListWithoutContents(chapter: chapter)) ?? []
        preloadedChapter = chapter
    }
}
