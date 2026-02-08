//
//  TextPaginator.swift
//  Aidoku
//
//  Created by Minirob on 2/2/26.
//
//  Core pagination engine for breaking markdown text into discrete pages.
//  Calculates how much text fits on each page based on available space,
//  font settings, and line spacing.
//

import UIKit
import MarkdownUI

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
    var fontSize: CGFloat = 18
    var fontName: String = "Georgia"
    var lineSpacing: CGFloat = 8
    var paragraphSpacing: CGFloat = 16
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
@MainActor
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
    
    /// Convert markdown to NSAttributedString with proper styling
    private func markdownToAttributedString(_ markdown: String) -> NSAttributedString {
        // Simple markdown conversion - for complex markdown, we'd use a proper parser
        // This handles basic formatting while preserving readable text
        let result = NSMutableAttributedString()
        
        // Process line by line to handle headers, etc.
        let lines = markdown.components(separatedBy: "\n")
        
        for (index, line) in lines.enumerated() {
            var processedLine = line
            var lineAttributes = config.attributes
            
            // Handle headers
            if line.hasPrefix("### ") {
                processedLine = String(line.dropFirst(4))
                lineAttributes[.font] = UIFont.boldSystemFont(ofSize: config.fontSize * 1.1)
            } else if line.hasPrefix("## ") {
                processedLine = String(line.dropFirst(3))
                lineAttributes[.font] = UIFont.boldSystemFont(ofSize: config.fontSize * 1.3)
            } else if line.hasPrefix("# ") {
                processedLine = String(line.dropFirst(2))
                lineAttributes[.font] = UIFont.boldSystemFont(ofSize: config.fontSize * 1.5)
            }
            
            // Handle bold **text**
            processedLine = processedLine.replacingOccurrences(
                of: "\\*\\*(.+?)\\*\\*",
                with: "$1",
                options: .regularExpression
            )
            
            // Handle italic *text* or _text_
            processedLine = processedLine.replacingOccurrences(
                of: "\\*(.+?)\\*",
                with: "$1",
                options: .regularExpression
            )
            processedLine = processedLine.replacingOccurrences(
                of: "_(.+?)_",
                with: "$1",
                options: .regularExpression
            )
            
            // Handle horizontal rules
            if line.trimmingCharacters(in: .whitespaces) == "---" ||
               line.trimmingCharacters(in: .whitespaces) == "***" {
                processedLine = "\n────────────────\n"
            }
            
            let attributedLine = NSAttributedString(string: processedLine, attributes: lineAttributes)
            result.append(attributedLine)
            
            // Add newline between lines (except for last line)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: config.attributes))
            }
        }
        
        return result
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
    
    /// Adjust range to break at paragraph or sentence boundary
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
        
        // Look backwards for a good break point (paragraph > sentence > word)
        let searchRange = NSRange(location: proposedRange.location, length: proposedRange.length)
        
        // Try to find paragraph break (double newline or single newline)
        let paragraphBreak = text.rangeOfCharacter(
            from: CharacterSet.newlines,
            options: .backwards,
            range: searchRange
        )
        
        if paragraphBreak.location != NSNotFound && paragraphBreak.location > proposedRange.location + proposedRange.length / 2 {
            // Found a paragraph break in the latter half of the page
            return NSRange(location: proposedRange.location, length: paragraphBreak.location - proposedRange.location + 1)
        }
        
        // Try to find sentence break (. ! ?)
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        let sentenceBreak = text.rangeOfCharacter(
            from: sentenceEnders,
            options: .backwards,
            range: searchRange
        )
        
        if sentenceBreak.location != NSNotFound && sentenceBreak.location > proposedRange.location + proposedRange.length / 3 {
            // Found a sentence break - include one character after (space) if possible
            let breakEnd = min(sentenceBreak.location + 2, text.length)
            return NSRange(location: proposedRange.location, length: breakEnd - proposedRange.location)
        }
        
        // Try to find word break (space)
        let wordBreak = text.rangeOfCharacter(
            from: CharacterSet.whitespaces,
            options: .backwards,
            range: searchRange
        )
        
        if wordBreak.location != NSNotFound && wordBreak.location > proposedRange.location {
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

