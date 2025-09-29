//
//  ChapterTitleDisplayMode.swift
//  Aidoku
//
//  Created by Skitty on 9/29/25.
//

enum ChapterTitleDisplayMode: Int, CaseIterable {
    case `default` = 0
    case chapter = 1
    case volume = 2
}

extension ChapterTitleDisplayMode {
    var localizedTitle: String {
        switch self {
            case .default: NSLocalizedString("DISPLAY_DEFAULT")
            case .chapter: NSLocalizedString("DISPLAY_CHAPTER")
            case .volume: NSLocalizedString("DISPLAY_VOLUME")
        }
    }
}
