//
//  NewMangaViewController.swift
//  Aidoku
//
//  Created by Skitty on 7/29/25.
//

import AidokuRunner
import SwiftUI

class NewMangaViewController: UIViewController {
    let source: AidokuRunner.Source
    let manga: AidokuRunner.Manga

    init(source: AidokuRunner.Source, manga: AidokuRunner.Manga) {
        self.source = source
        self.manga = manga

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = manga.title
        navigationItem.titleView = UIView() // hide navigation bar title
        navigationItem.largeTitleDisplayMode = .never

        let path = NavigationCoordinator(rootViewController: self)
        let rootView = MangaView(source: source, manga: manga)
            .environmentObject(path)
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.didMove(toParent: self)
        view.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
