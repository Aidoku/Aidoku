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

    // the reader's content already answered the tap, so the host should not also act on it.
    // nothing in a web view can be exempted with gestureRecognizer(_:shouldReceive:)
    func consumesTap() -> Bool
}

extension ReaderReaderDelegate {
    func toggleOffset() {
        // do nothing by default
    }

    func consumesTap() -> Bool {
        false
    }
}

protocol ReaderTableOfContentsReader: ReaderReaderDelegate {
    var tableOfContents: EpubTableOfContents { get }

    // not tableOfContents.isEmpty: a book declaring no contents has read them and has none
    var hasReadTableOfContents: Bool { get }

    // async because entries can share a spine document, only the layout telling them apart
    func currentTableOfContentsEntry() async -> EpubTableOfContents.Entry?

    func bookPage(ofTableOfContentsEntry entry: EpubTableOfContents.Entry) -> Int?

    func goToTableOfContentsEntry(_ entry: EpubTableOfContents.Entry)
}

@available(iOS 18.0, *)
protocol ReaderDictionaryReader: ReaderReaderDelegate {
    /// Returns recognized text at the given point (in the reader's view coordinates)
    /// along with the character rect for popup positioning and per-character rects for highlighting.
    func recognizedText(at point: CGPoint) -> TextRecognizer.Result?
    func setDictionaryOverlayTapHandler(_ handler: ((String, String, CGRect, [CGRect]) -> Void)?)
    func setDictionaryOverlayInteractionMode(_ mode: DictionaryOverlayInteractionMode)
    func dismissActiveDictionaryOverlay() -> Bool
}
