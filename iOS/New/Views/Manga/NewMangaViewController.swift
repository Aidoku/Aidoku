//
//  NewMangaViewController.swift
//  Aidoku
//
//  Created by Skitty on 7/29/25.
//

import AidokuRunner
import SwiftUI

class NewMangaViewController: UIHostingController<MangaView> {
    convenience init(source: AidokuRunner.Source, manga: AidokuRunner.Manga, parent: UIViewController?) {
        self.init(rootView: MangaView(source: source, manga: manga, path: NavigationCoordinator(rootViewController: parent)))

        navigationItem.title = manga.title
        navigationItem.titleView = UIView() // hide navigation bar title
        navigationItem.largeTitleDisplayMode = .never
    }
}
