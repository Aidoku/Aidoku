//
//  Manga.swift
//  Aidoku
//
//  Created by Skitty on 12/20/21.
//

import Foundation

struct Manga: Hashable, Codable {
    let provider: String
    let id: String
    
    var title: String?
    var author: String?
    var artist: String?
    
    var description: String?
    var categories: [String]?
    
    var thumbnailURL: String?
    
    init(
        provider: String,
        id: String,
        title: String? = nil,
        author: String? = nil,
        artist: String? = nil,
        description: String? = nil,
        categories: [String]? = nil,
        thumbnailURL: String? = nil
    ) {
        self.provider = provider
        self.id = id
        self.title = title
        self.author = author
        self.artist = artist
        self.description = description
        self.categories = categories
        self.thumbnailURL = thumbnailURL
    }
    
    func copy(from manga: Manga) -> Manga {
        Manga(
            provider: manga.provider,
            id: manga.id,
            title: manga.title,
            author: manga.author ?? self.author,
            artist: manga.artist ?? self.artist,
            description: manga.description ?? self.description,
            categories: manga.categories ?? self.categories,
            thumbnailURL: manga.thumbnailURL ?? self.thumbnailURL)
    }
}

struct MangaPageResult {
    let manga: [Manga]
    let hasNextPage: Bool
}
