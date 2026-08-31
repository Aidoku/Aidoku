//
//  ChapterIdentifier.swift
//  Aidoku
//
//  Created by Skitty on 10/24/25.
//

struct ChapterIdentifier: Hashable, Equatable, Codable, Sendable {
    let sourceKey: String
    let mangaKey: String
    let chapterKey: String

    var mangaIdentifier: MangaIdentifier {
        .init(sourceKey: sourceKey, mangaKey: mangaKey)
    }
}

extension ChapterIdentifier: CustomStringConvertible {
    var description: String {
        "\(sourceKey).\(mangaKey).\(chapterKey)"
    }
}
