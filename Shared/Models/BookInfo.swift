//
//  BookInfo.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/7/22.
//

import Foundation

struct BookInfo: Hashable, Equatable {
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

    static func == (lhs: BookInfo, rhs: BookInfo) -> Bool {
        lhs.bookId == rhs.bookId && lhs.sourceId == rhs.sourceId
    }
}
