//
//  Page.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation
import AidokuRunner

struct Page: Hashable {

    enum PageType: Int {
        case imagePage
        case prevInfoPage
        case nextInfoPage
    }

    var type: PageType = .imagePage
    var sourceId: String
    var chapterId: String
    var index: Int = 0
    var imageURL: String?
    var base64: String?
    var text: String?
    var zipURL: String?

    var context: PageContext?
    var hasDescription: Bool = false
    var description: String?

    var key: String {
        "\(chapterId)|\(index)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chapterId)
        hasher.combine(index)
    }
}

extension Page {
    func toNew() -> AidokuRunner.Page {
        let content: AidokuRunner.PageContent = if let imageURL, let url = URL(string: imageURL) {
            .url(url: url, context: nil)
        } else if let text {
            .text(text)
        } else {
            .text("Invalid URL")
        }
        return AidokuRunner.Page(
            content: content,
            hasDescription: hasDescription,
            description: description
        )
    }
}
