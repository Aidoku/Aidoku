//
//  SemanticVersion.swift
//  Aidoku
//
//  Created by Skitty on 12/31/22.
//

import Foundation

class SemanticVersion {

    private var components: [String]

    init(_ string: String) {
        components = string.components(separatedBy: ".")
    }

    private func compare(to targetVersion: SemanticVersion) -> ComparisonResult {
        var result: ComparisonResult = .orderedSame
        var versionComponents = components
        var targetComponents = targetVersion.components

        while versionComponents.count < targetComponents.count {
            versionComponents.append("0")
        }

        while targetComponents.count < versionComponents.count {
            targetComponents.append("0")
        }

        for (version, target) in zip(versionComponents, targetComponents) {
            result = version.compare(target, options: .numeric)
            if result != .orderedSame {
                break
            }
        }

        return result
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool { lhs.compare(to: rhs) == .orderedSame }
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool { lhs.compare(to: rhs) == .orderedAscending }
    static func <= (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool { lhs.compare(to: rhs) != .orderedDescending }
    static func > (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool { lhs.compare(to: rhs) == .orderedDescending }
    static func >= (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool { lhs.compare(to: rhs) != .orderedAscending }
}
