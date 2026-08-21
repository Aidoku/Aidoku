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
        defer { EpubFixture.remove(book.url) }
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

    /// What a followed link reported, since the report is the only thing the renderer produces for
    /// one: the navigation itself is cancelled.
    private final class LinkReport: @unchecked Sendable {
        var path: String?
        var fragment: String?
        var reported = false
    }

    /// A link's fragment reaches the book decoded, in the form the table of contents holds.
    ///
    /// `URL.fragment` hands back the percent-encoded form, while `EpubParser` decodes the fragments
    /// it reads out of the navigation document. An anchor whose id is not plain ASCII, which is
    /// every CJK book and any id with a space in it, was therefore reported in one form and looked
    /// up in the other: `fragmentPages` found no element by that id and the reader landed on the
    /// head of the document instead, with nothing said about it.
    @Test func anEncodedLinkFragmentIsReportedDecoded() async throws {
        let anchor = "\u{7B2C}\u{4E00}\u{7AE0}"
        let url = try EpubFixture.makeArchive(entries: [
            "OEBPS/a.xhtml": Data(EpubFixture.page(body: #"<a id="lnk" href="b.xhtml#\#(anchor)">go</a>"#).utf8),
            "OEBPS/b.xhtml": Data(EpubFixture.page(body: #"<h1 id="\#(anchor)">heading</h1>"#).utf8)
        ])
        defer { EpubFixture.remove(url) }

        let renderer = try await EpubFixture.makeRenderer(for: url)
        defer { EpubFixture.dismantle(renderer.webView) }
        _ = try await renderer.load(spinePath: "OEBPS/a.xhtml")

        let report = LinkReport()
        renderer.onLinkActivated = { path, fragment in
            report.path = path
            report.fragment = fragment
            report.reported = true
        }

        _ = try await EpubFixture.evaluate("document.getElementById('lnk').click()", in: renderer.webView)
        try await EpubFixture.waitUntil(timeout: 10) { report.reported }

        #expect(report.path == "OEBPS/b.xhtml")
        #expect(report.fragment == anchor, "the fragment arrived as \(report.fragment ?? "nil")")
    }
}
