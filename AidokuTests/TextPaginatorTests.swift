//
//  TextPaginatorTests.swift
//  Aidoku
//

import Testing
import UIKit
@testable import Aidoku

@Suite struct TextPaginatorTests {
    private let pageSize = CGSize(width: 320, height: 480)

    @Test("Text with emoji after sentence breaks paginates without crashing")
    func paginateEmojiAfterSentenceBreak() {
        // Regression test: the sentence-break search reads the UTF-16 code unit
        // following a sentence ender; when that character is an emoji (surrogate
        // pair), UnicodeScalar(UInt16) is nil and was previously force-unwrapped.
        // A single paragraph (no newlines) forces the sentence-break path.
        let sentence = "Some words that fill space before the period.\u{1F600} And then more words follow here. "
        let markdown = String(repeating: sentence, count: 200)
            .replacingOccurrences(of: "\n", with: " ")

        let paginator = TextPaginator()
        let pages = paginator.paginate(markdown: markdown, pageSize: pageSize)

        #expect(!pages.isEmpty)
        #expect(pages.count > 1)
    }

    @Test("Page ranges are contiguous and cover the whole text")
    func pageRangesAreContiguous() {
        let markdown = String(repeating: "A reasonably long paragraph of plain text to fill several pages.\n\n", count: 100)

        let paginator = TextPaginator()
        let pages = paginator.paginate(markdown: markdown, pageSize: pageSize)

        #expect(pages.count > 1)
        for (index, page) in pages.enumerated() {
            #expect(page.id == index)
            #expect(page.range.length > 0)
            if index > 0 {
                let previous = pages[index - 1]
                #expect(page.range.location == previous.range.location + previous.range.length)
            }
        }
    }

    @Test("Empty markdown does not crash")
    func paginateEmptyMarkdown() {
        let paginator = TextPaginator()
        _ = paginator.paginate(markdown: "", pageSize: pageSize)
    }
}
