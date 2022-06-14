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
    func move(toPage: Int, animated: Bool, reversed: Bool)

    func nextPage()
    func previousPage()

    func willTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
}

extension ReaderPageManager {
    func setChapter(chapter: Chapter, startPage: Int = 0) {
        setChapter(chapter: chapter, startPage: startPage)
    }
    func move(toPage: Int, animated: Bool = false, reversed: Bool = false) {
        move(toPage: toPage, animated: animated, reversed: reversed)
    }
}

protocol ReaderPageManagerDelegate: AnyObject {
    var chapter: Chapter { get set }
    var chapterList: [Chapter] { get set }

    func didMove(toPage page: Int)
    func pagesLoaded()
    func move(toChapter chapter: Chapter)
}
