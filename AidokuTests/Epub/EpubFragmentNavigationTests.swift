//
//  EpubFragmentNavigationTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/18/26.
//

@testable import Aidoku
import Foundation
import Testing
import WebKit

/// A table of contents entry and an internal link both address an element rather than a document,
/// so the reader has to turn one into a page. The arithmetic is the same as the one a page turn
/// uses and is asserted here against documents whose page boundaries are forced rather than
/// measured, so a wrong answer cannot be blamed on where the text happened to fall.
@Suite(.serialized)
@MainActor
struct EpubFragmentNavigationTests {
    /// Three blocks separated by forced column breaks occupy one page each, whatever the text does,
    /// so the page each anchor sits on is known before the document is laid out.
    private static func anchoredDocument() -> Data {
        let body = """
        <style>.break { -webkit-column-break-before: always; break-before: column; }</style>
        <div id="first">one</div>
        <div class="break" id="second">two</div>
        <div class="break" id="third">three</div>
        """
        return Data(EpubFixture.page(body: body).utf8)
    }

    @Test func fragmentsResolveToThePagesTheySitOn() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Self.anchoredDocument()
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        let count = try await renderer.load(spinePath: "OEBPS/page.xhtml")
        #expect(count == 3)

        let pages = await renderer.fragmentPages(["first", "second", "third"])

        #expect(pages == ["first": 0, "second": 1, "third": 2])
    }

    /// The offset a fragment is measured from is the renderer's own, so the answer must not depend
    /// on which page the reader is standing on when they ask.
    @Test func fragmentPagesDoNotMoveWithTheReader() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Self.anchoredDocument()
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        _ = try await renderer.load(spinePath: "OEBPS/page.xhtml")
        let atStart = await renderer.fragmentPages(["first", "second", "third"])

        await renderer.showPage(2)
        await renderer.settle()
        let atEnd = await renderer.fragmentPages(["first", "second", "third"])

        #expect(atStart == atEnd)
    }

    /// An entry pointing at an element the document does not contain is left unanswered rather than
    /// reported as its first page, so a caller can tell "at the head" from "not found".
    @Test func anAbsentFragmentIsNotAnswered() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Self.anchoredDocument()
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        _ = try await renderer.load(spinePath: "OEBPS/page.xhtml")

        let pages = await renderer.fragmentPages(["first", "nowhere"])

        #expect(pages["first"] == 0)
        #expect(pages["nowhere"] == nil)
    }

    /// EPUB 2 addresses a place with `<a name="...">` rather than an id, and books that predate
    /// EPUB 3 are most of what a table of contents is needed for.
    @Test func aNamedAnchorIsFoundAsWellAsAnId() async throws {
        let body = """
        <style>.break { -webkit-column-break-before: always; break-before: column; }</style>
        <div>one</div>
        <div class="break"><a name="named"></a>two</div>
        """
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: body).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        _ = try await renderer.load(spinePath: "OEBPS/page.xhtml")

        let pages = await renderer.fragmentPages(["named"])

        #expect(pages["named"] == 1)
    }

    /// Nothing to ask about, and nothing loaded to ask, are both answered without a round trip
    /// through the web view.
    @Test func nothingIsAskedOfAnUnloadedDocument() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Self.anchoredDocument()
        ])
        defer { EpubFixture.remove(archiveURL) }

        let renderer = try await EpubFixture.makeRenderer(for: archiveURL)
        defer { EpubFixture.dismantle(renderer.webView) }

        #expect(await renderer.fragmentPages(["first"]).isEmpty)

        _ = try await renderer.load(spinePath: "OEBPS/page.xhtml")

        #expect(await renderer.fragmentPages([]).isEmpty)
    }
}
