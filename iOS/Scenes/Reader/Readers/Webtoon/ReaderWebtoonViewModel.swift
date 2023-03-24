//
//  ReaderWebtoonViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import Foundation

@MainActor
class ReaderWebtoonViewModel: ReaderPagedViewModel {

    override class var settings: SettingItem {
        SettingItem(
            type: "group",
            title: NSLocalizedString("WEBTOON", comment: ""),
            footer: NSLocalizedString("PILLARBOX_ORIENTATION_INFO", comment: ""),
            items: [
                SettingItem(
                    type: "switch",
                    key: "Reader.verticalInfiniteScroll",
                    title: NSLocalizedString("INFINITE_VERTICAL_SCROLL", comment: "")
                ),
                SettingItem(
                    type: "switch",
                    key: "Reader.pillarbox",
                    title: NSLocalizedString("PILLARBOX", comment: "")
                ),
                SettingItem(
                    type: "stepper",
                    key: "Reader.pillarboxAmount",
                    title: NSLocalizedString("PILLARBOX_AMOUNT", comment: ""),
                    requires: "Reader.pillarbox",
                    minimumValue: 0,
                    maximumValue: 100,
                    stepValue: 5
                ),
                SettingItem(
                    type: "select",
                    key: "Reader.pillarboxOrientation",
                    title: NSLocalizedString("PILLARBOX_ORIENTATION", comment: ""),
                    values: ["both", "portrait", "landscape"],
                    titles: [
                        NSLocalizedString("BOTH", comment: ""),
                        NSLocalizedString("PORTRAIT", comment: ""),
                        NSLocalizedString("LANDSCAPE", comment: "")
                    ],
                    requires: "Reader.pillarbox"
                )
            ]
        )
    }

    func setPages(chapter: Chapter, pages: [Page]) {
        self.chapter = chapter
        self.pages = pages
        if preloadedChapter == chapter {
            preloadedPages = []
        }
    }
}
