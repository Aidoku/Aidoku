//
//  ReaderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/21.
//

import SwiftUI

struct ReaderView: UIViewControllerRepresentable {
    typealias UIViewControllerType = ReaderNavigationController
    
    @Environment(\.presentationMode) var presentationMode
    
    let manga: Manga?
    let chapter: Chapter
    let startPage: Int
    
    func makeUIViewController(context: Context) -> ReaderNavigationController {
        let vc = ReaderViewController(presentationMode: presentationMode, manga: manga, chapter: chapter, startPage: startPage)
        return ReaderNavigationController(rootViewController: vc)
    }
    
    func updateUIViewController(_ uiViewController: ReaderNavigationController, context: Context) {
    }
}
