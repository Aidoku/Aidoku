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
        chapterKey: String? = nil,
        openAction: MangaView.OpenAction? = nil,
    ) {
        self.init(
            source: source,
            manga: manga.toManga().toNew(),
            parent: parent,
            chapterKey: chapterKey,
            openAction: openAction,
            mangaInfo: manga
        )
    }

    init(
        source: AidokuRunner.Source? = nil,
        manga: AidokuRunner.Manga,
        parent: UIViewController?,
        chapterKey: String? = nil,
        openAction: MangaView.OpenAction? = nil,
        mangaInfo: MangaInfo? = nil
    ) {
        self.manga = manga
        self.mangaInfo = mangaInfo
        super.init(rootView: MangaView(
            source: source,
            manga: manga,
            path: NavigationCoordinator(rootViewController: parent),
            chapterKey: chapterKey,
            openAction: openAction
        ))

        navigationItem.title = manga.title
        navigationItem.titleView = UIView() // hide navigation bar title
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
