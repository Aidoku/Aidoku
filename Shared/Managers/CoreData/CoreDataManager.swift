//
//  CoreDataManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import CoreData

final class CoreDataManager {

    static let containerID = Bundle.main
        .infoDictionary?["ICLOUD_CONTAINER_ID"] as? String ?? "iCloud.\(Bundle.main.bundleIdentifier!)"

    static let shared = CoreDataManager()

    private var observers: [NSObjectProtocol] = []
    private var lastHistoryToken: NSPersistentHistoryToken?

    private var shouldUseiCloud: Bool {
        UserDefaults.standard.bool(forKey: "General.icloudSync") && FileManager.default.ubiquityIdentityToken != nil
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: nil
        ) { [weak self] _ in
            self?.storeRemoteChange()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("General.icloudSync"), object: nil, queue: nil
        ) { [weak self] _ in
            guard
                let self,
                let cloudDescription = self.container.persistentStoreDescriptions.first
            else { return }
            if self.shouldUseiCloud {
                cloudDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CoreDataManager.containerID)
            } else {
                cloudDescription.cloudKitContainerOptions = nil
            }
        })
    }

    lazy var container: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "Aidoku")

        let storeDirectory = FileManager.default.applicationSupportDirectory

        let cloudDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Aidoku.sqlite"))
        cloudDescription.configuration = "Cloud"
        cloudDescription.shouldMigrateStoreAutomatically = true
        cloudDescription.shouldInferMappingModelAutomatically = true

        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let localDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Local.sqlite"))
        localDescription.configuration = "Local"
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true

        if shouldUseiCloud {
            cloudDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: CoreDataManager.containerID)
        } else {
            cloudDescription.cloudKitContainerOptions = nil
        }

        container.persistentStoreDescriptions = [
            cloudDescription,
            localDescription
        ]

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                LogManager.logger.error("Error loading persistent stores \(error), \(error.userInfo)")
            }
        }

//        do {
//            try container.initializeCloudKitSchema(options: [.printSchema])
//        } catch {
//            print("error initializing cloudkit schema:", error)
//        }

        return container
    }()

    lazy var queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var context: NSManagedObjectContext {
        container.viewContext
    }

    func save() {
        do {
            try context.save()
        } catch {
            LogManager.logger.error("CoreDataManager.save: \(error.localizedDescription)")
        }
    }

//    func saveIfNeeded() {
//        if context.hasChanges {
//            save()
//        }
//    }

    func remove(_ objectID: NSManagedObjectID) {
        container.performBackgroundTask { context in
            let object = context.object(with: objectID)
            context.delete(object)
            try? context.save()
        }
    }

    /// Clear all objects from fetch request.
    func clear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext? = nil) {
        let context = context ?? self.context
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
        do {
            _ = try context.execute(deleteRequest)
        } catch {
            LogManager.logger.error("CoreDataManager.clear: \(error.localizedDescription)")
        }
    }

    // TODO: clean this up
    func migrateChapterHistory(progress: (@Sendable (Float) -> Void)? = nil) async {
        LogManager.logger.info("Beginning chapter history migration for 0.6")

        await container.performBackgroundTask { context in
            let request = HistoryObject.fetchRequest()
            let historyObjects = (try? context.fetch(request)) ?? []
            let total = Float(historyObjects.count)
            var i: Float = 0
            var count = 0
            for historyObject in historyObjects {
                progress?(i / total)
                i += 1
                guard
                    historyObject.chapter == nil,
                    let chapterObject = self.getChapter(
                        sourceId: historyObject.sourceId,
                        mangaId: historyObject.mangaId,
                        chapterId: historyObject.chapterId,
                        context: context
                    )
                else { continue }
                historyObject.chapter = chapterObject
                count += 1
            }
            try? context.save()

            LogManager.logger.info("Migrated \(count)/\(historyObjects.count) history objects")
        }
    }
}

extension CoreDataManager {

    func storeRemoteChange() {
        queue.addOperation {
            let context = self.container.newBackgroundContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.performAndWait {
                let historyFetchRequest = NSPersistentHistoryTransaction.fetchRequest!
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastHistoryToken)
                request.fetchRequest = historyFetchRequest

                let result = (try? context.execute(request)) as? NSPersistentHistoryResult
                guard
                    let transactions = result?.result as? [NSPersistentHistoryTransaction],
                    !transactions.isEmpty
                else { return }

                var newObjectIds = [NSManagedObjectID]()
                let entityNames = [
                    CategoryObject.entity().name,
                    ChapterObject.entity().name,
                    HistoryObject.entity().name,
                    LibraryMangaObject.entity().name,
                    MangaObject.entity().name,
                    TrackObject.entity().name
                ]

                for
                    transaction in transactions
                    where transaction.changes != nil && transaction.author == "NSCloudKitMirroringDelegate.import"
                {
                    for
                        change in transaction.changes!
                        where entityNames.contains(change.changedObjectID.entity.name) && change.changeType == .insert
                    {
                        newObjectIds.append(change.changedObjectID)
                    }
                }

                if !newObjectIds.isEmpty {
                    self.deduplicate(objectIds: newObjectIds)
                }

                self.lastHistoryToken = transactions.last!.token
            }
        }
    }

    func deduplicate(objectIds: [NSManagedObjectID]) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.performAndWait {
            for objectId in objectIds {
                deduplicate(objectId: objectId, context: context)
            }
            do {
                try context.save()
            } catch {
                LogManager.logger.error("deduplicate: \(error.localizedDescription)")
            }
        }
    }

    func deduplicate(objectId: NSManagedObjectID, context: NSManagedObjectContext) {
        let object = context.object(with: objectId)

        let request: NSFetchRequest<NSFetchRequestResult>?

        if let object = object as? MangaObject {
            request = MangaObject.fetchRequest()
            request?.predicate = NSPredicate(format: "sourceId == %@ AND id == %@", object.sourceId, object.id)
        } else if let object = object as? CategoryObject {
            request = CategoryObject.fetchRequest()
            request?.predicate = NSPredicate(format: "title == %@", object.title ?? "")
        } else if let object = object as? ChapterObject {
            request = ChapterObject.fetchRequest()
            request?.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND id == %@",
                object.sourceId, object.mangaId, object.id
            )
        } else if let object = object as? HistoryObject {
            request = HistoryObject.fetchRequest()
            request?.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND chapterId == %@",
                object.sourceId, object.mangaId, object.chapterId
            )
        } else if let object = object as? LibraryMangaObject {
            request = LibraryMangaObject.fetchRequest()
            request?.predicate = NSPredicate(
                format: "manga.sourceId == %@ AND manga.id == %@",
                object.manga?.sourceId ?? "", object.manga?.id ?? ""
            )
        } else if let object = object as? TrackObject {
            request = TrackObject.fetchRequest()
            request?.predicate = NSPredicate(format: "id == %@ AND trackerId == %@", object.id ?? "", object.trackerId ?? "")
        } else {
            request = nil
        }

        guard let request = request else { return }

        if (try? context.count(for: request)) ?? 0 > 1 {
            guard let objects = try? context.fetch(request) else { return }
            for object in objects.dropFirst(1) {
                if let object = object as? NSManagedObject {
                    context.delete(object)
                }
            }
        }
    }
}
