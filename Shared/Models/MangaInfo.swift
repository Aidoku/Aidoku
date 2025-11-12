//
//  MangaInfo.swift
//  Aidoku
//
//  Created by Skitty on 8/7/22.
//

import Foundation

struct MangaInfo: Hashable, Sendable {
    var identifier: MangaIdentifier { .init(sourceKey: sourceId, mangaKey: mangaId) }

    let mangaId: String
    let sourceId: String

    var coverUrl: URL?
    var title: String?
    var author: String?

    var url: URL?

    var unread: Int = 0
    var downloads: Int = 0

    func toManga() -> Manga {
        Manga(
            sourceId: sourceId,
            id: mangaId,
            title: title,
            author: author,
            coverUrl: coverUrl,
            url: url
        )
    }
}
