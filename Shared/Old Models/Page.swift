//
//  Page.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation

struct Page: Hashable {

    enum PageType: Int {
        case imagePage
        case prevInfoPage
        case nextInfoPage
    }

    var type: PageType = .imagePage
    var sourceId: String
    var chapterId: String
    var index: Int
    var imageURL: String?
    var base64: String?
    var text: String?

    var key: String {
        "\(chapterId)|\(index)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chapterId)
        hasher.combine(index)
    }
}
