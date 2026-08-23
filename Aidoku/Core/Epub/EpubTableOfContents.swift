//
//  EpubTableOfContents.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/18/26.
//

import Foundation

/// A book's table of contents, resolved onto the spine the reader navigates.
///
/// One ePub is one chapter, so the host's chapter list describes the books in a series rather than
/// the places inside one. This is the only means of moving through a book other than the slider,
/// which is why `SLICE-MAP.md` calls it core rather than optional.
///
/// `EpubParser` returns the TOC as it is written, addressing archive paths. The reader navigates by
/// spine index, so every entry is resolved against the spine here and any that does not land in it
/// is dropped: a TOC may point at a cover or a landmark that the spine marks `linear="no"`, and an
/// entry the reader cannot be taken to is worse than one that is missing.
///
/// Nothing here touches UIKit or WebKit. It is a list and the arithmetic that reads it.
struct EpubTableOfContents: Equatable {
    /// One place in the book, addressed the way the reader moves.
    struct Entry: Equatable, Identifiable {
        /// Position in the list, which is both document order and a stable identity for a list row.
        let id: Int
        let title: String
        /// Index into the spine, as `ReaderEpubViewModel.spinePaths` orders it.
        let document: Int
        /// The element within the document the entry points at, or nil for its head.
        let fragment: String?
        /// Nesting depth, zero for a top-level entry.
        let depth: Int
    }

    let entries: [Entry]

    var isEmpty: Bool { entries.isEmpty }

    init(entries: [Entry]) {
        self.entries = entries
    }

    /// Resolves a parsed TOC against a spine.
    init(toc: [EpubParser.TocEntry], spinePaths: [String]) {
        var documents: [String: Int] = [:]
        for (index, path) in spinePaths.enumerated() where documents[path] == nil {
            documents[path] = index
        }

        let resolved = toc.compactMap { entry -> (EpubParser.TocEntry, Int)? in
            guard let document = documents[entry.path] else { return nil }
            return (entry, document)
        }

        // Depth is what a book's own nesting says, not what its list markup happens to start at.
        // A nav document that wraps its whole contents in one extra list, or an NCX whose top
        // level is a single "Contents" point, would otherwise indent every row it has.
        let shallowest = resolved.map { $0.0.depth }.min() ?? 0

        entries = resolved.enumerated().map { position, resolved in
            let (entry, document) = resolved
            return Entry(
                id: position,
                title: entry.title,
                document: document,
                fragment: entry.fragment,
                depth: entry.depth - shallowest
            )
        }
    }

    /// The entry a reader in `document` is inside, which is the last one at or before it.
    ///
    /// `nil` when the reader is ahead of the first entry, which is a book whose TOC skips its
    /// opening documents. Where a document holds several entries this returns the first of them:
    /// telling them apart needs the page each fragment sits on, which only a laid-out document can
    /// answer. See `entry(inDocument:atOrBefore:fragmentPages:)`.
    func entry(inDocument document: Int) -> Entry? {
        entries.last { $0.document <= document }
    }

    /// The entries inside one document, in document order.
    ///
    /// A book converted from a single file addresses its whole contents by fragment, so this is
    /// how many places one spine document may hold.
    func entries(inDocument document: Int) -> [Entry] {
        entries.filter { $0.document == document }
    }

    /// The entry a reader on `page` of `document` is inside, given where each of that document's
    /// fragments sits.
    ///
    /// `pages` maps a fragment to the page of the document it begins on, which is what the renderer
    /// can answer for a document it has laid out. A fragment missing from the map is one the
    /// document does not contain, and is passed over rather than assumed to be at its head.
    ///
    /// When none of the document's entries qualifies the answer lies behind it, never back among
    /// them: a book converted from a single file addresses its whole contents by fragment, and a
    /// reader in its front matter is ahead of every one of them.
    func entry(inDocument document: Int, atOrBefore page: Int, fragmentPages pages: [String: Int]) -> Entry? {
        let inside = entries(inDocument: document).filter { entry in
            guard let fragment = entry.fragment else { return true }
            guard let start = pages[fragment] else { return false }
            return start <= page
        }
        return inside.last ?? entries.last { $0.document < document }
    }
}
