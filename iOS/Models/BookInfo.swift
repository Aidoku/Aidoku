//
//  BookInfo.swift
//  Aidoku (iOS)
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

//    init(
//        bookId: String,
//        sourceId: String,
//        coverUrl: URL? = nil,
//        title: String? = nil,
//        author: String? = nil,
//        unread: Int = 0,
//    ) {
//        self.bookId = bookId
//        self.sourceId = sourceId
//        self.coverUrl = coverUrl
//        self.title = title
//        self.author = author
//        self.unread = unread
//    }

    func toBook() -> Book {
        Book(sourceId: sourceId, id: bookId, title: title, author: author, coverUrl: coverUrl?.absoluteString, url: url?.absoluteString)
    }
}
