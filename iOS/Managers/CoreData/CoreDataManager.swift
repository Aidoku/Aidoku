//
//  CoreDataManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import CoreData

final class CoreDataManager {

    static let shared = CoreDataManager()

    private var cloudSyncObserver: NSObjectProtocol?

    deinit {
        if let cloudSyncObserver = cloudSyncObserver {
            NotificationCenter.default.removeObserver(cloudSyncObserver)
        }
    }

    init() {
        cloudSyncObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("General.icloudSync"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let cloudDescription = self?.container.persistentStoreDescriptions.first else { return }
            if UserDefaults.standard.bool(forKey: "General.icloudSync") {
                cloudDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.xyz.skitty.Aidoku")
            } else {
                cloudDescription.cloudKitContainerOptions = nil
            }
        }
    }

    lazy var container: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "Aidoku")

        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

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

        if UserDefaults.standard.bool(forKey: "General.icloudSync") {
            cloudDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.xyz.skitty.Aidoku")
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
        return container
    }()

    var context: NSManagedObjectContext {
        container.viewContext
    }

    func saveIfNeeded() {
        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            LogManager.logger.error("CoreData save error \(error)")
        }
    }

    func remove(_ object: NSManagedObject) {
        container.performBackgroundTask { context in
            let object = context.object(with: object.objectID)
            context.delete(object)
        }
    }

    // TODO: clean this up
    func migrateChapterHistory() {
        LogManager.logger.info("Beginning chapter history migration for 0.6")
        var count = 0

        let request = HistoryObject.fetchRequest()
        let historyObjects = (try? context.fetch(request)) ?? []
        for historyObject in historyObjects {
            guard
                historyObject.chapter == nil,
                let chapterObject = getChapter(
                    sourceId: historyObject.sourceId,
                    mangaId: historyObject.mangaId,
                    id: historyObject.chapterId
                )
            else { continue }
            historyObject.chapter = chapterObject
            count += 1
        }
        saveIfNeeded()

        LogManager.logger.info("Migrated \(count)/\(historyObjects.count) history objects")
    }
}
