//
//  ChapterFlagMask.swift
//  Aidoku
//
//  Created by Skitty on 2/14/24.
//

import Foundation

// chapter flags are stored in an int16
// ascending:     0b0000000000000001
// sort:          0b0000000000001110 (only 3 options are used, but we have room for more in the future)
// dwnld filter:  0b0000000000110000
// unread filter: 0b0000000011000000
struct ChapterFlagMask {
    static let sortAscending: Int = 1
    static let sortMethod: Int = 0b1110
    static let downloadFilterEnabled: Int = 1 << 4
    static let downloadFilterExcluded: Int = 1 << 5
    static let unreadFilterEnabled: Int = 1 << 6
    static let unreadFilterExcluded: Int = 1 << 7
}
