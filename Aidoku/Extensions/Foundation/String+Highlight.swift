//
//  String+Highlight.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import Foundation

extension String {
    func highlight(text: String) -> AttributedString {
        var attributedString = AttributedString(self)
        let ranges = ranges(of: text, options: [.caseInsensitive, .diacriticInsensitive])

        attributedString.backgroundColor = .clear
        for range in ranges {
            if let attributedRange = range.attributedRange(for: attributedString) {
                attributedString[attributedRange].backgroundColor = .accentColor.opacity(0.2)
            }
        }

        return attributedString
    }
}

private extension Range<String.Index> {
    func attributedRange(for attributedString: AttributedString) -> Range<AttributedString.Index>? {
        let start = AttributedString.Index(lowerBound, within: attributedString)
        let end = AttributedString.Index(upperBound, within: attributedString)
        guard let start, let end else { return nil }
        return start..<end
    }
}

/// https://stackoverflow.com/a/32306142/14351818
private extension StringProtocol {
    func ranges<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Range<Index>] {
        var result: [Range<Index>] = []
        var startIndex = self.startIndex
        while
            startIndex < endIndex,
            let range = self[startIndex...].range(of: string, options: options)
        {
            result.append(range)
            startIndex = range.lowerBound < range.upperBound ? range.upperBound :
                index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return result
    }
}
