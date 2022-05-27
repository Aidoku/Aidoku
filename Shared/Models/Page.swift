//
//  Page.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation

struct Page: Hashable {
    let index: Int
    let imageURL: String?
    let base64: String?
    let text: String?

    var key: String {
        // using the full base64 string as a key slows stuff down because it's so large, so hopefully this is unique enough
        String(index)
    }
}
