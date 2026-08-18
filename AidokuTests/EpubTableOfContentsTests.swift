//
//  EpubTableOfContentsTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/18/26.
//

@testable import Aidoku
import Foundation
import Testing

/// The table of contents is the only way through a book besides the slider, since one ePub is one
/// chapter. Two things can go wrong silently: an entry can resolve to the wrong spine document,
/// which takes the reader to the wrong place, and the order or the nesting can be lost, which
/// leaves a list that is complete and unreadable. Both are asserted against books written here
/// rather than against the parser's own output.
@Suite
struct EpubTableOfContentsTests {
    // MARK: - Parsing

    /// One row of a TOC as a fixture writes it: where it points, what it says, and how deeply it is
    /// nested.
    private struct Row {
        let target: String
        let title: String
        var depth = 0
    }

    /// A package whose TOC is an EPUB 3 nav document.
    private static func navPackage(spine: [String], entries: [Row]) -> [String: Data] {
        var list = ""
        var depth = 0
        for entry in entries {
            while depth < entry.depth {
                list += "<ol>"
                depth += 1
            }
            while depth > entry.depth {
                list += "</ol>"
                depth -= 1
            }
            list += #"<li><a href="\#(entry.target)">\#(entry.title)</a></li>"#
        }
        while depth > 0 {
            list += "</ol>"
            depth -= 1
        }

        let nav = """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
              <head><title>Contents</title></head>
              <body><nav epub:type="toc"><ol>\(list)</ol></nav></body>
            </html>
            """
        var entriesByPath = package(spine: spine, navHref: "nav.xhtml")
        entriesByPath["OEBPS/nav.xhtml"] = Data(nav.utf8)
        return entriesByPath
    }

    /// A package whose TOC is an EPUB 2 NCX.
    private static func ncxPackage(spine: [String], entries: [Row]) -> [String: Data] {
        var points = ""
        var depth = 0
        for (position, entry) in entries.enumerated() {
            while depth > entry.depth {
                points += "</navPoint>"
                depth -= 1
            }
            // A deeper point is a child of the one before it, which is how an NCX nests.
            points += #"<navPoint id="p\#(position)" playOrder="\#(position)">"#
            points += "<navLabel><text>\(entry.title)</text></navLabel>"
            points += #"<content src="\#(entry.target)"/>"#
            depth = entry.depth + 1
        }
        while depth > 0 {
            points += "</navPoint>"
            depth -= 1
        }

        let ncx = """
            <?xml version="1.0" encoding="utf-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
              <navMap>\(points)</navMap>
            </ncx>
            """
        var entriesByPath = package(spine: spine, ncxHref: "toc.ncx")
        entriesByPath["OEBPS/toc.ncx"] = Data(ncx.utf8)
        return entriesByPath
    }

    /// The container, the OPF and the spine documents, with the TOC declared however the caller
    /// wants it. The documents themselves are only ever addressed by path here.
    private static func package(spine: [String], navHref: String? = nil, ncxHref: String? = nil) -> [String: Data] {
        var entries: [String: Data] = [:]
        var manifest = ""
        var itemrefs = ""
        for (position, name) in spine.enumerated() {
            entries["OEBPS/\(name)"] = Data(EpubFixture.page(body: "<p id=\"start\">\(name)</p>").utf8)
            manifest += #"<item id="d\#(position)" href="\#(name)" media-type="application/xhtml+xml"/>"#
            itemrefs += #"<itemref idref="d\#(position)"/>"#
        }
        if let navHref {
            manifest += #"<item id="nav" href="\#(navHref)" media-type="application/xhtml+xml" properties="nav"/>"#
        }
        if let ncxHref {
            manifest += #"<item id="ncx" href="\#(ncxHref)" media-type="application/x-dtbncx+xml"/>"#
        }

        entries["META-INF/container.xml"] = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8)

        entries["OEBPS/content.opf"] = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="id">fixture</dc:identifier>
                <dc:title>Fixture</dc:title>
                <dc:language>en</dc:language>
              </metadata>
              <manifest>\(manifest)</manifest>
              <spine\(ncxHref == nil ? "" : #" toc="ncx""#)>\(itemrefs)</spine>
            </package>
            """.utf8)
        return entries
    }

    private static func parse(_ entries: [String: Data]) throws -> EpubParser.Book {
        let url = try EpubFixture.makeArchive(entries: entries)
        defer { EpubFixture.remove(url) }
        return try #require(EpubParser.parse(url: url))
    }

    @Test func aNavDocumentKeepsItsOrderAndItsNesting() throws {
        let book = try Self.parse(Self.navPackage(
            spine: ["one.xhtml", "two.xhtml", "three.xhtml"],
            entries: [
                Row(target: "one.xhtml", title: "Part One", depth: 0),
                Row(target: "two.xhtml", title: "A Meeting", depth: 1),
                Row(target: "three.xhtml", title: "Part Two", depth: 0)
            ]
        ))

        #expect(book.toc.map(\.title) == ["Part One", "A Meeting", "Part Two"])
        #expect(book.toc.map(\.depth) == [0, 1, 0])
        #expect(book.toc.map(\.path) == ["OEBPS/one.xhtml", "OEBPS/two.xhtml", "OEBPS/three.xhtml"])
        #expect(book.toc.allSatisfy { $0.fragment == nil })
    }

    @Test func anNcxKeepsItsOrderAndItsNesting() throws {
        let book = try Self.parse(Self.ncxPackage(
            spine: ["one.xhtml", "two.xhtml", "three.xhtml"],
            entries: [
                Row(target: "one.xhtml", title: "Part One", depth: 0),
                Row(target: "two.xhtml", title: "A Meeting", depth: 1),
                Row(target: "three.xhtml", title: "Part Two", depth: 0)
            ]
        ))

        #expect(book.toc.map(\.title) == ["Part One", "A Meeting", "Part Two"])
        #expect(book.toc.map(\.depth) == [0, 1, 0])
    }

    /// Several entries in one document is what a book converted from a single file looks like, and
    /// it is the case a title-per-document map cannot express at all.
    @Test func fragmentsAreKeptAndSeveralEntriesMayShareADocument() throws {
        let book = try Self.parse(Self.navPackage(
            spine: ["all.xhtml"],
            entries: [
                Row(target: "all.xhtml", title: "Cover", depth: 0),
                Row(target: "all.xhtml#ch1", title: "Chapter One", depth: 0),
                Row(target: "all.xhtml#ch2", title: "Chapter Two", depth: 0)
            ]
        ))

        #expect(book.toc.count == 3)
        #expect(book.toc.map(\.fragment) == [nil, "ch1", "ch2"])
        #expect(book.toc.allSatisfy { $0.path == "OEBPS/all.xhtml" })
    }

    /// The chapter grouping is derived from the same entries, so it must not have moved: one title
    /// per document, the first entry in a document naming it.
    @Test func chapterTitlesStillComeFromTheFirstEntryInEachDocument() throws {
        let book = try Self.parse(Self.navPackage(
            spine: ["one.xhtml", "two.xhtml"],
            entries: [
                Row(target: "one.xhtml", title: "Opening", depth: 0),
                Row(target: "one.xhtml#later", title: "Not the chapter title", depth: 1),
                Row(target: "two.xhtml", title: "Closing", depth: 0)
            ]
        ))

        #expect(book.chapters.map(\.title) == ["Opening", "Closing"])
    }

    /// An EPUB 3 nav document is content, so it can address itself.
    @Test func aBareFragmentAddressesTheTocDocumentItself() throws {
        let book = try Self.parse(Self.navPackage(
            spine: ["one.xhtml"],
            entries: [Row(target: "#top", title: "Contents", depth: 0)]
        ))

        #expect(book.toc.map(\.path) == ["OEBPS/nav.xhtml"])
        #expect(book.toc.map(\.fragment) == ["top"])
    }

    @Test func aBookWithNoTocHasNoContents() throws {
        let (url, _) = try EpubFixture.makeBook(documents: [2, 2])
        defer { EpubFixture.remove(url) }
        let book = try #require(EpubParser.parse(url: url))

        #expect(book.toc.isEmpty)
    }

    // MARK: - Resolution against the spine

    private static func entry(_ path: String, _ title: String, fragment: String? = nil, depth: Int = 0)
        -> EpubParser.TocEntry {
        EpubParser.TocEntry(path: path, fragment: fragment, title: title, depth: depth)
    }

    @Test func entriesResolveOntoTheSpine() {
        let contents = EpubTableOfContents(
            toc: [
                Self.entry("a.xhtml", "First"),
                Self.entry("c.xhtml", "Third")
            ],
            spinePaths: ["a.xhtml", "b.xhtml", "c.xhtml"]
        )

        #expect(contents.entries.map(\.document) == [0, 2])
        #expect(contents.entries.map(\.id) == [0, 1])
    }

    /// A cover or a landmark the spine marks `linear="no"` is in the TOC and not in the reading
    /// order, so there is no page in the book to take the reader to.
    @Test func anEntryOutsideTheSpineIsDropped() {
        let contents = EpubTableOfContents(
            toc: [
                Self.entry("cover.xhtml", "Cover"),
                Self.entry("a.xhtml", "First")
            ],
            spinePaths: ["a.xhtml"]
        )

        #expect(contents.entries.map(\.title) == ["First"])
        #expect(contents.entries.map(\.document) == [0])
    }

    /// A nav document that wraps everything in one extra list would otherwise indent every row.
    @Test func depthIsMeasuredFromTheShallowestEntry() {
        let contents = EpubTableOfContents(
            toc: [
                Self.entry("a.xhtml", "First", depth: 2),
                Self.entry("b.xhtml", "Under it", depth: 3)
            ],
            spinePaths: ["a.xhtml", "b.xhtml"]
        )

        #expect(contents.entries.map(\.depth) == [0, 1])
    }

    // MARK: - Where the reader is

    private static let contents = EpubTableOfContents(
        toc: [
            Self.entry("b.xhtml", "Second"),
            Self.entry("b.xhtml", "Second, later", fragment: "later"),
            Self.entry("d.xhtml", "Fourth")
        ],
        spinePaths: ["a.xhtml", "b.xhtml", "c.xhtml", "d.xhtml"]
    )

    @Test func theCurrentEntryIsTheLastOneAtOrBeforeTheDocument() {
        #expect(Self.contents.entry(inDocument: 0) == nil)
        #expect(Self.contents.entry(inDocument: 1)?.title == "Second, later")
        // A document with no entry of its own belongs to the entry before it.
        #expect(Self.contents.entry(inDocument: 2)?.title == "Second, later")
        #expect(Self.contents.entry(inDocument: 3)?.title == "Fourth")
    }

    @Test func fragmentsTellApartTheEntriesThatShareADocument() {
        let pages = ["later": 4]

        #expect(
            Self.contents.entry(inDocument: 1, atOrBefore: 0, fragmentPages: pages)?.title == "Second"
        )
        #expect(
            Self.contents.entry(inDocument: 1, atOrBefore: 3, fragmentPages: pages)?.title == "Second"
        )
        #expect(
            Self.contents.entry(inDocument: 1, atOrBefore: 4, fragmentPages: pages)?.title == "Second, later"
        )
    }

    /// A fragment the document does not contain cannot place the entry that names it, and guessing
    /// at its head would report the reader as somewhere they have not reached.
    @Test func anUnlocatableFragmentDoesNotClaimTheReader() {
        let entry = Self.contents.entry(inDocument: 1, atOrBefore: 9, fragmentPages: [:])

        #expect(entry?.title == "Second")
    }
}
