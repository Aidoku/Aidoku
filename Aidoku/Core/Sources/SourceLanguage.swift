//
//  SourceLanguage.swift
//  Aidoku
//
//  Created by skitty on 8/25/26.
//

import Foundation

enum SourceLanguage {
    static let multi = "multi"

    static func primaryCode(for languages: [String]) -> String {
        languages.count == 1 ? languages[0] : multi
    }

    static func compare(
        _ lhs: [String],
        _ rhs: [String],
        preferredCodes: [String] = []
    ) -> ComparisonResult {
        compare(primaryCode(for: lhs), primaryCode(for: rhs), preferredCodes: preferredCodes)
    }

    static func compare(
        _ lhs: String,
        _ rhs: String,
        preferredCodes: [String] = []
    ) -> ComparisonResult {
        let lhs = normalized(lhs)
        let rhs = normalized(rhs)

        if lhs == rhs {
            return .orderedSame
        }

        if lhs == multi {
            return .orderedAscending
        }
        if rhs == multi {
            return .orderedDescending
        }

        let preferredCodes = unique(
            preferredCodes.map(normalized)
                + Locale.preferredLanguages.map(normalized)
        )

        let lhsPriority = preferredCodes.firstIndex(of: lhs)
        let rhsPriority = preferredCodes.firstIndex(of: rhs)

        switch (lhsPriority, rhsPriority) {
            case let (lhsPriority?, rhsPriority?):
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                        ? .orderedAscending
                        : .orderedDescending
                }

            case (.some, nil):
                return .orderedAscending

            case (nil, .some):
                return .orderedDescending

            case (nil, nil):
                break
        }

        let lhsName = Locale.current.localizedString(forIdentifier: lhs) ?? lhs
        let rhsName = Locale.current.localizedString(forIdentifier: rhs) ?? rhs

        return lhsName.localizedCaseInsensitiveCompare(rhsName)
    }

    static func normalized(_ code: String) -> String {
        guard code.lowercased() != multi else {
            return multi
        }

        return Locale(
            identifier: code.replacingOccurrences(of: "-", with: "_")
        )
        .languageCode?
        .lowercased() ?? code.lowercased()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()

        return values.filter {
            seen.insert($0).inserted
        }
    }
}
