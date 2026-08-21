//
//  EpubRendererNavigationTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/21/26.
//

@testable import Aidoku
import Foundation
import Testing

/// A load that throws must leave nothing behind describing the document it was leaving.
///
/// The sibling defect, a report belonging to a replaced navigation resuming the load that replaced
/// it, is fixed in `EpubSpineRenderer.finishNavigation` but is not covered here: reproducing it
/// needs the renderer held mid-navigation, and a fixture document loads faster than a test can
/// observe the window. Delivering a foreign `WKNavigation` through the delegate is the shape that
/// would work, given a resource provider that stalls.
@MainActor
struct EpubRendererNavigationTests {
    /// The state describing a document is cleared before the navigation away from it, so a load that
    /// throws leaves nothing behind claiming to describe what is no longer on screen.
    @Test func aFailedLoadLeavesNoCountFromThePreviousDocument() async throws {
        let book = try EpubFixture.makeBook(documents: [4, 4])
        let renderer = try await EpubFixture.makeRenderer(for: book.url)
        defer { EpubFixture.dismantle(renderer.webView) }

        let first = try await renderer.load(spinePath: book.spinePaths[0])
        #expect(first > 0)

        await #expect(throws: (any Error).self) {
            try await renderer.load(spinePath: "OEBPS/missing.xhtml")
        }

        #expect(renderer.pageCount == 0)
        #expect(renderer.currentPage == 0)
        #expect(renderer.progression == 0)
    }
}
