//
//  CoreDataManager+Source.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/3/23.
//

import CoreData
import AidokuRunner

extension CoreDataManager {

    /// Remove all source objects.
    func clearSources(context: NSManagedObjectContext? = nil) {
        clear(request: SourceObject.fetchRequest(), context: context)
    }

    /// Gets all source objects.
    func getSources(context: NSManagedObjectContext? = nil) -> [SourceObject] {
        (try? (context ?? self.context).fetch(SourceObject.fetchRequest())) ?? []
    }

    /// Check if a source exists in the data store.
    func hasSource(id: String, context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? self.context
        let request = SourceObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Get a particular source object.
    func getSource(id: String, context: NSManagedObjectContext? = nil) -> SourceObject? {
        let context = context ?? self.context
        let request = SourceObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Creates a new source item.
    @discardableResult
    func createSource(source: Source, context: NSManagedObjectContext? = nil) -> SourceObject {
        let context = context ?? self.context
        let object = SourceObject(context: context)
        object.load(from: source)
        return object
    }

    @discardableResult
    func createSource(source: AidokuRunner.Source, context: NSManagedObjectContext? = nil) -> SourceObject {
        let context = context ?? self.context
        let object = SourceObject(context: context)
        object.load(from: source)
        return object
    }

    /// Removes a source object.
    func removeSource(id: String, context: NSManagedObjectContext? = nil) {
        guard let object = getSource(id: id, context: context) else { return }
        (context ?? self.context).delete(object)
    }

    func setListing(sourceId: String, listing: Int) async {
        await container.performBackgroundTask { context in
            guard
                listing >= 0,
                listing < Int16.max,
                let source = self.getSource(id: sourceId, context: context)
            else { return }
            source.listing = Int16(listing)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.setListing: \(error.localizedDescription)")
            }
        }
    }

    func getListing(sourceId: String) async -> Int? {
        await container.performBackgroundTask { context in
            if let source = self.getSource(id: sourceId, context: context) {
                return Int(source.listing)
            } else {
                return nil
            }
        }
    }
}
