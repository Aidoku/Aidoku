//
//  EpubTableOfContents.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/18/26.
//

import Foundation

// EpubParser returns the toc addressing archive paths, but the reader navigates by spine index,
// so entries are resolved against the spine here and any that does not land in it is dropped: a toc
// may point at a landmark the spine marks linear="no", and an entry the reader cannot be taken to
// is worse than one that is missing
struct EpubTableOfContents: Equatable {
    struct Entry: Equatable, Identifiable {
        // document order, and a stable identity for a list row
        let id: Int
        let title: String
        // index into the spine, as ReaderEpubViewModel.spinePaths orders it
        let document: Int
        // the element within the document, nil for its head
        let fragment: String?
        let depth: Int
    }

    let entries: [Entry]

    var isEmpty: Bool { entries.isEmpty }

    init(entries: [Entry]) {
        self.entries = entries
    }

    init(toc: [EpubParser.TocEntry], spinePaths: [String]) {
        var documents: [String: Int] = [:]
        for (index, path) in spinePaths.enumerated() where documents[path] == nil {
            documents[path] = index
        }

        let resolved = toc.compactMap { entry -> (EpubParser.TocEntry, Int)? in
            guard let document = documents[entry.path] else { return nil }
            return (entry, document)
        }

        // depth is what the book's nesting says, not what its markup starts at: a nav document
        // wrapping its contents in one extra list would otherwise indent every row it has
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

    // where a document holds several entries this returns the first: telling them apart needs the
    // page each fragment sits on, which only entry(inDocument:atOrBefore:fragmentPages:) can answer
    func entry(inDocument document: Int) -> Entry? {
        entries.last { $0.document <= document }
    }

    func entries(inDocument document: Int) -> [Entry] {
        entries.filter { $0.document == document }
    }

    // pages maps a fragment to the page it begins on. a fragment missing from it is one the
    // document does not contain, and is passed over rather than assumed to be at its head. when
    // none qualifies the answer lies behind the document, never back among them, since a book
    // converted from a single file addresses its whole contents by fragment
    func entry(inDocument document: Int, atOrBefore page: Int, fragmentPages pages: [String: Int]) -> Entry? {
        let inside = entries(inDocument: document).filter { entry in
            guard let fragment = entry.fragment else { return true }
            guard let start = pages[fragment] else { return false }
            return start <= page
        }
        return inside.last ?? entries.last { $0.document < document }
    }
}
