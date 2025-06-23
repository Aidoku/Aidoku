//
//  SourceInfo.swift
//  Aidoku
//
//  Created by Skitty on 12/30/22.
//

import Foundation
import AidokuRunner

struct SourceInfo2: Hashable {
    let sourceId: String

    var iconUrl: URL?
    var name: String
    var altNames: [String] = []
    var languages: [String]
    var version: Int

    var contentRating: SourceContentRating

    var externalInfo: ExternalSourceInfo?

    var isMultiLanguage: Bool {
        languages.isEmpty || languages.count > 1 || languages.first == "multi"
    }
}
