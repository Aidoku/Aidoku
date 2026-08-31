//
//  FuriganaText.swift
//  Aidoku
//
//  Created by skitty on 7/20/26.
//

import SwiftUI

struct FuriganaText: View {
    let expression: String
    let reading: String?

    var expressionFont: Font = .body
    var readingFont: Font = .system(size: 9)
    var spacing: CGFloat = 0

    private let segments: [FuriganaSegment]

    init(expression: String, reading: String?) {
        self.expression = expression
        self.reading = reading
        self.segments = FuriganaParser.segment(
            expression: expression,
            reading: reading
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(segments) { segment in
                if let reading = segment.reading, !reading.isEmpty {
                    VStack(spacing: 0) {
                        Text(reading)
                            .font(readingFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Text(segment.text)
                            .font(expressionFont)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text(segment.text)
                        .font(expressionFont)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L182

private struct FuriganaSegment: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let reading: String?
}

private enum FuriganaParser {
    private struct Group {
        let text: String
        let isKana: Bool

        var normalizedText: String {
            text.toHiragana()
        }
    }

    static func segment(
        expression: String,
        reading: String?
    ) -> [FuriganaSegment] {
        guard
            let reading,
            !reading.isEmpty,
            reading != expression
        else {
            return [.init(text: expression, reading: nil)]
        }

        let groups = makeGroups(from: expression)

        guard let result = segmentize(
            reading: reading,
            normalizedReading: reading.toHiragana(),
            groups: groups,
            groupIndex: 0
        ) else {
            // place reading over entire expression if segmentation fails
            return [.init(text: expression, reading: reading)]
        }

        return result
    }

    private static func makeGroups(from expression: String) -> [Group] {
        guard let first = expression.first else {
            return []
        }

        var groups: [Group] = []
        var current = String(first)
        var currentIsKana = first.isKana

        for character in expression.dropFirst() {
            let isKana = character.isKana

            if isKana == currentIsKana {
                current.append(character)
            } else {
                groups.append(.init(text: current, isKana: currentIsKana))

                current = String(character)
                currentIsKana = isKana
            }
        }

        groups.append(.init(text: current, isKana: currentIsKana))

        return groups
    }

    private static func segmentize(
        reading: String,
        normalizedReading: String,
        groups: [Group],
        groupIndex: Int
    ) -> [FuriganaSegment]? {
        guard groupIndex < groups.count else {
            return reading.isEmpty ? [] : nil
        }

        let group = groups[groupIndex]

        if group.isKana {
            let normalizedText = group.normalizedText

            guard normalizedReading.hasPrefix(normalizedText) else {
                return nil
            }

            let consumedCount = normalizedText.count

            guard
                let remainingReading = reading.droppingFirst(consumedCount),
                let remainingNormalized = normalizedReading.droppingFirst(consumedCount),
                var segments = segmentize(
                    reading: remainingReading,
                    normalizedReading: remainingNormalized,
                    groups: groups,
                    groupIndex: groupIndex + 1
                )
            else {
                return nil
            }

            let consumedReading = reading.prefixCharacters(consumedCount)

            if consumedReading == group.text {
                segments.insert(.init(text: group.text, reading: nil), at: 0)
            } else {
                segments.insert(
                    contentsOf: segmentKana(
                        text: group.text,
                        reading: consumedReading
                    ),
                    at: 0
                )
            }

            return segments
        }

        var result: [FuriganaSegment]?
        let remainingGroupCount = groups.count - groupIndex

        for consumedCount in stride(
            from: reading.count,
            through: group.text.count,
            by: -1
        ) {
            guard
                let remainingReading = reading.droppingFirst(consumedCount),
                let remainingNormalized = normalizedReading.droppingFirst(consumedCount),
                var tail = segmentize(
                    reading: remainingReading,
                    normalizedReading: remainingNormalized,
                    groups: groups,
                    groupIndex: groupIndex + 1
                )
            else {
                continue
            }

            if result != nil {
                return nil
            }

            let segmentReading = reading.prefixCharacters(consumedCount)

            tail.insert(.init(text: group.text, reading: segmentReading), at: 0)

            result = tail

            if remainingGroupCount == 1 {
                break
            }
        }

        return result
    }

    private static func segmentKana(
        text: String,
        reading: String
    ) -> [FuriganaSegment] {
        let textCharacters = Array(text)
        let readingCharacters = Array(reading)

        guard textCharacters.count == readingCharacters.count else {
            return [.init(text: text, reading: reading)]
        }

        var segments: [FuriganaSegment] = []
        var start = 0
        var matches = textCharacters[0] == readingCharacters[0]

        for index in 1..<textCharacters.count {
            let newMatches = textCharacters[index] == readingCharacters[index]

            guard newMatches != matches else {
                continue
            }

            appendKanaSegment(
                to: &segments,
                text: textCharacters,
                reading: readingCharacters,
                range: start..<index,
                matches: matches
            )

            start = index
            matches = newMatches
        }

        appendKanaSegment(
            to: &segments,
            text: textCharacters,
            reading: readingCharacters,
            range: start..<textCharacters.count,
            matches: matches
        )

        return segments
    }

    private static func appendKanaSegment(
        to segments: inout [FuriganaSegment],
        text: [Character],
        reading: [Character],
        range: Range<Int>,
        matches: Bool
    ) {
        let textPart = String(text[range])
        let readingPart = String(reading[range])

        segments.append(.init(text: textPart, reading: matches ? nil : readingPart))
    }
}

private extension Character {
    var isKana: Bool {
        unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
                case 0x3040...0x309F: // hiragana
                    return true
                case 0x30A0...0x30FF: // katakana
                    return true
                case 0xFF66...0xFF9F: // half-width katakana
                    return true
                default:
                    return false
            }
        }
    }
}

private extension String {
    func toHiragana() -> String {
        String(
            unicodeScalars.map { scalar in
                let value = scalar.value
                if (0x30A1...0x30F6).contains(value), let converted = UnicodeScalar(value - 0x60) {
                    return Character(converted)
                }
                return Character(scalar)
            }
        )
    }

    func prefixCharacters(_ count: Int) -> String {
        String(prefix(count))
    }

    func droppingFirst(_ count: Int) -> String? {
        guard count <= self.count else {
            return nil
        }
        return String(dropFirst(count))
    }
}
