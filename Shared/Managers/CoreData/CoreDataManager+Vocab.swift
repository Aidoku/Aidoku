//
//  CoreDataManager+Vocab.swift
//  Aidoku
//
//  Created by Skitty on 7/23/26.
//

import CoreData

extension CoreDataManager {
    /// Removes all vocab objects.
    func clearVocab(context: NSManagedObjectContext? = nil) {
        clear(request: VocabObject.fetchRequest(), context: context)
    }

    /// Gets all vocab objects.
    func getVocab(sorted: Bool = true, context: NSManagedObjectContext? = nil) -> [VocabObject] {
        let request = VocabObject.fetchRequest()
        if sorted {
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdDate", ascending: false)
            ]
        }
        return (try? (context ?? self.context).fetch(request)) ?? []
    }

    /// Checks if a vocab item for a specified word exists in the data store.
    func hasVocab(word: String, reading: String? = nil, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = VocabObject.fetchRequest()
        if let reading {
            request.predicate = NSPredicate(
                format: "word == %@ AND reading == %@",
                word, reading
            )
        } else {
            request.predicate = NSPredicate(
                format: "word == %@",
                word
            )
        }
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Gets a vocab item for a specified word.
    func getVocab(word: String, reading: String? = nil, context: NSManagedObjectContext? = nil) -> VocabObject? {
        let context = context ?? self.context
        let request = VocabObject.fetchRequest()
        if let reading {
            request.predicate = NSPredicate(
                format: "word == %@ AND reading == %@",
                word, reading
            )
        } else {
            request.predicate = NSPredicate(
                format: "word == %@",
                word
            )
        }
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Creates a new vocab item.
    @discardableResult
    func createVocab(
        entry: VocabEntry,
        context: NSManagedObjectContext? = nil
    ) -> VocabObject {
        let context = context ?? self.context
        let object = VocabObject(context: context)
        object.load(from: entry)
        return object
    }

    /// Removes a vocab item.
    func removeVocab(word: String, reading: String? = nil, context: NSManagedObjectContext? = nil) {
        guard let object = getVocab(
            word: word,
            reading: reading,
            context: context
        ) else { return }
        (context ?? self.context).delete(object)
    }
}
