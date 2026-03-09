//
//  ReaderReaderDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/16/22.
//

import UIKit
import AidokuRunner

@MainActor
// swiftlint:disable:next class_delegate_protocol
protocol ReaderReaderDelegate: UIViewController {
    var readingMode: ReadingMode { get set }
    var delegate: ReaderHoldingDelegate? { get set }

    func moveLeft()
    func moveRight()
    func toggleOffset()

    func sliderMoved(value: CGFloat)
    func sliderStopped(value: CGFloat)
    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int)

    /// Returns recognized text at the given point (in the reader's view coordinates)
    /// along with the character rect for popup positioning and per-character rects for highlighting.
    @available(iOS 18.0, *)
    func recognizedText(at point: CGPoint) -> (text: String, fullText: String, rect: CGRect, charRects: [CGRect])?

    @available(iOS 18.0, *)
    func setDictionaryOverlayTapHandler(_ handler: ((String, CGRect, [CGRect]) -> Void)?)

    @available(iOS 18.0, *)
    func dismissActiveDictionaryOverlay() -> Bool
}

extension ReaderReaderDelegate {
    @available(iOS 18.0, *)
    func dismissActiveDictionaryOverlay() -> Bool {
        false
    }
}

extension ReaderReaderDelegate {
    func toggleOffset() {
        // do nothing by default
    }
}
