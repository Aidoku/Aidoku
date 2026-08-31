//
//  SourceInfo.swift
//  Aidoku
//
//  Created by Skitty on 12/30/22.
//

import Foundation
import AidokuRunner

struct SourceInfo: Hashable {
    let sourceId: String

    var iconUrl: URL?
    var name: String
    var altNames: [String] = []
    var languages: [String]
    var version: Int
    var contentRating: SourceContentRating
    var disabled: Bool = false
    var external: Bool = true

    var externalInfo: ExternalSourceInfo?

    var isMultiLanguage: Bool {
        languages.isEmpty || languages.count > 1 || languages.first == "multi"
    }
}
