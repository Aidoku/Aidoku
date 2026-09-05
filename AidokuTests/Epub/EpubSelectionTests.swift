//
//  EpubSelectionTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 9/2/26.
//

@testable import Aidoku
import Foundation
import Testing
import UIKit
import WebKit

/// The paged style's pages take no touches, so a selection starts from a long press the reader
/// answers itself, and a live selection must not move the page under its handles.
@MainActor
struct EpubSelectionTests {
    /// A press on a word selects that word. One in the space below the text selects nothing, where
    /// `caretRangeFromPoint` alone snaps to the nearest word.
    @Test func aPressSelectsOnlyTheWordUnderIt() async throws {
        let book = try EpubFixture.makeBook(documents: [1])
        defer { EpubFixture.remove(book.url) }
        let renderer = try await EpubFixture.makeRenderer(for: book.url)
        defer { EpubFixture.dismantle(renderer.webView) }
        _ = try await renderer.load(spinePath: book.spinePaths[0])

        // the first word's own box, not the paragraph's, which spans every line
        let firstWord = "(function() { var r = document.createRange(); var t = document.querySelector('p').firstChild;"
            + " r.setStart(t, 0); r.setEnd(t, 9); return r.getClientRects()[0]; })()"
        let x = try await EpubFixture.number("\(firstWord).left + \(firstWord).width / 2", in: renderer.webView)
        let y = try await EpubFixture.number("\(firstWord).top + \(firstWord).height / 2", in: renderer.webView)
        let word = await renderer.selectWord(at: CGPoint(x: x, y: y))
        #expect(word == "Paragraph")

        let bounds = renderer.webView.bounds
        let none = await renderer.selectWord(at: CGPoint(x: bounds.midX, y: bounds.maxY - 4))
        #expect(none.isEmpty, "selected '\(none)' from empty space")
    }

    /// WebKit scrolls the next column in when a handle reaches the edge. A locked page snaps the
    /// scroll view back at once, and releasing the lock leaves the document itself at the page too.
    @Test func aLockedPageHoldsItsOffsetAndTheDocumentFollowsOnRelease() async throws {
        let book = try EpubFixture.makeBook(documents: [40])
        defer { EpubFixture.remove(book.url) }
        let renderer = try await EpubFixture.makeRenderer(for: book.url)
        defer { EpubFixture.dismantle(renderer.webView) }
        _ = try await renderer.load(spinePath: book.spinePaths[0])
        await renderer.showPage(1)
        let pageOffset = EpubFixture.pageOffset(in: renderer.webView)
        #expect(pageOffset > 0)

        renderer.lockPage()
        renderer.webView.scrollView.contentOffset.x = pageOffset + 90
        #expect(EpubFixture.pageOffset(in: renderer.webView) == pageOffset)

        // the document's own position, where the autoscroll leaves it. read in the same script:
        // once the scroll view snaps, WebKit pulls a scripted scroll back on its own, where the
        // autoscroll of a live drag holds the document where it took it
        let drifted = try await EpubFixture.number(
            "(window.scrollTo(\(pageOffset + 90), 0), window.pageXOffset)",
            in: renderer.webView
        )
        #expect(drifted == pageOffset + 90)

        await renderer.unlockPage()
        // the document reports the previous offset for a moment after the script returns
        try await EpubFixture.waitUntil(timeout: 5) {
            (try? await EpubFixture.number("window.pageXOffset", in: renderer.webView)) == pageOffset
        }
        try await EpubFixture.waitUntil(timeout: 5) { EpubFixture.pageOffset(in: renderer.webView) == pageOffset }
    }
}
