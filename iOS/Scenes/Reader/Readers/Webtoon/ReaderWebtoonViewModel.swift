//
//  ReaderWebtoonViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import Foundation

class ReaderWebtoonViewModel: ReaderPagedViewModel {

    override class var settings: SettingItem {
        SettingItem(type: "group", title: NSLocalizedString("WEBTOON", comment: ""), items: [
            SettingItem(
                type: "switch",
                key: "Reader.verticalInfiniteScroll",
                title: NSLocalizedString("INFINITE_VERTICAL_SCROLL", comment: "")
            )
        ])
    }

    func setPages(chapter: Chapter, pages: [Page]) {
        self.chapter = chapter
        self.pages = pages
        if preloadedChapter == chapter {
            preloadedPages = []
        }
    }
}
