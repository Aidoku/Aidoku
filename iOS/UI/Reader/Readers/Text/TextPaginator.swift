//
//  TextPaginator.swift
//  Aidoku
//
//  Core pagination engine for breaking markdown text into discrete pages.
//  Calculates how much text fits on each page based on available space,
//  font settings, and line spacing.
//

import UIKit

/// Represents a single page of paginated text
struct TextPage: Identifiable, Equatable {
    let id: Int
    let attributedContent: NSAttributedString
    let markdownContent: String
    let range: NSRange  // Range in original text

    static func == (lhs: TextPage, rhs: TextPage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Configuration for text pagination
struct PaginationConfig {
    var fontSize: CGFloat = 16
    var fontName: String = "System"
    var lineSpacing: CGFloat = 6
    var paragraphSpacing: CGFloat = 12
    var horizontalPadding: CGFloat = 24
    var verticalPadding: CGFloat = 32

    var font: UIFont {
        if fontName == "San Francisco" || fontName == "System" {
            return UIFont.systemFont(ofSize: fontSize)
        }
        return UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        return style
    }

    var attributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.label
        ]
    }
}

/// Main pagination engine
class TextPaginator {
    private var config: PaginationConfig
    private var pageSize: CGSize = .zero

    init(config: PaginationConfig = PaginationConfig()) {
        self.config = config
    }

    /// Update pagination configuration
    func updateConfig(_ config: PaginationConfig) {
        self.config = config
    }

    /// Calculate the usable content area for a page
    func contentSize(for pageSize: CGSize) -> CGSize {
        CGSize(
            width: pageSize.width - (config.horizontalPadding * 2),
            height: pageSize.height - (config.verticalPadding * 2)
        )
    }

    /// Paginate markdown text into discrete pages
    /// - Parameters:
    ///   - markdown: The source markdown text
    ///   - pageSize: The available page size (full screen)
    /// - Returns: Array of TextPage objects
    func paginate(markdown: String, pageSize: CGSize) -> [TextPage] {
        self.pageSize = pageSize

        // Convert markdown to attributed string
        let attributedString = markdownToAttributedString(markdown)

        // Calculate content area
        let contentArea = contentSize(for: pageSize)

        // Paginate the attributed string
        return paginateAttributedString(attributedString, contentSize: contentArea, originalMarkdown: markdown)
    }

    /// Convert markdown to NSAttributedString using Apple's built-in CommonMark parser,
    /// then apply custom styling (fonts, paragraph styles, list formatting) from `config`.
    private func markdownToAttributedString(_ markdown: String) -> NSAttributedString {
        // Parse the full CommonMark document via Apple's AttributedString API
        guard let parsed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        ) else {
            // Fallback: plain text with base styling
            return NSAttributedString(string: markdown, attributes: config.attributes)
        }

        let result = NSMutableAttributedString()
        var lastBlockIdentity: Int?

        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let blockIntent = run.presentationIntent
            let inlineIntent = run.inlinePresentationIntent
            let currentIdentity = blockIntent?.components.first?.identity

            // Insert paragraph separator when the block changes
            if let current = currentIdentity, current != lastBlockIdentity, result.length > 0 {
                result.append(NSAttributedString(string: "\n", attributes: config.attributes))
            }

            // Determine block-level attributes
            var runAttrs = config.attributes
            if let intent = blockIntent {
                mergeBlockAttributes(into: &runAttrs, intent: intent)

                // Insert list bullet/number at the start of a new list item block
                if let current = currentIdentity, current != lastBlockIdentity {
                    if let bulletStr = listBulletString(for: intent) {
                        result.append(NSAttributedString(string: bulletStr, attributes: runAttrs))
                    }
                }
            }

            // Apply inline styling on top of block attributes
            if let inline = inlineIntent {
                mergeInlineAttributes(into: &runAttrs, intent: inline)
            }

            // Preserve hyperlinks
            if let link = run.link {
                runAttrs[.link] = link
            }

            result.append(NSAttributedString(string: text, attributes: runAttrs))
            lastBlockIdentity = currentIdentity
        }

        return result
    }

    // MARK: - Block Styling

    /// Merge block-level attributes (header, list, quote, code) into the given dictionary.
    private func mergeBlockAttributes(
        into attrs: inout [NSAttributedString.Key: Any],
        intent: PresentationIntent
    ) {
        for component in intent.components {
            switch component.kind {
            case .header(level: let level):
                mergeHeaderAttributes(into: &attrs, level: level)
            case .listItem:
                mergeListItemAttributes(into: &attrs)
            case .blockQuote:
                mergeBlockQuoteAttributes(into: &attrs)
            case .codeBlock:
                mergeCodeBlockAttributes(into: &attrs)
            default:
                break
            }
        }
    }

    /// Merge header attributes (scaled bold font, extra spacing).
    private func mergeHeaderAttributes(into attrs: inout [NSAttributedString.Key: Any], level: Int) {
        let sizeMultiplier: CGFloat = switch level {
        case 1: 1.75
        case 2: 1.5
        case 3: 1.25
        case 4: 1.15
        case 5: 1.1
        default: 1.05
        }

        let headerFontSize = config.fontSize * sizeMultiplier
        var headerFont: UIFont
        if config.fontName == "San Francisco" || config.fontName == "System" {
            headerFont = UIFont.systemFont(ofSize: headerFontSize, weight: .bold)
        } else {
            headerFont = UIFont(name: config.fontName, size: headerFontSize)
                ?? UIFont.systemFont(ofSize: headerFontSize)
            if let boldDescriptor = headerFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                headerFont = UIFont(descriptor: boldDescriptor, size: headerFontSize)
            }
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = config.lineSpacing
        style.paragraphSpacingBefore = config.paragraphSpacing
        style.paragraphSpacing = config.paragraphSpacing / 2

        attrs[.font] = headerFont
        attrs[.paragraphStyle] = style
    }

    /// Merge list item attributes (hanging indent, tab stops).
    private func mergeListItemAttributes(into attrs: inout [NSAttributedString.Key: Any]) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = config.lineSpacing
        style.headIndent = config.fontSize * 1.5
        style.firstLineHeadIndent = 0
        style.paragraphSpacing = config.paragraphSpacing / 3
        style.tabStops = [NSTextTab(textAlignment: .left, location: config.fontSize * 1.5)]

        attrs[.paragraphStyle] = style
    }

    /// Return the bullet/number prefix for a list item, or nil if the intent is not a list item.
    private func listBulletString(for intent: PresentationIntent) -> String? {
        for component in intent.components {
            if case .listItem(ordinal: let ordinal) = component.kind {
                let isOrdered = intent.components.contains { $0.kind == .orderedList }
                return isOrdered ? "\(ordinal).\t" : "\u{2022}\t"
            }
        }
        return nil
    }

    /// Merge block quote attributes (indentation, secondary color).
    private func mergeBlockQuoteAttributes(into attrs: inout [NSAttributedString.Key: Any]) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = config.lineSpacing
        style.headIndent = config.fontSize * 1.5
        style.firstLineHeadIndent = config.fontSize * 1.5
        style.paragraphSpacing = config.paragraphSpacing

        attrs[.paragraphStyle] = style
        attrs[.foregroundColor] = UIColor.secondaryLabel
    }

    /// Merge code block attributes (monospace font, indentation).
    private func mergeCodeBlockAttributes(into attrs: inout [NSAttributedString.Key: Any]) {
        let monoFont = UIFont.monospacedSystemFont(ofSize: config.fontSize * 0.9, weight: .regular)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = config.lineSpacing * 0.75
        style.paragraphSpacing = config.paragraphSpacing
        style.headIndent = config.fontSize * 0.75
        style.firstLineHeadIndent = config.fontSize * 0.75

        attrs[.font] = monoFont
        attrs[.paragraphStyle] = style
        attrs[.foregroundColor] = UIColor.secondaryLabel
    }

    // MARK: - Inline Styling

    /// Merge inline attributes (bold, italic, code, strikethrough) into the given dictionary.
    private func mergeInlineAttributes(
        into attrs: inout [NSAttributedString.Key: Any],
        intent: InlinePresentationIntent
    ) {
        var font = (attrs[.font] as? UIFont) ?? config.font
        var traits: UIFontDescriptor.SymbolicTraits = []

        if intent.contains(.stronglyEmphasized) {
            traits.insert(.traitBold)
        }
        if intent.contains(.emphasized) {
            traits.insert(.traitItalic)
        }

        if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: font.pointSize)
        }

        if intent.contains(.code) {
            font = UIFont.monospacedSystemFont(ofSize: config.fontSize * 0.9, weight: .regular)
        }

        attrs[.font] = font

        if intent.contains(.strikethrough) {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
    }

    /// Split attributed string into pages based on available height
    private func paginateAttributedString(
        _ attributedString: NSAttributedString,
        contentSize: CGSize,
        originalMarkdown: String
    ) -> [TextPage] {
        var pages: [TextPage] = []
        let fullLength = attributedString.length
        var currentLocation = 0
        var pageIndex = 0

        // Ensure we have valid content size
        guard contentSize.width > 50 && contentSize.height > 50 else {
            // Return entire text as single page if size is invalid
            let page = TextPage(
                id: 0,
                attributedContent: attributedString,
                markdownContent: originalMarkdown,
                range: NSRange(location: 0, length: fullLength)
            )
            return [page]
        }

        while currentLocation < fullLength {
            // Create fresh text storage with remaining text
            let remainingRange = NSRange(location: currentLocation, length: fullLength - currentLocation)
            let remainingText = attributedString.attributedSubstring(from: remainingRange)

            let textStorage = NSTextStorage(attributedString: remainingText)
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(size: contentSize)

            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = .byWordWrapping

            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)

            // Force layout
            layoutManager.ensureLayout(for: textContainer)

            // Get the glyph range that fits in this container
            let glyphRange = layoutManager.glyphRange(for: textContainer)

            if glyphRange.length == 0 {
                break
            }

            // Convert glyph range to character range
            var actualGlyphRange = NSRange()
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: &actualGlyphRange)

            // Adjust for the offset we're at
            let absoluteRange = NSRange(location: currentLocation + characterRange.location, length: characterRange.length)

            // Try to break at a paragraph or sentence boundary
            let adjustedRange = adjustRangeToBreakPoint(
                attributedString: attributedString,
                proposedRange: absoluteRange
            )

            // Extract the page content
            let pageContent = attributedString.attributedSubstring(from: adjustedRange)
            let markdownSlice = extractMarkdownSlice(from: originalMarkdown, range: adjustedRange)

            let page = TextPage(
                id: pageIndex,
                attributedContent: pageContent,
                markdownContent: markdownSlice,
                range: adjustedRange
            )
            pages.append(page)

            // Move to next page
            currentLocation = adjustedRange.location + adjustedRange.length
            pageIndex += 1

            // Safety check to prevent infinite loops
            if pageIndex > 10000 {
                break
            }
        }

        // Ensure we have at least one page
        if pages.isEmpty && fullLength > 0 {
            let page = TextPage(
                id: 0,
                attributedContent: attributedString,
                markdownContent: originalMarkdown,
                range: NSRange(location: 0, length: fullLength)
            )
            pages.append(page)
        }

        return pages
    }

    /// Adjust range to break at a clean boundary without wasting too much space.
    /// Only searches the last portion of the page to keep pages consistently full.
    private func adjustRangeToBreakPoint(
        attributedString: NSAttributedString,
        proposedRange: NSRange
    ) -> NSRange {
        let text = attributedString.string as NSString
        let endLocation = proposedRange.location + proposedRange.length

        // If we're at the end of the text, use the proposed range
        if endLocation >= text.length {
            return proposedRange
        }

        // Only search the last 15% of the page for clean break points.
        // This keeps pages consistently full while still avoiding mid-word breaks.
        let minBreakLocation = proposedRange.location + (proposedRange.length * 85) / 100
        let searchRange = NSRange(
            location: minBreakLocation,
            length: endLocation - minBreakLocation
        )

        guard searchRange.length > 0 else { return proposedRange }

        // Try to find paragraph break (newline) in the tail
        let paragraphBreak = text.rangeOfCharacter(
            from: CharacterSet.newlines,
            options: .backwards,
            range: searchRange
        )

        if paragraphBreak.location != NSNotFound {
            return NSRange(location: proposedRange.location, length: paragraphBreak.location - proposedRange.location + 1)
        }

        // Try to find sentence break (. ! ?) in the tail
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        let sentenceBreak = text.rangeOfCharacter(
            from: sentenceEnders,
            options: .backwards,
            range: searchRange
        )

        if sentenceBreak.location != NSNotFound {
            let breakEnd = min(sentenceBreak.location + 2, text.length)
            return NSRange(location: proposedRange.location, length: breakEnd - proposedRange.location)
        }

        // Try to find word break (space) in the tail
        let wordBreak = text.rangeOfCharacter(
            from: CharacterSet.whitespaces,
            options: .backwards,
            range: searchRange
        )

        if wordBreak.location != NSNotFound {
            return NSRange(location: proposedRange.location, length: wordBreak.location - proposedRange.location + 1)
        }

        // No good break point found, use proposed range
        return proposedRange
    }

    /// Extract markdown slice corresponding to character range
    private func extractMarkdownSlice(from markdown: String, range: NSRange) -> String {
        // This is a simplified extraction - in a full implementation,
        // we'd maintain a mapping between attributed string ranges and original markdown
        guard let stringRange = Range(range, in: markdown) else {
            // If range conversion fails, return empty string
            // This can happen if markdown was transformed during attribution
            return ""
        }
        return String(markdown[stringRange])
    }
}

// MARK: - Pagination Result
extension TextPaginator {
    /// Result of pagination with metadata
    struct PaginationResult {
        let pages: [TextPage]
        let totalCharacters: Int
        let config: PaginationConfig
        let pageSize: CGSize

        var pageCount: Int { pages.count }
        var isEmpty: Bool { pages.isEmpty }
    }

    /// Paginate with full result metadata
    func paginateWithMetadata(markdown: String, pageSize: CGSize) -> PaginationResult {
        let pages = paginate(markdown: markdown, pageSize: pageSize)
        return PaginationResult(
            pages: pages,
            totalCharacters: markdown.count,
            config: config,
            pageSize: pageSize
        )
    }
}
