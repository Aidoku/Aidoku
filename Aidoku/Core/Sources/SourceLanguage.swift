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

    static func preferredCodes() -> Set<String> {
        Set([multi] + Locale.preferredLanguages.map(normalized))
    }

    static func compare(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
        compare(primaryCode(for: lhs), primaryCode(for: rhs))
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
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

        let lhsName = displayName(for: lhs)
        let rhsName = displayName(for: rhs)

        let result = lhsName.localizedCaseInsensitiveCompare(rhsName)

        if result == .orderedSame {
            return lhs.localizedCaseInsensitiveCompare(rhs)
        }

        return result
    }

    static func displayName(for code: String) -> String {
        if normalized(code) == multi {
            return NSLocalizedString("MULTI_LANGUAGE")
        }
        return Locale.current.localizedString(forIdentifier: code) ?? code
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
