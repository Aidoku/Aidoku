//
//  CoreDataManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import Combine
import CoreData

final class CoreDataManager: @unchecked Sendable {
    static let shared = CoreDataManager()

    static let containerID = Bundle.main
        .infoDictionary?["ICLOUD_CONTAINER_ID"] as? String ?? "iCloud.\(Bundle.main.bundleIdentifier!)"

    let container: NSPersistentCloudKitContainer

    @MainActor
    var context: NSManagedObjectContext {
        container.viewContext
    }

    // only accessed from init
    private var cancellables: Set<AnyCancellable> = []

    private let remoteHistoryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.aidoku.remote-history"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    // only accessed from remoteHistoryQueue
    private var lastHistoryToken: NSPersistentHistoryToken?
    private var didLoadHistoryToken = false
    private var lastHistoryPurge: Date?
    private var usesCloudKitMirroring: Bool

    private static let historyTokenUrl = FileManager.default.applicationSupportDirectory
        .appendingPathComponent("historyToken.data")
    /// How far back a cold start looks when no token has been stored yet.
    private static let historyColdStartWindow: TimeInterval = 24 * 60 * 60
    /// How much history to keep around while mirroring is running, which needs it to export.
    private static let historyRetention: TimeInterval = 7 * 24 * 60 * 60
    /// Purging on every remote change notification would run once per save, so throttle it.
    private static let historyPurgeInterval: TimeInterval = 60 * 60

    private static var shouldUseiCloud: Bool {
        AppSettings.general.icloudSync.get() && FileManager.default.ubiquityIdentityToken != nil
    }

    private init() {
        let usesCloudKitMirroring = Self.shouldUseiCloud
        self.usesCloudKitMirroring = usesCloudKitMirroring
        self.container = Self.createContainer(usesCloudKitMirroring: usesCloudKitMirroring)

        NotificationCenter.default.publisher(
            for: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
        .sink { [weak self] _ in
            self?.storeRemoteChange()
        }
        .store(in: &cancellables)

        Publishers.Merge(
            NotificationCenter.default.publisher(for: .init(AppSettings.general.icloudSync.key)),
            NotificationCenter.default.publisher(for: NSNotification.Name.NSUbiquityIdentityDidChange)
        )
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateCloudConfiguration()
                }
            }
            .store(in: &cancellables)
    }

    static func createContainer(usesCloudKitMirroring: Bool) -> NSPersistentCloudKitContainer {
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

        if usesCloudKitMirroring {
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
    }

    @MainActor
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
    func clear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext) {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
        do {
            _ = try context.execute(deleteRequest)
        } catch {
            LogManager.logger.error("CoreDataManager.clear: \(error.localizedDescription)")
        }
    }

    @MainActor
    func updateCloudConfiguration() {
        let usesCloudKitMirroring = Self.shouldUseiCloud
        remoteHistoryQueue.addOperation { [weak self] in
            self?.usesCloudKitMirroring = usesCloudKitMirroring
        }

        guard let cloudDescription = self.container.persistentStoreDescriptions.first else { return }
        if usesCloudKitMirroring {
            cloudDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CoreDataManager.containerID)
        } else {
            cloudDescription.cloudKitContainerOptions = nil
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
                        chapterId: historyObject.identifier,
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
        remoteHistoryQueue.addOperation { [weak self] in
            guard let self else { return }
            guard self.usesCloudKitMirroring else {
                self.purgeHistory(before: Date())
                return
            }
            let context = self.container.newBackgroundContext()
            context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            context.performAndWait {
                let historyFetchRequest = NSPersistentHistoryTransaction.fetchRequest!
                let request: NSPersistentHistoryChangeRequest
                if let token = self.historyToken() {
                    request = .fetchHistory(after: token)
                } else {
                    request = .fetchHistory(after: Date().addingTimeInterval(-Self.historyColdStartWindow))
                }
                request.fetchRequest = historyFetchRequest

                var result = (try? context.execute(request)) as? NSPersistentHistoryResult
                if result == nil && self.historyToken() != nil {
                    self.clearHistoryToken()
                    let fallback = NSPersistentHistoryChangeRequest.fetchHistory(
                        after: Date().addingTimeInterval(-Self.historyColdStartWindow)
                    )
                    fallback.fetchRequest = historyFetchRequest
                    result = (try? context.execute(fallback)) as? NSPersistentHistoryResult
                }
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

                self.setHistoryToken(transactions.last!.token)
            }
            self.purgeHistory(before: Date().addingTimeInterval(-Self.historyRetention))
        }
    }

    private func purgeHistory(before date: Date) {
        let now = Date()
        if let lastHistoryPurge, now.timeIntervalSince(lastHistoryPurge) < Self.historyPurgeInterval {
            return
        }
        lastHistoryPurge = now

        let context = container.newBackgroundContext()
        context.performAndWait {
            do {
                try context.execute(NSPersistentHistoryChangeRequest.deleteHistory(before: date))
            } catch {
                LogManager.logger.error("purgeHistory: \(error.localizedDescription)")
            }
        }
    }

    private func historyToken() -> NSPersistentHistoryToken? {
        if !didLoadHistoryToken {
            didLoadHistoryToken = true
            if let data = try? Data(contentsOf: Self.historyTokenUrl) {
                lastHistoryToken = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSPersistentHistoryToken.self,
                    from: data
                )
            }
        }
        return lastHistoryToken
    }

    private func clearHistoryToken() {
        didLoadHistoryToken = true
        lastHistoryToken = nil
        Self.historyTokenUrl.removeItem()
    }

    private func setHistoryToken(_ token: NSPersistentHistoryToken) {
        didLoadHistoryToken = true
        lastHistoryToken = token
        guard
            let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else { return }
        try? data.write(to: Self.historyTokenUrl, options: .atomic)
    }

    func deduplicate(objectIds: [NSManagedObjectID]) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        // Work in batches, saving and resetting in between.
        for batch in objectIds.chunked(into: 500) {
            context.performAndWait {
                for objectId in batch {
                    deduplicate(objectId: objectId, context: context)
                }
                do {
                    try context.save()
                } catch {
                    LogManager.logger.error("deduplicate: \(error.localizedDescription)")
                }
                context.reset()
            }
        }
    }

    func deduplicate(objectId: NSManagedObjectID, context: NSManagedObjectContext) {
        guard let object = try? context.existingObject(with: objectId) else { return }

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
