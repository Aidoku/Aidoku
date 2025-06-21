//
//  ChapterFilterOption.swift
//  Aidoku
//
//  Created by Skitty on 2/14/24.
//

import Foundation

struct ChapterFilterOption: Hashable {
    var type: ChapterFilterMethod
    var exclude: Bool

    static func parseOptions(flags: Int) -> [ChapterFilterOption] {
        let downloaded = flags & ChapterFlagMask.downloadFilterEnabled != 0
        let unread = flags & ChapterFlagMask.unreadFilterEnabled != 0
        let locked = flags & ChapterFlagMask.lockedFilterEnabled != 0
        var result: [ChapterFilterOption] = []
        if downloaded {
            result.append(.init(type: .downloaded, exclude: flags & ChapterFlagMask.downloadFilterExcluded != 0))
        }
        if unread {
            result.append(.init(type: .unread, exclude: flags & ChapterFlagMask.unreadFilterExcluded != 0))
        }
        if locked {
            result.append(.init(type: .locked, exclude: flags & ChapterFlagMask.lockedFilterExcluded != 0))
        }
        return result
    }
}

enum ChapterFilterMethod: CaseIterable, Hashable {
    case downloaded
    case unread
    case locked

    var stringValue: String {
        switch self {
            case .downloaded: NSLocalizedString("DOWNLOADED", comment: "")
            case .unread: NSLocalizedString("UNREAD", comment: "")
            case .locked: NSLocalizedString("LOCKED", comment: "")
        }
    }
}
