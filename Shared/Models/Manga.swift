//
//  Manga.swift
//  Aidoku
//
//  Created by Skitty on 12/20/21.
//

import Foundation

enum MangaStatus: Int {
    case unknown = 0
    case ongoing = 1
    case completed = 2
    case cancelled = 3
    case hiatus = 4
}

enum MangaViewer: Int {
    case rtl = 0
    case ltf = 1
    case vertical = 2
    case webtoon = 3
}

struct Manga: KVCObject, Hashable  {
    let sourceId: String
    let id: String
    
    var title: String?
    var author: String?
    var artist: String?
    
    var description: String?
    var tags: [String]?
    
    var status: MangaStatus
    
    var cover: String?
    
    var viewer: MangaViewer
    
    init(
        sourceId: String,
        id: String,
        title: String? = nil,
        author: String? = nil,
        artist: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        status: MangaStatus = .unknown,
        cover: String? = nil,
        viewer: MangaViewer = .rtl
    ) {
        self.sourceId = sourceId
        self.id = id
        self.title = title
        self.author = author
        self.artist = artist
        self.description = description
        self.tags = tags
        self.status = status
        self.cover = cover
        self.viewer = viewer
    }
    
    func copy(from manga: Manga) -> Manga {
        Manga(
            sourceId: manga.sourceId,
            id: manga.id,
            title: manga.title,
            author: manga.author ?? self.author,
            artist: manga.artist ?? self.artist,
            description: manga.description ?? self.description,
            tags: manga.tags ?? self.tags,
            status: manga.status,
            cover: manga.cover ?? self.cover,
            viewer: manga.viewer
        )
    }
    
    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "id": return id
        case "title": return title
        case "author": return author
        case "artist": return artist
        case "description": return description
        case "tags": return tags
        case "status": return status.rawValue
        case "cover": return cover
        case "viewer": return viewer.rawValue
        default: return nil
        }
    }
}

struct MangaPageResult {
    let manga: [Manga]
    let hasNextPage: Bool
}
