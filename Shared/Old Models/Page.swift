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
    var index: Int
    var imageURL: String?
    var base64: String?
    var text: String?

    var key: String {
        // using the full base64 string as a key slows stuff down because it's so large, so hopefully this is unique enough
        imageURL ?? (base64 != nil ? String(index) + (base64?.take(first: 10) ?? "") + (base64?.take(last: 20) ?? "") : nil) ?? String(index)
    }
}
