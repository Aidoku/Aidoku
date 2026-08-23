//
//  EditedKeys.swift
//  Aidoku
//
//  Created by Skitty on 7/28/25.
//

import Foundation

struct EditedKeys: OptionSet {
    let rawValue: Int32

    static let title = Self(rawValue: 1 << 0)
    static let authors = Self(rawValue: 1 << 1)
    static let artists = Self(rawValue: 1 << 2)
    static let description = Self(rawValue: 1 << 3)
    static let tags = Self(rawValue: 1 << 4)
    static let cover = Self(rawValue: 1 << 5)
    static let url = Self(rawValue: 1 << 6)
    static let status = Self(rawValue: 1 << 7)
    static let contentRating = Self(rawValue: 1 << 8)
    static let viewer = Self(rawValue: 1 << 9)
    static let neverUpdate = Self(rawValue: 1 << 10)
}
