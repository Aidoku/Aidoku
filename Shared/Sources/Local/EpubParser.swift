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
    }

    struct Chapter {
        /// Paths of the chapter's content files within the archive, in reading order.
        /// Spine files without a TOC entry are grouped into the preceding chapter.
        let hrefs: [String]
        let title: String?

        /// Path of the primary (first) content file, used as the chapter identifier.
        var href: String { hrefs[0] }
    }

    /// A piece of chapter content, in document order.
    enum Segment {
        case text(String)
        /// Archive path of an image referenced by the chapter.
        case image(String)
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

        // chapter titles from the TOC (EPUB 3 nav document or EPUB 2 NCX)
        var titles: [String: String] = [:]
        if let navHref {
            let navPath = resolve(href: navHref, relativeTo: opfDir)
            titles = navTitles(from: archive, navPath: navPath)
        }
        if titles.isEmpty {
            let ncxId = elements("spine", in: opf).first.flatMap { attr($0, "toc") }
            let ncxHref = ncxId.flatMap { manifestHrefs[$0] }
                ?? manifestHrefs.values.first { $0.lowercased().hasSuffix(".ncx") }
            if let ncxHref {
                let ncxPath = resolve(href: ncxHref, relativeTo: opfDir)
                titles = ncxTitles(from: archive, ncxPath: ncxPath)
            }
        }

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
            chapters: chapters
        )
    }

    // MARK: - Chapter Content

    /// Extract a chapter's XHTML from the archive and convert it into
    /// text (markdown) and image segments in document order.
    /// `href` identifies the chapter by its primary content file; grouped
    /// continuation files are included automatically.
    static func chapterSegments(url: URL, href: String) -> [Segment] {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            LogManager.logger.error("EpubParser: failed to open archive \(url.lastPathComponent): \(error)")
            return []
        }

        // resolve the full file group for this chapter
        let hrefs = parse(archive: archive)?
            .chapters.first { $0.href == href }?
            .hrefs ?? [href]

        var segments: [Segment] = []
        for href in hrefs {
            guard let html = extractString(from: archive, path: href) else {
                LogManager.logger.error("EpubParser: failed to extract chapter file \(href)")
                continue
            }
            segments += self.segments(fromHTML: html, basePath: directory(of: href))
        }

        let hasText = segments.contains {
            if case .text = $0 { return true }
            return false
        }

        // drop images that don't exist in the archive, and drop small decorative
        // images (scene dividers, ornaments, logos) when the chapter has text —
        // otherwise every chapter becomes mixed content and can't use the
        // paginated text reader
        // ponytail: 100 KB size heuristic; full-page illustrations in text
        // chapters are practically always larger
        let filtered: [Segment] = segments.compactMap { segment in
            guard case let .image(path) = segment else { return segment }
            guard let entry = entry(in: archive, path: path) else { return nil }
            if hasText && entry.uncompressedSize < 100_000 { return nil }
            return segment
        }

        // merge adjacent text segments (left over after dropping images) so
        // text-only chapters always produce a single text page
        var merged: [Segment] = []
        for segment in filtered {
            if case let .text(text) = segment, case let .text(previous)? = merged.last {
                merged[merged.count - 1] = .text(previous + "\n\n" + text)
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    /// Convert chapter XHTML to segments: markdown text (headings, blockquotes,
    /// list items, emphasis) interleaved with referenced images.
    static func segments(fromHTML html: String, basePath: String) -> [Segment] {
        guard
            let doc = try? SwiftSoup.parse(html),
            let body = doc.body()
        else { return [Segment.text(html)] }

        var segments: [Segment] = []
        var pendingText: [String] = []

        func flushText() {
            if !pendingText.isEmpty {
                segments.append(.text(pendingText.joined(separator: "\n\n")))
                pendingText = []
            }
        }

        func appendImage(_ element: Element) {
            if let path = imagePath(of: element, basePath: basePath) {
                flushText()
                segments.append(.image(path))
            }
        }

        func walk(_ element: Element) {
            for node in element.getChildNodes() {
                guard let child = node as? Element else { continue }
                let tag = localName(child)

                if tag == "img" || tag == "image" {
                    // "image" covers svg <image xlink:href=...> elements
                    appendImage(child)
                } else if blockTags.contains(tag) {
                    let text = inlineMarkdown(of: child).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        switch tag {
                            case "h1", "h2", "h3", "h4", "h5", "h6":
                                let level = Int(String(tag.dropFirst())) ?? 1
                                pendingText.append(String(repeating: "#", count: level) + " " + text)
                            case "blockquote":
                                pendingText.append("> " + text)
                            case "li":
                                pendingText.append("- " + text)
                            default:
                                pendingText.append(text)
                        }
                    }
                    // emit images contained in the block after its text
                    for img in (try? child.select("img, image").array()) ?? [] {
                        appendImage(img)
                    }
                } else {
                    walk(child)
                }
            }
        }

        walk(body)
        flushText()

        if segments.isEmpty {
            // fallback for text not wrapped in block elements
            let text = ((try? body.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(.text(text))
            }
        }
        return segments
    }

    private static let blockTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "blockquote", "li"]

    /// Resolve an image element's source to an archive path, ignoring external and data urls.
    private static func imagePath(of element: Element, basePath: String) -> String? {
        let src = [attr(element, "src"), attr(element, "xlink:href"), attr(element, "href")]
            .compactMap { $0 }
            .first
        guard
            let src,
            !src.hasPrefix("data:"),
            !src.hasPrefix("http://"), !src.hasPrefix("https://")
        else { return nil }
        return resolve(href: stripFragment(src), relativeTo: basePath)
    }

    /// Render an element's inline content, preserving emphasis as markdown.
    private static func inlineMarkdown(of element: Element) -> String {
        var result = ""
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                result += textNode.text()
            } else if let child = node as? Element {
                let inner = inlineMarkdown(of: child)
                switch localName(child) {
                    case "em", "i":
                        result += inner.isEmpty ? "" : "*\(inner)*"
                    case "strong", "b":
                        result += inner.isEmpty ? "" : "**\(inner)**"
                    case "br":
                        result += "\n"
                    case "img":
                        break // images are emitted as separate segments
                    default:
                        result += inner
                }
            }
        }
        return result
    }

    // MARK: - TOC

    /// Chapter titles from an EPUB 3 nav document, keyed by archive path.
    private static func navTitles(from archive: Archive, navPath: String) -> [String: String] {
        guard
            let html = extractString(from: archive, path: navPath),
            let doc = try? SwiftSoup.parse(html)
        else { return [:] }
        let navDir = directory(of: navPath)

        let navs = elements("nav", in: doc)
        let toc = navs.first { attr($0, "epub:type") == "toc" } ?? navs.first
        guard let toc else { return [:] }

        var titles: [String: String] = [:]
        for link in (try? toc.select("a[href]").array()) ?? [] {
            guard
                let href = attr(link, "href"),
                let title = try? link.text(),
                !title.isEmpty
            else { continue }
            let path = resolve(href: stripFragment(href), relativeTo: navDir)
            if titles[path] == nil {
                titles[path] = title
            }
        }
        return titles
    }

    /// Chapter titles from an EPUB 2 NCX file, keyed by archive path.
    private static func ncxTitles(from archive: Archive, ncxPath: String) -> [String: String] {
        guard
            let xml = extractString(from: archive, path: ncxPath),
            let doc = try? SwiftSoup.parse(xml, "", Parser.xmlParser())
        else { return [:] }
        let ncxDir = directory(of: ncxPath)

        var titles: [String: String] = [:]
        for navPoint in elements("navpoint", in: doc) {
            guard
                let src = elements("content", in: navPoint).first.flatMap({ attr($0, "src") }),
                let title = elements("navlabel", in: navPoint).first
                    .flatMap({ elements("text", in: $0).first })
                    .flatMap({ try? $0.text() }),
                !title.isEmpty
            else { continue }
            let path = resolve(href: stripFragment(src), relativeTo: ncxDir)
            if titles[path] == nil {
                titles[path] = title
            }
        }
        return titles
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

    /// Look up an archive entry, tolerating "./" prefixes, percent-encoding, and case differences.
    static func entry(in archive: Archive, path: String) -> Entry? {
        if let entry = archive[path] { return entry }
        let target = path.lowercased()
        return archive.first { entry in
            var entryPath = entry.path
            if entryPath.hasPrefix("./") {
                entryPath = String(entryPath.dropFirst(2))
            }
            return entryPath.lowercased() == target
                || (entryPath.removingPercentEncoding ?? entryPath).lowercased() == target
        }
    }

    private static func extractData(from archive: Archive, path: String) -> Data? {
        guard let entry = entry(in: archive, path: path) else { return nil }
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

    private static func stripFragment(_ href: String) -> String {
        href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
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
