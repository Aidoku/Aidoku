//
//  SourceInfo.swift
//  Aidoku
//
//  Created by Skitty on 12/30/22.
//

import Foundation

struct SourceInfo2: Hashable {
    let sourceId: String

    var iconUrl: URL?
    var name: String
    var lang: String
    var version: Int

    enum ContentRating: Int {
        case safe = 0
        case suggestive = 1
        case nsfw = 2
    }

    var contentRating: ContentRating

    var externalInfo: ExternalSourceInfo?
}
