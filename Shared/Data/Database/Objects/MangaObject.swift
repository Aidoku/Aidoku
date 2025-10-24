//
//  MangaObject.swift
//  Aidoku
//
//  Created by Skitty on 1/27/22.
//

import Foundation
import CoreData
import AidokuRunner

@objc(MangaObject)
public class MangaObject: NSManagedObject {

    func load(from manga: Manga, override: Bool = false) {
        let editedKeys = EditedKeys(rawValue: editedKeys)
        id = manga.id
        sourceId = manga.sourceId
        if override || !editedKeys.contains(.title) {
            title = manga.title ?? ""
        }
        if override || !editedKeys.contains(.authors) {
            author = manga.author
        }
        if override || !editedKeys.contains(.artists) {
            artist = manga.artist
        }
        if override || !editedKeys.contains(.description) {
            desc = manga.description
        }
        if override || !editedKeys.contains(.tags) {
            tags = manga.tags ?? []
        }
        if override || !editedKeys.contains(.cover) {
            cover = manga.coverUrl?.absoluteString
        }
        if override || !editedKeys.contains(.url) {
            url = manga.url?.absoluteString
        }
        if override || !editedKeys.contains(.status) {
            status = Int16(manga.status.rawValue)
        }
        if override || !editedKeys.contains(.contentRating) {
            nsfw = Int16(manga.nsfw.rawValue)
        }
        if override || !editedKeys.contains(.viewer) {
            viewer = Int16(manga.viewer.rawValue)
        }
        if override || !editedKeys.contains(.neverUpdate) {
            neverUpdate = manga.updateStrategy == .never
        }
        nextUpdateTime = manga.nextUpdateTime
        chapterFlags = Int16(manga.chapterFlags)
        langFilter = manga.langFilter
        scanlatorFilter = manga.scanlatorFilter
    }

    func load(from manga: AidokuRunner.Manga, sourceId: String) {
        id = manga.key
        self.sourceId = sourceId
        title = manga.title
        author = manga.authors.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }
        artist = manga.artists.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }
        desc = manga.description
        tags = manga.tags ?? []
        cover = manga.cover
        url = manga.url?.absoluteString
        status = Int16(manga.status.rawValue)
        let contentRating = manga.contentRating.rawValue
        nsfw = Int16(contentRating > 0 ? contentRating - 1 : 0)
        viewer = switch manga.viewer {
            case .unknown: 0
            case .rightToLeft: 1
            case .leftToRight: 2
            case .vertical: 3
            case .webtoon: 4
        }
        neverUpdate = manga.updateStrategy == .never
        nextUpdateTime = manga.nextUpdateTime.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    func toManga() -> Manga {
        Manga(
            sourceId: sourceId,
            id: id,
            title: title,
            author: author,
            artist: artist,
            description: desc,
            tags: tags ?? [],
            coverUrl: cover != nil ? URL(string: cover!) : nil,
            url: url != nil ? URL(string: url!) : nil,
            status: PublishingStatus(rawValue: Int(status)) ?? .unknown,
            nsfw: MangaContentRating(rawValue: Int(nsfw)) ?? .safe,
            viewer: MangaViewer(rawValue: Int(viewer)) ?? .defaultViewer,
            updateStrategy: neverUpdate ? .never : .always,
            nextUpdateTime: nextUpdateTime,
            chapterFlags: Int(chapterFlags),
            langFilter: langFilter,
            scanlatorFilter: scanlatorFilter,
            lastUpdated: libraryObject?.lastUpdated,
            lastOpened: libraryObject?.lastOpened,
            lastRead: libraryObject?.lastRead,
            dateAdded: libraryObject?.dateAdded
        )
    }

    func toNewManga() -> AidokuRunner.Manga {
        let viewer: Viewer = switch viewer {
            case 0: .unknown
            case 1: .rightToLeft
            case 2: .leftToRight
            case 3: .vertical
            case 4: .webtoon
            default: .unknown
        }
        return AidokuRunner.Manga(
            sourceKey: sourceId,
            key: id,
            title: title,
            cover: cover,
            artists: artist?.components(separatedBy: ", "),
            authors: author?.components(separatedBy: ", "),
            description: desc,
            url: url.flatMap { URL(string: $0) },
            tags: tags,
            status: AidokuRunner.PublishingStatus(rawValue: UInt8(status)) ?? .unknown,
            contentRating: AidokuRunner.ContentRating(rawValue: UInt8(nsfw + 1)) ?? .unknown,
            viewer: viewer,
            updateStrategy: neverUpdate ? .never : .always,
            nextUpdateTime: nextUpdateTime.flatMap { Int($0.timeIntervalSince1970) },
            chapters: nil
        )
    }
}

extension MangaObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MangaObject> {
        NSFetchRequest<MangaObject>(entityName: "Manga")
    }

    @NSManaged public var id: String
    @NSManaged public var sourceId: String
    @NSManaged public var title: String
    @NSManaged public var author: String?
    @NSManaged public var artist: String?
    @NSManaged public var desc: String?
    @NSManaged public var tags: [String]?
    @NSManaged public var cover: String?
    @NSManaged public var url: String?

    @NSManaged public var status: Int16
    @NSManaged public var nsfw: Int16
    @NSManaged public var viewer: Int16

    @NSManaged public var neverUpdate: Bool
    @NSManaged public var nextUpdateTime: Date?

    @NSManaged public var chapterFlags: Int16
    @NSManaged public var langFilter: String?
    @NSManaged public var scanlatorFilter: [String]?

    @NSManaged public var editedKeys: Int32

    @NSManaged public var libraryObject: LibraryMangaObject?
    @NSManaged public var fileInfo: LocalFileInfoObject?
    @NSManaged public var chapters: NSSet?
}

// MARK: Generated accessors for chapters
extension MangaObject {

    @objc(addChaptersObject:)
    @NSManaged public func addToChapters(_ value: ChapterObject)

    @objc(removeChaptersObject:)
    @NSManaged public func removeFromChapters(_ value: ChapterObject)

    @objc(addChapters:)
    @NSManaged public func addToChapters(_ values: NSSet)

    @objc(removeChapters:)
    @NSManaged public func removeFromChapters(_ values: NSSet)
}
