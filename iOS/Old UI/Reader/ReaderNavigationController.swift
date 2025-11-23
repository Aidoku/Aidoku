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

    let onWillDisappear: (() -> Void)?

    init(readerViewController: ReaderViewController, mangaInfo: MangaInfo? = nil, onWillDisappear: (() -> Void)? = nil) {
        self.readerViewController = readerViewController
        self.mangaInfo = mangaInfo
        self.onWillDisappear = onWillDisappear
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onWillDisappear?()
    }
}

struct SwiftUIReaderNavigationController: UIViewControllerRepresentable {
    let readerViewController: ReaderViewController
    var onWillDisappear: (() -> Void)?

    func makeUIViewController(context: Context) -> ReaderNavigationController {
        .init(readerViewController: readerViewController, onWillDisappear: onWillDisappear)
    }

    func updateUIViewController(_ uiViewController: ReaderNavigationController, context: Context) {}
}
