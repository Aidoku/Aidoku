//
//  ReaderHoldingDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/16/22.
//

import Foundation
import AidokuRunner

protocol ReaderHoldingDelegate: AnyObject {

    func getNextChapter() -> AidokuRunner.Chapter?
    func getPreviousChapter() -> AidokuRunner.Chapter?
    func setChapter(_ chapter: AidokuRunner.Chapter)

    func setCurrentPage(_ page: Int)
    func setCurrentPages(_ pages: ClosedRange<Int>)
    func setPages(_ pages: [Page])
    func displayPage(_ page: Int) // show page on toolbar but don't set it as current page
    func setSliderOffset(_ offset: CGFloat)
    func setCompleted()
}
