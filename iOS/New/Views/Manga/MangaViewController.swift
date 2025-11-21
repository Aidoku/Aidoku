//
//  MangaViewController.swift
//  Aidoku
//
//  Created by Skitty on 7/29/25.
//

import AidokuRunner
import SwiftUI

class MangaViewController: UIHostingController<MangaView> {
    let manga: AidokuRunner.Manga
    let mangaInfo: MangaInfo?

    convenience init(
        source: AidokuRunner.Source? = nil,
        manga: MangaInfo,
        parent: UIViewController?,
        scrollToChapterKey: String? = nil
    ) {
        self.init(
            source: source,
            manga: manga.toManga().toNew(),
            parent: parent,
            scrollToChapterKey: scrollToChapterKey,
            mangaInfo: manga
        )
    }

    init(
        source: AidokuRunner.Source? = nil,
        manga: AidokuRunner.Manga,
        parent: UIViewController?,
        scrollToChapterKey: String? = nil,
        mangaInfo: MangaInfo? = nil
    ) {
        self.manga = manga
        self.mangaInfo = mangaInfo
        super.init(rootView: MangaView(
            source: source,
            manga: manga,
            path: NavigationCoordinator(rootViewController: parent),
            scrollToChapterKey: scrollToChapterKey
        ))

        navigationItem.title = manga.title
        navigationItem.titleView = UIView() // hide navigation bar title
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
