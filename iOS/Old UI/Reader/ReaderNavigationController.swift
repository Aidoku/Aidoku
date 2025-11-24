//
//  ReaderNavigationController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/23/21.
//

import SwiftUI

class ReaderNavigationController: UINavigationController {
    let readerViewController: ReaderViewController
    let mangaInfo: MangaInfo?

    init(readerViewController: ReaderViewController, mangaInfo: MangaInfo? = nil) {
        self.readerViewController = readerViewController
        self.mangaInfo = mangaInfo
        super.init(rootViewController: readerViewController)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch UserDefaults.standard.string(forKey: "Reader.orientation") {
            case "device": .all
            case "portrait": .portrait
            case "landscape": .landscape
            default: .all
        }
    }
}

struct SwiftUIReaderNavigationController: UIViewControllerRepresentable {
    let readerViewController: ReaderViewController

    func makeUIViewController(context: Context) -> ReaderNavigationController {
        .init(readerViewController: readerViewController)
    }

    func updateUIViewController(_ uiViewController: ReaderNavigationController, context: Context) {
        if readerViewController != uiViewController.readerViewController {
            Task { @MainActor in
                uiViewController.setViewControllers([readerViewController], animated: false)
            }
        }
    }
}
