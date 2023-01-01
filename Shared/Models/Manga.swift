//
//  Manga.swift
//  Aidoku
//
//  Created by Skitty on 7/24/22.
//

import Foundation

// TODO: refactor

class Manga: Codable, Hashable {

    var key: String {
        self.sourceId + "." + self.id
    }

    let sourceId: String
    let id: String

    var title: String?
    var author: String?
    var artist: String?

    var description: String?
    var tags: [String]?

    var coverUrl: URL?
    var url: URL?

    var status: PublishingStatus
    var nsfw: MangaContentRating
    var viewer: MangaViewer

//    var tintColor: CodableColor?

    var lastUpdated: Date?
    var lastOpened: Date?
    var lastRead: Date?
    var dateAdded: Date?

    init(
        sourceId: String,
        id: String,
        title: String? = nil,
        author: String? = nil,
        artist: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        coverUrl: URL? = nil,
        url: URL? = nil,
        status: PublishingStatus = .unknown,
        nsfw: MangaContentRating = .safe,
        viewer: MangaViewer = .defaultViewer,
//        tintColor: UIColor? = nil,
        lastUpdated: Date? = nil,
        lastOpened: Date? = nil,
        lastRead: Date? = nil,
        dateAdded: Date? = nil
    ) {
        self.sourceId = sourceId
        self.id = id
        self.title = title
        self.author = author
        self.artist = artist
        self.description = description
        self.tags = tags
        self.coverUrl = coverUrl
        self.url = url
        self.status = status
        self.nsfw = nsfw
        self.viewer = viewer
//        self.tintColor = tintColor != nil ? CodableColor(color: tintColor!) : nil
        self.lastUpdated = lastUpdated
        self.lastOpened = lastOpened
        self.lastRead = lastRead
        self.dateAdded = dateAdded
    }

    func load(from manga: Manga) {
        title = manga.title ?? title
        author = manga.author ?? author
        artist = manga.artist ?? artist
        description = manga.description ?? description
        tags = manga.tags ?? tags
        coverUrl = manga.coverUrl ?? coverUrl
        url = manga.url ?? url
        status = manga.status
        nsfw = manga.nsfw
        viewer = manga.viewer
//        tintColor = manga.tintColor ?? tintColor
        lastUpdated = manga.lastUpdated ?? lastUpdated
        lastOpened = manga.lastOpened ?? lastOpened
        lastRead = manga.lastRead ?? lastRead
        dateAdded = manga.dateAdded ?? dateAdded
    }

    func copy(from manga: Manga) -> Manga {
        Manga(
            sourceId: manga.sourceId,
            id: manga.id,
            title: manga.title ?? title,
            author: manga.author ?? author,
            artist: manga.artist ?? artist,
            description: manga.description ?? description,
            tags: manga.tags ?? tags,
            coverUrl: manga.coverUrl ?? coverUrl,
            url: manga.url ?? url,
            status: manga.status,
            nsfw: manga.nsfw,
            viewer: manga.viewer,
            lastUpdated: manga.lastUpdated ?? lastUpdated,
            lastOpened: manga.lastOpened ?? lastOpened,
            lastRead: manga.lastRead ?? lastRead,
            dateAdded: manga.dateAdded ?? dateAdded
        )
    }

    func toInfo() -> MangaInfo {
        MangaInfo(mangaId: id, sourceId: sourceId, coverUrl: coverUrl, title: title, author: author)
    }

    static func == (lhs: Manga, rhs: Manga) -> Bool {
        lhs.sourceId == rhs.sourceId && lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sourceId)
        hasher.combine(id)
    }
}

extension Manga: KVCObject {
    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "id": return id
        case "title": return title
        case "author": return author
        case "artist": return artist
        case "description": return description
        case "tags": return tags
        case "cover": return coverUrl
        case "url": return url
        case "status": return status.rawValue
        case "nsfw": return nsfw.rawValue
        case "viewer": return viewer.rawValue
        default: return nil
        }
    }
}
