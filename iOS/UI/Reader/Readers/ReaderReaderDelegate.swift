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
}

extension ReaderReaderDelegate {
    func toggleOffset() {
        // do nothing by default
    }
}

@available(iOS 18.0, *)
protocol ReaderDictionaryReader: ReaderReaderDelegate {
    /// Returns recognized text at the given point (in the reader's view coordinates)
    /// along with the character rect for popup positioning and per-character rects for highlighting.
    func recognizedText(at point: CGPoint) -> TextRecognizer.Result?
    func setDictionaryOverlayTapHandler(_ handler: ((String, CGRect, [CGRect]) -> Void)?)
    func setDictionaryOverlayInteractionMode(_ mode: DictionaryOverlayInteractionMode)
    func dismissActiveDictionaryOverlay() -> Bool
}
