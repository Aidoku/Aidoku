//
//  BackupLibraryManga.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import CoreData
import Kingfisher

struct BackupLibraryManga: Codable {
    var lastOpened: Date
    var lastUpdated: Date
    var dateAdded: Date
    var categories: [String]

    var mangaId: String
    var sourceId: String

    init(libraryObject: LibraryMangaObject) {
        lastOpened = libraryObject.lastOpened
        lastUpdated = libraryObject.lastUpdated
        dateAdded = libraryObject.dateAdded
        mangaId = libraryObject.manga.id
        sourceId = libraryObject.manga.sourceId
        categories = []
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
        obj.dateAdded = dateAdded
        return obj
    }
}
