//
//  Book.swift
//  Aidoku
//
//  Created by Skitty on 7/24/22.
//

import Foundation

// TODO: refactor

class Book: KVCObject, Codable, Hashable {
    static func == (lhs: Book, rhs: Book) -> Bool {
        lhs.sourceId == rhs.sourceId && lhs.id == rhs.id
    }

    var key: String {
        self.sourceId + "." + self.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
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

    func toManga() -> Manga {
        Manga(
            sourceId: sourceId,
            id: id,
            title: title,
            author: author,
            artist: artist,
            description: description,
            tags: tags,
            cover: coverUrl?.absoluteString,
            url: url?.absoluteString,
            status: status,
            nsfw: nsfw,
            viewer: viewer,
//            tintColor: tintColor?.color,
            lastUpdated: lastUpdated,
            lastOpened: lastOpened,
            lastRead: lastRead,
            dateAdded: dateAdded
        )
    }

    static func fromManga(_ manga: Manga) -> Book {
        Book(
            sourceId: manga.sourceId,
            id: manga.id,
            title: manga.title,
            author: manga.author,
            artist: manga.artist,
            description: manga.description,
            tags: manga.tags,
            coverUrl: manga.cover != nil ? URL(string: manga.cover!) : nil,
            url: manga.url != nil ? URL(string: manga.url!) : nil,
            status: manga.status,
            nsfw: manga.nsfw,
            viewer: manga.viewer,
//            tintColor: manga.tintColor?.color,
            lastUpdated: manga.lastUpdated,
            lastOpened: manga.lastOpened,
            lastRead: manga.lastRead,
            dateAdded: manga.dateAdded
        )
    }

    func load(from manga: Manga) {
        title = manga.title ?? title
        author = manga.author ?? author
        artist = manga.artist ?? artist
        description = manga.description ?? description
        tags = manga.tags ?? tags
        coverUrl = manga.cover != nil ? URL(string: manga.cover!) : coverUrl
        url = manga.url != nil ? URL(string: manga.url!) : url
        status = manga.status
        nsfw = manga.nsfw
        viewer = manga.viewer
//        tintColor = manga.tintColor ?? tintColor
        lastUpdated = manga.lastUpdated ?? lastUpdated
        lastOpened = manga.lastOpened ?? lastOpened
        lastRead = manga.lastRead ?? lastRead
        dateAdded = manga.dateAdded ?? dateAdded
    }

    func toInfo() -> BookInfo {
        BookInfo(bookId: id, sourceId: sourceId, coverUrl: coverUrl, title: title, author: author)
    }

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
