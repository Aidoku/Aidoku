//
//  EpubParser.swift
//  Aidoku
//
//  Minimal EPUB 2/3 parser for the local files source.
//  Extracts book metadata, the spine (reading order), chapter titles from the
//  TOC, the cover image, and converts chapter XHTML into text and image
//  segments for the reader.
//
//  XML element lookups match on local names so that namespace-prefixed
//  packages (e.g. <opf:item>, <odc:rootfile>) parse the same as unprefixed ones.
//

import Foundation
import SwiftSoup
import ZIPFoundation

enum EpubParser {
    struct Book {
        var title: String?
        var author: String?
        var description: String?
        var coverData: Data?
        /// Chapters in spine (reading) order.
        var chapters: [Chapter]
        /// The book's table of contents in document order, empty where the book declares none.
        var toc: [TocEntry]
    }

    struct Chapter {
        /// Paths of the chapter's content files within the archive, in reading order.
        /// Spine files without a TOC entry are grouped into the preceding chapter.
        let hrefs: [String]
        let title: String?

        /// Path of the primary (first) content file, used as the chapter identifier.
        var href: String { hrefs[0] }
    }

    /// One entry of the book's table of contents.
    ///
    /// Distinct from `Chapter`, which is a run of spine documents: an entry is a *place*, so
    /// several may point into one document and one may sit beneath another. The reader navigates
    /// by these; the chapter grouping only decides where a chapter starts.
    struct TocEntry: Equatable {
        /// Path of the content file within the archive.
        let path: String
        /// The fragment the entry points at, without its `#`, or nil for the head of the document.
        let fragment: String?
        let title: String
        /// Nesting depth, zero for a top-level entry.
        let depth: Int
    }

    // MARK: - Parsing

    static func parse(url: URL) -> Book? {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            LogManager.logger.error("EpubParser: failed to open archive \(url.lastPathComponent): \(error)")
            return nil
        }
        return parse(archive: archive)
    }

    static func parse(archive: Archive) -> Book? {
        // container.xml points to the OPF package document
        guard
            let containerXml = extractString(from: archive, path: "META-INF/container.xml"),
            let container = try? SwiftSoup.parse(containerXml, "", Parser.xmlParser())
        else {
            LogManager.logger.error("EpubParser: missing or unreadable META-INF/container.xml")
            return nil
        }
        guard
            let opfPath = elements("rootfile", in: container).first.flatMap({ attr($0, "full-path") }),
            let opfXml = extractString(from: archive, path: opfPath),
            let opf = try? SwiftSoup.parse(opfXml, "", Parser.xmlParser())
        else {
            LogManager.logger.error("EpubParser: missing or unreadable OPF package document")
            return nil
        }

        let opfDir = directory(of: opfPath)

        // metadata
        let metadata = elements("metadata", in: opf).first
        let title = metadata.flatMap { elements("title", in: $0).first.flatMap { try? $0.text() } }
        let author = metadata.flatMap { elements("creator", in: $0).first.flatMap { try? $0.text() } }
        let description = metadata.flatMap { elements("description", in: $0).first.flatMap { try? $0.text() } }

        // manifest: id -> href
        var manifestHrefs: [String: String] = [:]
        var coverHref: String?
        var navHref: String?
        for item in elements("manifest", in: opf).flatMap({ elements("item", in: $0) }) {
            guard let id = attr(item, "id"), let href = attr(item, "href") else { continue }
            manifestHrefs[id] = href
            let properties = attr(item, "properties") ?? ""
            if properties.contains("cover-image") {
                coverHref = href
            }
            if properties.contains("nav") {
                navHref = href
            }
        }

        // EPUB 2 cover: <meta name="cover" content="manifest-id">
        if coverHref == nil, let metadata {
            let coverId = elements("meta", in: metadata)
                .first { attr($0, "name") == "cover" }
                .flatMap { attr($0, "content") }
            if let coverId, let href = manifestHrefs[coverId] {
                coverHref = href
            }
        }

        // the TOC (EPUB 3 nav document or EPUB 2 NCX), in document order
        var toc: [TocEntry] = []
        if let navHref {
            let navPath = resolve(href: navHref, relativeTo: opfDir)
            toc = navEntries(from: archive, navPath: navPath)
        }
        if toc.isEmpty {
            let ncxId = elements("spine", in: opf).first.flatMap { attr($0, "toc") }
            let ncxHref = ncxId.flatMap { manifestHrefs[$0] }
                ?? manifestHrefs.values.first { $0.lowercased().hasSuffix(".ncx") }
            if let ncxHref {
                let ncxPath = resolve(href: ncxHref, relativeTo: opfDir)
                toc = ncxEntries(from: archive, ncxPath: ncxPath)
            }
        }
        // chapter titles are the same entries keyed by document, the first entry in a document
        // naming it, since a chapter starts where a document does and an entry need not.
        let titles = titlesByPath(of: toc)

        // spine defines the reading order; group files without a TOC entry
        // (illustrations, chapter continuations) into the preceding chapter
        var chapters: [Chapter] = []
        var currentHrefs: [String] = []
        var currentTitle: String?
        func flushChapter() {
            if !currentHrefs.isEmpty {
                chapters.append(Chapter(hrefs: currentHrefs, title: currentTitle))
            }
            currentHrefs = []
            currentTitle = nil
        }
        let hasTitles = !titles.isEmpty
        for itemref in elements("spine", in: opf).flatMap({ elements("itemref", in: $0) }) {
            guard
                attr(itemref, "linear") != "no",
                let idref = attr(itemref, "idref"),
                let href = manifestHrefs[idref]
            else { continue }
            let path = resolve(href: href, relativeTo: opfDir)
            let title = titles[path]
            // without a toc, every file is its own chapter
            if !hasTitles || title != nil {
                flushChapter()
                currentTitle = title
            }
            currentHrefs.append(path)
        }
        flushChapter()

        if chapters.isEmpty {
            LogManager.logger.error("EpubParser: no readable chapters found in spine")
        }

        let coverData = coverHref.flatMap {
            extractData(from: archive, path: resolve(href: $0, relativeTo: opfDir))
        }

        return Book(
            title: title?.isEmpty == true ? nil : title,
            author: author?.isEmpty == true ? nil : author,
            description: description?.isEmpty == true ? nil : description,
            coverData: coverData,
            chapters: chapters,
            toc: toc
        )
    }

    // MARK: - TOC

    /// The table of contents from an EPUB 3 nav document, in document order.
    private static func navEntries(from archive: Archive, navPath: String) -> [TocEntry] {
        guard
            let html = extractString(from: archive, path: navPath),
            let doc = try? SwiftSoup.parse(html)
        else { return [] }
        let navDir = directory(of: navPath)

        let navs = elements("nav", in: doc)
        let toc = navs.first { attr($0, "epub:type") == "toc" } ?? navs.first
        guard let toc else { return [] }

        var entries: [TocEntry] = []
        // `select` yields document order, which is reading order for a well-formed nav document.
        for link in (try? toc.select("a[href]").array()) ?? [] {
            guard
                let href = attr(link, "href"),
                let title = try? link.text(),
                !title.isEmpty
            else { continue }
            entries.append(
                TocEntry(
                    path: target(of: href, relativeTo: navDir, ownPath: navPath),
                    fragment: fragment(of: href),
                    title: title,
                    // Nesting is the lists between the link and the nav itself. The outermost list
                    // is the nav's own, so it is what depth is counted from rather than a level of it.
                    depth: max(nesting(of: link, under: toc, tags: ["ol", "ul"]) - 1, 0)
                )
            )
        }
        return entries
    }

    /// The table of contents from an EPUB 2 NCX file, in document order.
    private static func ncxEntries(from archive: Archive, ncxPath: String) -> [TocEntry] {
        guard
            let xml = extractString(from: archive, path: ncxPath),
            let doc = try? SwiftSoup.parse(xml, "", Parser.xmlParser())
        else { return [] }
        let ncxDir = directory(of: ncxPath)

        var entries: [TocEntry] = []
        // A nested navPoint follows its parent in document order, so the flat walk is reading
        // order and the nesting is recovered from each point's ancestors.
        for navPoint in elements("navpoint", in: doc) {
            guard
                let src = elements("content", in: navPoint).first.flatMap({ attr($0, "src") }),
                let title = elements("navlabel", in: navPoint).first
                    .flatMap({ elements("text", in: $0).first })
                    .flatMap({ try? $0.text() }),
                !title.isEmpty
            else { continue }
            entries.append(
                TocEntry(
                    path: target(of: src, relativeTo: ncxDir, ownPath: ncxPath),
                    fragment: fragment(of: src),
                    title: title,
                    depth: nesting(of: navPoint, under: doc, tags: ["navpoint"])
                )
            )
        }
        return entries
    }

    /// Chapter titles keyed by archive path, which is the TOC read as one title per document.
    ///
    /// The first entry in a document names it, since a chapter starts where a document does while
    /// an entry may point partway into one.
    private static func titlesByPath(of entries: [TocEntry]) -> [String: String] {
        var titles: [String: String] = [:]
        for entry in entries where titles[entry.path] == nil {
            titles[entry.path] = entry.title
        }
        return titles
    }

    /// How many of `tags` the element sits inside, stopping at `root`.
    private static func nesting(of element: Element, under root: Node, tags: [String]) -> Int {
        var depth = 0
        for parent in element.parents().array() {
            if parent === root { break }
            if tags.contains(localName(parent)) { depth += 1 }
        }
        return depth
    }

    /// The archive path a TOC href points at.
    ///
    /// A bare fragment addresses the TOC document itself, which in EPUB 3 is content like any
    /// other and can be in the spine.
    private static func target(of href: String, relativeTo dir: String, ownPath: String) -> String {
        let path = stripFragment(href)
        return path.isEmpty ? ownPath : resolve(href: path, relativeTo: dir)
    }

    // MARK: - XML Helpers

    /// The tag name without any namespace prefix, lowercased.
    private static func localName(_ element: Element) -> String {
        let tag = element.tagName().lowercased()
        return tag.split(separator: ":").last.map(String.init) ?? tag
    }

    /// All descendant elements matching a local (namespace-stripped) tag name.
    private static func elements(_ tag: String, in root: Element) -> [Element] {
        (try? root.getAllElements().array())?.filter { $0 !== root && localName($0) == tag } ?? []
    }

    private static func elements(_ tag: String, in root: Document) -> [Element] {
        (try? root.getAllElements().array())?.filter { localName($0) == tag } ?? []
    }

    /// A non-empty attribute value, or nil.
    private static func attr(_ element: Element, _ name: String) -> String? {
        guard let value = try? element.attr(name), !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Archive Helpers

    private static func extractData(from archive: Archive, path: String) -> Data? {
        guard let entry = archive.entry(at: path) else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { data.append($0) }
        } catch {
            return nil
        }
        return data
    }

    private static func extractString(from archive: Archive, path: String) -> String? {
        guard let data = extractData(from: archive, path: path) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Path Helpers

    private static func directory(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// An href without its fragment, which is empty for an href that is only a fragment.
    private static func stripFragment(_ href: String) -> String {
        guard let hash = href.firstIndex(of: "#") else { return href }
        return String(href[href.startIndex..<hash])
    }

    /// The fragment of an href, without its `#`, or nil where there is none.
    private static func fragment(of href: String) -> String? {
        guard let hash = href.firstIndex(of: "#") else { return nil }
        let fragment = String(href[href.index(after: hash)...])
        guard !fragment.isEmpty else { return nil }
        return fragment.removingPercentEncoding ?? fragment
    }

    /// Resolve a (possibly percent-encoded) relative href against a base directory.
    static func resolve(href: String, relativeTo dir: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var components = dir.isEmpty ? [] : dir.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/") {
            switch part {
                case ".":
                    continue
                case "..":
                    if !components.isEmpty { components.removeLast() }
                default:
                    components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }
}
