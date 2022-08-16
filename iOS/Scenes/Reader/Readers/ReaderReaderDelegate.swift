//
//  ReaderReaderDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/16/22.
//

import CoreGraphics

protocol ReaderReaderDelegate: AnyObject {

    func sliderMoved(value: CGFloat)
    func sliderStopped(value: CGFloat)
    func setChapter(_ chapter: Chapter, startPage: Int)
}
