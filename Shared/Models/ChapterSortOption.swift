//
//  ChapterSortOption.swift
//  Aidoku
//
//  Created by Skitty on 2/14/24.
//

import Foundation

enum ChapterSortOption: Int, CaseIterable {
    case sourceOrder = 0
    case chapter
    case uploadDate

    init(flags: Int) {
        let option = (flags & ChapterFlagMask.sortMethod) >> 1
        self = ChapterSortOption(rawValue: option) ?? .sourceOrder
    }

    var stringValue: String {
        switch self {
        case .sourceOrder: NSLocalizedString("SOURCE_ORDER", comment: "")
        case .chapter: NSLocalizedString("CHAPTER", comment: "")
        case .uploadDate: NSLocalizedString("UPLOAD_DATE", comment: "")
        }
    }
}
