//
//  Manga.swift
//  Aidoku
//
//  Created by Skitty on 12/20/21.
//

import Foundation

enum MangaStatus: Int, Codable {
    case unknown = 0
    case ongoing = 1
    case completed = 2
    case cancelled = 3
    case hiatus = 4
}

struct Manga: Hashable, Codable, KVCObject {
    let provider: String
    let id: String
    
    var title: String?
    var author: String?
    var artist: String?
    
    var description: String?
    var categories: [String]?
    
    var status: MangaStatus
    
    var thumbnailURL: String?
    
    init(
        provider: String,
        id: String,
        title: String? = nil,
        author: String? = nil,
        artist: String? = nil,
        description: String? = nil,
        categories: [String]? = nil,
        status: MangaStatus = .unknown,
        thumbnailURL: String? = nil
    ) {
        self.provider = provider
        self.id = id
        self.title = title
        self.author = author
        self.artist = artist
        self.description = description
        self.categories = categories
        self.status = status
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
    
    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "id": return id
        case "title": return title
        case "author": return author
        case "artist": return artist
        case "description": return description
        case "categories": return categories
        case "status": return status.rawValue
        case "cover_url": return thumbnailURL
        default: return nil
        }
    }
}

struct MangaPageResult {
    let manga: [Manga]
    let hasNextPage: Bool
}
