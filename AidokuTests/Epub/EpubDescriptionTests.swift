//
//  EpubDescriptionTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/24/26.
//

@testable import Aidoku
import Foundation
import Testing

/// A `dc:description` is declared as text, and publishers routinely put escaped HTML in it anyway.
/// The package document is XML, so reading the element unescapes one level and the markup arrives
/// as literal tags, which is what reached the library screen. These assert against the whole parse
/// rather than against the cleaning in isolation, because the defect lives in the interaction: one
/// unescape happens in the XML reader and the second has to happen after it.
@Suite
struct EpubDescriptionTests {
    /// The smallest archive `EpubParser.parse` accepts, carrying `description` verbatim.
    private static func makeBook(description: String) throws -> URL {
        var entries: [String: Data] = [:]
        entries["META-INF/container.xml"] = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8)
        entries["OEBPS/0.xhtml"] = Data("<html><body><p>Body.</p></body></html>".utf8)
        entries["OEBPS/content.opf"] = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="id">fixture</dc:identifier>
                <dc:title>Fixture</dc:title>
                <dc:language>en</dc:language>
                <dc:description>\(description)</dc:description>
              </metadata>
              <manifest>
                <item id="d0" href="0.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine><itemref idref="d0"/></spine>
            </package>
            """.utf8)
        return try EpubFixture.makeArchive(entries: entries)
    }

    private static func description(of raw: String) throws -> String? {
        let url = try makeBook(description: raw)
        defer { EpubFixture.remove(url) }
        return EpubParser.parse(url: url)?.description
    }

    /// The shape `The Red Tree` and `Hyperion Cantos Complete` both carry. The paragraph break has
    /// to survive, since flattening an anthology's title list into one line reads worse than the
    /// tags it replaces.
    ///
    /// The two trailing spaces are not incidental. A description is rendered as markdown, where a
    /// lone newline is a soft break and renders as a space, so a `<br>` only survives in the
    /// two-space form. A blank line needs no such help, being a paragraph break already.
    @Test func escapedBlockMarkupBecomesParagraphs() throws {
        let raw = "&lt;div&gt;&lt;p class=&quot;description&quot;&gt;Anthology containing:&lt;/p&gt;"
            + "&lt;p&gt;Hyperion&lt;br&gt;Endymion&lt;/p&gt;&lt;/div&gt;"
        #expect(try Self.description(of: raw) == "Anthology containing:\n\nHyperion  \nEndymion")
    }

    /// Consecutive `<br>` tags are a hand-rolled list, which is how `Hyperion Cantos Complete`
    /// writes its seven volumes. Every one of them has to keep its own line.
    @Test func repeatedLineBreaksEachKeepTheirLine() throws {
        let raw = "&lt;p&gt;One&lt;br&gt;Two&lt;br&gt;Three&lt;/p&gt;"
        #expect(try Self.description(of: raw) == "One  \nTwo  \nThree")
    }

    /// `Ikigai`, which escapes twice: the XML reader yields `&#8212;` as literal characters, so the
    /// entity has to be decoded by the pass that drops the tags.
    @Test func inlineMarkupIsDroppedAndEntitiesDecoded() throws {
        let raw = "&lt;b&gt;Bring joy to your days with &lt;i&gt;ikigai&lt;/i&gt;&amp;#8212;the "
            + "happiness of always being busy&lt;/b&gt;"
        #expect(try Self.description(of: raw) == "Bring joy to your days with ikigai\u{2014}the happiness of always being busy")
    }

    /// Most books are already prose, and `4:50 From Paddington` is one. Nothing may be rewritten.
    @Test func plainProseIsUntouched() throws {
        let raw = "SUMMARY:While two trains idle next to each other, Elspeth McGillicuddy sees a strangulation."
        #expect(try Self.description(of: raw) == raw)
    }

    /// An ampersand in prose is not markup. The parse runs, because the guard cannot tell the two
    /// apart, so this pins that it round-trips rather than being mangled or dropped.
    @Test func bareAmpersandSurvives() throws {
        #expect(try Self.description(of: "Tom &amp; Jerry, and other tales") == "Tom & Jerry, and other tales")
    }

    /// A book with no description at all still parses, and reports none rather than an empty string.
    @Test func absentDescriptionIsNil() throws {
        let url = try EpubFixture.makeBook(documents: [1]).url
        defer { EpubFixture.remove(url) }
        #expect(EpubParser.parse(url: url)?.description == nil)
    }
}
