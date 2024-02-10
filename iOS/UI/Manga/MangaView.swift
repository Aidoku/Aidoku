//
//  MangaView.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 09/02/2024.
//

import SwiftUI

struct MangaView: UIViewControllerRepresentable {

    let manga: Manga
    var chapterList: [Chapter] = []
    var scrollTo: Chapter?

    func makeUIViewController(context: Context) -> MangaViewController {
        MangaViewController(manga: manga, chapterList: chapterList, scrollTo: scrollTo)
    }

    func updateUIViewController(_ uiViewController: MangaViewController, context: Context) {

    }
}
