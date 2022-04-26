//
//  MangaObject.swift
//  Aidoku
//
//  Created by Skitty on 1/27/22.
//

import Foundation
import CoreData

@objc(MangaObject)
public class MangaObject: NSManagedObject {

    func load(from manga: Manga) {
        id = manga.id
        sourceId = manga.sourceId
        title = manga.title ?? "No title"
        author = manga.author
        artist = manga.artist
        desc = manga.description
        tags = manga.tags ?? []
        cover = manga.cover
        url = manga.url
        status = Int16(manga.status.rawValue)
        nsfw = Int16(manga.nsfw.rawValue)
        viewer = Int16(manga.viewer.rawValue)
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
            cover: cover,
            url: url,
            status: MangaStatus(rawValue: Int(status)) ?? .unknown,
            nsfw: MangaContentRating(rawValue: Int(nsfw)) ?? .safe,
            viewer: MangaViewer(rawValue: Int(viewer)) ?? .defaultViewer,
            lastUpdated: libraryObject?.lastUpdated,
            lastOpened: libraryObject?.lastOpened,
            lastRead: libraryObject?.lastRead,
            dateAdded: libraryObject?.dateAdded
        )
    }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
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

    @NSManaged public var libraryObject: LibraryMangaObject?
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

extension MangaObject: Identifiable {

}
