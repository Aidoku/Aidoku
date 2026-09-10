import Foundation

/// Keeps Markdown and paragraph boundaries out of the translation service. Only
/// visible prose is translated; image URLs and code never become translation input.
struct BookTranslationBlock: Equatable, Sendable {
    let markdown: String
    let text: String?

    static func parse(_ markdown: String) -> [Self] {
        var blocks: [Self] = []
        var lines: [String] = []
        var fence: Character?
        var fenceLength = 0
        var isCode = false

        func flush() {
            let value = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { lines = []; return }
            let parsed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .full))
            var prose = ""
            var lastIdentity: Int?
            if let parsed {
                for run in parsed.runs where run.imageURL == nil {
                    let identity = run.presentationIntent?.components.first?.identity
                    if !prose.isEmpty, identity != lastIdentity { prose += "\n" }
                    prose += String(parsed[run.range].characters)
                    lastIdentity = identity
                }
            } else {
                prose = value
            }
            let hasLetters = prose.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            blocks.append(.init(markdown: value, text: !isCode && hasLetters ? prose : nil))
            lines = []
            isCode = false
        }

        for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = trimmed.first, marker == "`" || marker == "~" {
                let length = trimmed.prefix(while: { $0 == marker }).count
                if let active = fence {
                    lines.append(line)
                    if marker == active && length >= fenceLength {
                        fence = nil
                        flush()
                    }
                    continue
                } else if length >= 3 {
                    flush()
                    fence = marker
                    fenceLength = length
                    isCode = true
                }
            }
            if trimmed.isEmpty && fence == nil { flush() } else { lines.append(line) }
        }
        flush()
        return blocks
    }

    /// Bounds each request without splitting a Unicode grapheme or dropping text.
    static func chunks(_ text: String, limit: Int = 3000) -> [String] {
        precondition(limit > 0)
        var rest = text[...]
        var result: [String] = []
        while rest.count > limit {
            let end = rest.index(rest.startIndex, offsetBy: limit)
            let candidate = rest[..<end]
            let split = candidate.lastIndex(where: { $0.isWhitespace })
                .map { rest.index(after: $0) } ?? end
            result.append(String(rest[..<split]))
            rest = rest[split...]
        }
        if !rest.isEmpty { result.append(String(rest)) }
        return result
    }
}

/// An app-session LRU. Never serialized: relaunching the process starts empty.
/// A chapter occupies one slot, even if it is translated into another language.
@MainActor
final class BookTranslationCache {
    static let shared = BookTranslationCache()
    struct Entry {
        let source: String
        let target: String
        let blocks: [BookTranslationBlock]
        let translations: [String?]
    }
    private let capacity: Int
    private var entries: [ChapterIdentifier: Entry] = [:]
    private var recency: [ChapterIdentifier] = []
    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    init(capacity: Int = 10) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func value(for chapter: ChapterIdentifier, source: String, target: String, blocks: [BookTranslationBlock]) -> [String?]? {
        guard let entry = entries[chapter], entry.source == source, entry.target == target, entry.blocks == blocks else { return nil }
        return self.entry(for: chapter, source: source, target: target)?.translations
    }

    func entry(for chapter: ChapterIdentifier, source: String, target: String) -> Entry? {
        guard let entry = entries[chapter], entry.source == source, entry.target == target else { return nil }
        recency.removeAll { $0 == chapter }
        recency.append(chapter)
        return entry
    }

    func insert(_ entry: Entry, for chapter: ChapterIdentifier) {
        guard entry.blocks.count == entry.translations.count else { return }
        entries[chapter] = entry
        recency.removeAll { $0 == chapter }
        recency.append(chapter)
        while recency.count > capacity {
            entries.removeValue(forKey: recency.removeFirst())
        }
    }
}

/// A scroll anchor is a paragraph index plus the fraction traversed within it.
/// Mapping that anchor works even when translated paragraphs have different heights.
enum BookTranslationScrollPosition {
    static func anchor(offset: CGFloat, starts: [CGFloat], heights: [CGFloat]) -> Double {
        guard !starts.isEmpty, starts.count == heights.count else { return 0 }
        let index = starts.lastIndex(where: { $0 <= offset }) ?? 0
        let fraction = min(1, max(0, (offset - starts[index]) / max(1, heights[index])))
        return Double(index) + Double(fraction)
    }

    static func offset(anchor: Double, starts: [CGFloat], heights: [CGFloat]) -> CGFloat {
        guard anchor.isFinite, !starts.isEmpty, starts.count == heights.count else { return 0 }
        let bounded = min(Double(starts.count), max(0, anchor))
        let index = min(starts.count - 1, Int(bounded))
        return starts[index] + CGFloat(min(1, bounded - Double(index))) * heights[index]
    }
}
