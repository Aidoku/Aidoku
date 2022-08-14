//
//  CoreDataManager+Category.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/11/22.
//

import CoreData

extension CoreDataManager {

    func getCategories() -> [CategoryObject] {
        let request = CategoryObject.fetchRequest()
        let objects = try? container.viewContext.fetch(request)
        return objects ?? []
    }

    func getCategories(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> [CategoryObject] {
        let libraryObject = getLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context)
        return (libraryObject?.categories?.allObjects as? [CategoryObject]) ?? []
    }

    func getCategories(libraryManga: LibraryMangaObject) -> [CategoryObject] {
        (libraryManga.categories?.allObjects as? [CategoryObject]) ?? []
    }
}
