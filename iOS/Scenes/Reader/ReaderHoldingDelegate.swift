//
//  ReaderHoldingDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/16/22.
//

import Foundation

protocol ReaderHoldingDelegate: AnyObject {

    func getChapter() -> Chapter
    func getNextChapter() -> Chapter?
    func getPreviousChapter() -> Chapter?
    func setChapter(_ chapter: Chapter)

    func setCurrentPage(_ page: Int)
    func setTotalPages(_ pages: Int)
    func displayPage(_ page: Int) // show page on toolbar but don't set it as current page
    func setCompleted()
}
