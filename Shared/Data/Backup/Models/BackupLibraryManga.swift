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
    var lastRead: Date?
    var dateAdded: Date
    var categories: [String]?

    var mangaId: String
    var sourceId: String

    init(libraryObject: LibraryMangaObject, skipCategories: Bool = false) {
        lastOpened = libraryObject.lastOpened
        lastUpdated = libraryObject.lastUpdated
        lastRead = libraryObject.lastRead
        dateAdded = libraryObject.dateAdded
        mangaId = libraryObject.manga?.id ?? ""
        sourceId = libraryObject.manga?.sourceId ?? ""
        if !skipCategories {
            categories = (libraryObject.categories?.allObjects as? [CategoryObject])?.compactMap { $0.title } ?? []
        }
    }

    func toObject(context: NSManagedObjectContext? = nil) -> LibraryMangaObject {
        let obj: LibraryMangaObject
        if let context = context {
            obj = LibraryMangaObject(context: context)
        } else {
            obj = LibraryMangaObject()
        }
        obj.lastOpened = lastOpened
        obj.lastUpdated = lastUpdated
        obj.lastRead = lastRead
        obj.dateAdded = dateAdded
        return obj
    }
}
