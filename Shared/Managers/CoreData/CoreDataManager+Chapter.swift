//
//  CoreDataManager+Chapter.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/13/22.
//

import CoreData

extension CoreDataManager {

    /// Get a particular chapter object.
    func getChapter(sourceId: String, mangaId: String, id: String, context: NSManagedObjectContext? = nil) -> ChapterObject? {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@ AND id == %@",
            sourceId, mangaId, id
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get the chapter objects for a manga.
    func getChapters(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@",
            sourceId, mangaId
        )
        return (try? context.fetch(request)) ?? []
    }

    /// Check if a chapter exists in the data store.
    func chapterExists(sourceId: String, mangaId: String, id: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@ AND id == %@",
            sourceId, mangaId, id
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Create a chapter object.
    @discardableResult
    func createChapter(_ chapter: Chapter, context: NSManagedObjectContext? = nil) -> ChapterObject? {
        let context = context ?? self.context
        guard let mangaObject = getManga(sourceId: chapter.sourceId, mangaId: chapter.mangaId, context: context) else {
            return nil
        }
        let object = ChapterObject(context: context)
        object.load(from: chapter)
        object.manga = mangaObject
        return object
    }

    /// Set a list of chapters for a manga.
    func setChapters(_ chapters: [Chapter], sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) {
        let context = context ?? self.context
        var newChapters = chapters

        // update existing chapter objects
        let chapterObjects = getChapters(sourceId: sourceId, mangaId: mangaId, context: context)
        for object in chapterObjects {
            if let newChapter = chapters.first(where: { $0.id == object.id }) {
                object.load(from: newChapter)
                newChapters.removeAll { $0.id == object.id }
            } else {
                context.delete(object)
            }
        }

        // create new chapter objects
        for chapter in newChapters where !chapterExists(
            sourceId: sourceId,
            mangaId: mangaId,
            id: chapter.id,
            context: context
        ) {
            createChapter(chapter, context: context)
        }
    }

    /// Get the number of unread chapters for a manga.
    func unreadCount(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> Int {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@ AND (history == nil OR history.completed == false)",
            sourceId, mangaId
        )
        return (try? context.count(for: request)) ?? 0
    }

    /// Get the number of read chapters for a manga.
    func readCount(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> Int {
        let context = context ?? self.context
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@ AND history != nil AND history.completed == true",
            sourceId, mangaId
        )
        return (try? context.count(for: request)) ?? 0
    }
}
