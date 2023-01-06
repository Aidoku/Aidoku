//
//  MigrationStrategy.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/5/23.
//

import Foundation

enum MigrationStrategory: CaseIterable {
    case firstAlternative
    case mostChapters

    func toString() -> String {
        switch self {
        case .firstAlternative: return NSLocalizedString("FIRST_ALTERNATIVE", comment: "")
        case .mostChapters: return NSLocalizedString("MOST_CHAPTERS_SLOWER", comment: "")
        }
    }
}
