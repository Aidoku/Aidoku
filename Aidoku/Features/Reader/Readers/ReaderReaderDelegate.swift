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

    // true when the reader's own content already answered the tap, so the host should not also
    // toggle the bars or turn a page. nothing inside a web view can be exempted with
    // gestureRecognizer(_:shouldReceive:), so an epub link tap would otherwise do both
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

// a reader whose content carries its own table of contents
protocol ReaderTableOfContentsReader: ReaderReaderDelegate {
    var tableOfContents: EpubTableOfContents { get }

    // not the same question as tableOfContents.isEmpty: a book that declares no contents has read
    // them and has none, and reading emptiness as "not yet" left the contents button disabled for
    // the whole of such a book
    var hasReadTableOfContents: Bool { get }

    // async because entries can share a spine document, so telling them apart means asking the
    // laid-out document where each begins. nil where the contents begin after the current page
    func currentTableOfContentsEntry() async -> EpubTableOfContents.Entry?

    // one-based, nil while the pages before the entry are still being counted
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
