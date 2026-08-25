//
//  EpubTableOfContents.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/18/26.
//

import Foundation

// EpubParser addresses archive paths where the reader navigates by spine index, so an entry that
// does not resolve against the spine is dropped: a toc may point at a landmark marked linear="no",
// and an entry the reader cannot be taken to is worse than one that is missing
struct EpubTableOfContents: Equatable {
    struct Entry: Equatable, Identifiable {
        // document order, and a stable identity for a list row
        let id: Int
        let title: String
        let document: Int
        // nil for the head of the document
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

        // a nav document wrapping its contents in one extra list would otherwise indent every row
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

    // the first where a document holds several; entry(inDocument:atOrBefore:fragmentPages:) needs
    // the layout to tell them apart
    func entry(inDocument document: Int) -> Entry? {
        entries.last { $0.document <= document }
    }

    func entries(inDocument document: Int) -> [Entry] {
        entries.filter { $0.document == document }
    }

    // a fragment missing from pages is one the document does not contain, passed over rather than
    // assumed to be at its head. when none qualifies the answer lies behind the document
    func entry(inDocument document: Int, atOrBefore page: Int, fragmentPages pages: [String: Int]) -> Entry? {
        let inside = entries(inDocument: document).filter { entry in
            guard let fragment = entry.fragment else { return true }
            guard let start = pages[fragment] else { return false }
            return start <= page
        }
        return inside.last ?? entries.last { $0.document < document }
    }
}
