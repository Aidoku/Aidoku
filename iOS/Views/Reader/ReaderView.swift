//
//  ReaderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/21.
//

import SwiftUI

struct ReaderView: UIViewControllerRepresentable {
    typealias UIViewControllerType = ReaderNavigationController
    
    let manga: Manga?
    let chapter: Chapter
    let chapterList: [Chapter]
    
    func makeUIViewController(context: Context) -> ReaderNavigationController {
        let vc = ReaderViewController(manga: manga, chapter: chapter, chapterList: chapterList)
        return ReaderNavigationController(rootViewController: vc)
    }
    
    func updateUIViewController(_ uiViewController: ReaderNavigationController, context: Context) {
    }
}
