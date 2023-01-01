//
//  BookInfo.swift
//  Aidoku
//
//  Created by Skitty on 8/7/22.
//

import Foundation

struct BookInfo: Hashable {
    let bookId: String
    let sourceId: String

    var coverUrl: URL?
    var title: String?
    var author: String?

    var url: URL?

    var unread: Int = 0

    func toBook() -> Book {
        Book(sourceId: sourceId, id: bookId, title: title, author: author, coverUrl: coverUrl, url: url)
    }
}
