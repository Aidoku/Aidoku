//
//  MangaViewController.swift
//  Aidoku
//
//  Created by Skitty on 7/29/25.
//

import AidokuRunner
import SwiftUI

class MangaViewController: UIHostingController<MangaView> {
    convenience init(
        source: AidokuRunner.Source? = nil,
        manga: AidokuRunner.Manga,
        parent: UIViewController?,
        scrollToChapterKey: String? = nil,
    ) {
        self.init(rootView: MangaView(
            source: source,
            manga: manga,
            path: NavigationCoordinator(rootViewController: parent),
            scrollToChapterKey: scrollToChapterKey
        ))

        navigationItem.title = manga.title
        navigationItem.titleView = UIView() // hide navigation bar title
        navigationItem.largeTitleDisplayMode = .never
    }
}
