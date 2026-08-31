//
//  MangaIdentifier.swift
//  Aidoku
//
//  Created by Skitty on 10/24/25.
//

struct MangaIdentifier: Hashable, Equatable, Codable, Sendable {
    let sourceKey: String
    let mangaKey: String
}

extension MangaIdentifier: CustomStringConvertible {
    var description: String {
        "\(sourceKey).\(mangaKey)"
    }
}
