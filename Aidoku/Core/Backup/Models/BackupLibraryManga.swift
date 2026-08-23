//
//  BackupLibraryManga.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import CoreData

struct BackupLibraryManga: Codable, Hashable {
    var lastOpened: Date
    var lastUpdated: Date
    var lastUpdatedChapters: Date?
    var lastChapter: Date?
    var lastRead: Date?
    var dateAdded: Date
    var categories: [String]?

    var mangaId: String
    var sourceId: String

    var identifier: MangaIdentifier {
        .init(sourceKey: sourceId, mangaKey: mangaId)
    }

    init(libraryObject: LibraryMangaObject, skipCategories: Bool = false) {
        lastOpened = libraryObject.lastOpened
        lastUpdated = libraryObject.lastUpdated
        lastUpdatedChapters = libraryObject.lastUpdatedChapters
        lastChapter = libraryObject.lastChapter
        lastRead = libraryObject.lastRead
        dateAdded = libraryObject.dateAdded
        mangaId = libraryObject.manga?.id ?? ""
        sourceId = libraryObject.manga?.sourceId ?? ""
        if !skipCategories {
            categories = (libraryObject.categories?.allObjects as? [CategoryObject])?.compactMap { $0.title } ?? []
        }
    }

    func toObject(context: NSManagedObjectContext) -> LibraryMangaObject {
        let obj = LibraryMangaObject(context: context)
        obj.lastOpened = lastOpened
        obj.lastUpdated = lastUpdated
        obj.lastUpdatedChapters = lastUpdatedChapters ?? lastUpdated
        obj.lastChapter = lastChapter
        obj.lastRead = lastRead
        obj.dateAdded = dateAdded
        return obj
    }
}
