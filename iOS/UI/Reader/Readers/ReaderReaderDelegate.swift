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

    /// Whether the tap being handled has already been answered by the reader itself, and so should
    /// not also toggle the bars or turn a page.
    ///
    /// Asked once, when a tap arrives, and consumed by the asking. Only a reader whose content
    /// handles taps of its own needs it: an ePub's web view follows links, and the tap zones do not
    /// cancel touches over it, so one tap on a footnote both navigates and reaches the host. A
    /// control can be exempted by `gestureRecognizer(_:shouldReceive:)` instead, but nothing inside
    /// a web view is one.
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

/// A reader whose content has a table of contents of its own.
///
/// The host's chapter list describes the chapters of a manga, and one ePub is one chapter, so a
/// book's own contents are the only way to move about inside it besides the slider. Refining the
/// reader protocol rather than adding to it keeps every other reader unchanged, the way
/// `ReaderDictionaryReader` does for text recognition.
protocol ReaderTableOfContentsReader: ReaderReaderDelegate {
    /// The contents of what is open, empty where it declares none.
    var tableOfContents: EpubTableOfContents { get }

    /// The entry the reader is currently inside, or nil where the contents begin after them.
    ///
    /// Asynchronous because several entries may share a spine document, and telling those apart
    /// means asking the laid-out document where each of them begins.
    func currentTableOfContentsEntry() async -> EpubTableOfContents.Entry?

    /// The page of the whole book an entry begins at, one-based, or nil while the pages before it
    /// are still being counted.
    func bookPage(ofTableOfContentsEntry entry: EpubTableOfContents.Entry) -> Int?

    /// Takes the reader to an entry.
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
