//
//  ReaderPageManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/15/22.
//

import UIKit

protocol ReaderPageManager {
    var delegate: ReaderPageManagerDelegate? { get set }
    var chapter: Chapter? { get set }
    var pages: [Page] { get set }
    var readingMode: MangaViewer? { get set }

    func attach(toParent parent: UIViewController)
    func remove()

    func setChapter(chapter: Chapter, startPage: Int)
    func move(toPage: Int)
}

extension ReaderPageManager {
    func setChapter(chapter: Chapter, startPage: Int = 0) {
        setChapter(chapter: chapter, startPage: startPage)
    }
}

protocol ReaderPageManagerDelegate: AnyObject {
    var chapterList: [Chapter] { get set }

    func didMove(toPage page: Int)
    func pagesLoaded()
    func move(toChapter chapter: Chapter)
}
