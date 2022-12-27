//
//  CoreDataManager+Category.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/11/22.
//

import CoreData

extension CoreDataManager {

    /// Remove all category objects.
    func clearCategories(context: NSManagedObjectContext? = nil) {
        clear(request: CategoryObject.fetchRequest(), context: context)
    }

    /// Get category object with title.
    func getCategory(title: String, context: NSManagedObjectContext? = nil) -> CategoryObject? {
        let context = context ?? self.context
        let request = CategoryObject.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@", title)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get all category objects.
    func getCategories(sorted: Bool = true, context: NSManagedObjectContext? = nil) -> [CategoryObject] {
        let context = context ?? self.context
        let request = CategoryObject.fetchRequest()
        if sorted {
            request.sortDescriptors = [NSSortDescriptor(key: "sort", ascending: true)]
        }
        let objects = try? context.fetch(request)
        return objects ?? []
    }

    /// Get category objects for a library manga.
    func getCategories(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> [CategoryObject] {
        let libraryObject = getLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context)
        return (libraryObject?.categories?.allObjects as? [CategoryObject]) ?? []
    }

    func getCategoryTitles(context: NSManagedObjectContext? = nil) -> [String] {
        getCategories(context: context).compactMap { $0.title }
    }

    /// Get category objects for a library object.
    func getCategories(libraryManga: LibraryMangaObject) -> [CategoryObject] {
        (libraryManga.categories?.allObjects as? [CategoryObject]) ?? []
    }

    /// Check if category exists.
    func hasCategory(title: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = CategoryObject.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@", title)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Create a category object.
    @discardableResult
    func createCategory(title: String, context: NSManagedObjectContext? = nil) -> CategoryObject? {
        guard hasCategory(title: title, context: context) else { return nil }

        let context = context ?? self.context

        let request = CategoryObject.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sort", ascending: false)]
        let lastCategoryIndex = (try? context.fetch(request))?.first?.sort ?? -1

        let categoryObject = CategoryObject(context: context)
        categoryObject.title = title
        categoryObject.sort = lastCategoryIndex + 1
        return categoryObject
    }

    /// Add categories to library manga.
    func addCategoriesToManga(sourceId: String, mangaId: String, categories: [String], context: NSManagedObjectContext? = nil) {
        guard let libraryObject = getLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context) else { return }
        for category in categories {
            guard let categoryObject = getCategory(title: category, context: context) else { continue }
            libraryObject.addToCategories(categoryObject)
        }
    }

    func addCategoriesToManga(sourceId: String, mangaId: String, categories: [String]) async {
        await container.performBackgroundTask { context in
            self.addCategoriesToManga(sourceId: sourceId, mangaId: mangaId, categories: categories, context: context)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.addCategoriesToManga: \(error.localizedDescription)")
            }
        }
    }

    /// Remove categories from library manga.
    func removeCategoriesFromManga(sourceId: String, mangaId: String, categories: [String]) async {
        await container.performBackgroundTask { context in
            guard let libraryObject = self.getLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context) else { return }
            for category in categories {
                guard let categoryObject = self.getCategory(title: category, context: context) else { continue }
                libraryObject.removeFromCategories(categoryObject)
            }
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.removeCategoriesFromManga: \(error.localizedDescription)")
            }
        }
    }
}
