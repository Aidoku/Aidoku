//
//  DataManager.swift
//  Aidoku
//
//  Created by Skitty on 12/29/21.
//

import CoreData

class DataManager {

    enum DataError: Error {
        case fetchFailed
    }

    static let shared = DataManager()

    var container: NSPersistentCloudKitContainer
    var inMemory: Bool

    var backgroundContext: NSManagedObjectContext!

    var libraryManga: [Manga] = [] {
        didSet {
            NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
        }
    }

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init(inMemory: Bool = false) {
        self.inMemory = inMemory

        container = NSPersistentCloudKitContainer(name: "Aidoku")
        setupContainer(cloudSync: UserDefaults.standard.bool(forKey: "General.icloudSync"))

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("General.icloudSync"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.setupContainer(cloudSync: UserDefaults.standard.bool(forKey: "General.icloudSync"))
        })
    }

    func setupContainer(cloudSync: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Aidoku")
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let mainStoreUrl = storeDirectory.appendingPathComponent("Aidoku.sqlite")

        let cloudDescription = NSPersistentStoreDescription(url: mainStoreUrl)
        cloudDescription.configuration = "Cloud"

        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let localDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Local.sqlite"))
        localDescription.configuration = "Local"

        if inMemory {
            localDescription.url = URL(fileURLWithPath: "/dev/null")
            cloudDescription.url = URL(fileURLWithPath: "/dev/null")
            cloudDescription.cloudKitContainerOptions = nil
        } else if cloudSync {
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

        container.loadPersistentStores { desciption, error in
            if let error = error {
                LogManager.logger.error("CoreData Error: \(error)")
            } else if desciption.configuration == "Cloud" {
                self.backgroundContext = self.container.newBackgroundContext()
                self.backgroundContext.automaticallyMergesChangesFromParent = true
                self.backgroundContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
                self.loadLibrary()
            }
        }
    }

    func fetch<T>(
        request: NSFetchRequest<T>,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [T] {
        let context = context ?? container.viewContext

        var result: [T]?

        context.performAndWait {
            let fetchRequest = request
            if let predicate = predicate {
                fetchRequest.predicate = predicate
            }
            if let sortDescriptors = sortDescriptors {
                fetchRequest.sortDescriptors = sortDescriptors
            }
            if let limit = limit {
                fetchRequest.fetchLimit = limit
            }
            if let offset = offset {
                fetchRequest.fetchOffset = offset
            }
            result = try? context.fetch(fetchRequest)
        }

        guard let result = result else {
            throw DataError.fetchFailed
        }

        return result
    }

    @discardableResult
    func save(context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? container.viewContext

        var result = false
        if context.hasChanges {
            context.performAndWait {
                do {
                    try context.save()
                    result = true
                } catch {
                    LogManager.logger.error("CoreData save: \(error)")
                }
            }
        }
        return result
    }
}

// MARK: - Source Fallback
extension DataManager {

    func getManga(sourceId: String, mangaId: String) async -> Manga? {
        if let manga = getMangaObject(withId: mangaId, sourceId: sourceId, context: backgroundContext)?.toManga() {
            return manga
        }
        return try? await SourceManager.shared.source(for: sourceId)?.getMangaDetails(manga: Manga(sourceId: sourceId, id: mangaId))
    }

    func getChapter(sourceId: String, mangaId: String, chapterId: String) async -> Chapter? {
        if let chapter = getChapterObject(for: sourceId, id: chapterId, mangaId: mangaId, context: backgroundContext)?.toChapter() {
            return chapter
        }
        let chapters = (try? await SourceManager.shared.source(for: sourceId)?.getChapterList(manga: Manga(sourceId: sourceId, id: mangaId))) ?? []
        return chapters.first { $0.id == chapterId }
    }
}

// MARK: - Library Manga
extension DataManager {

    func libraryContains(manga: Manga) -> Bool {
        libraryManga.contains { $0 == manga }
    }

    func addToLibrary(manga: Manga, context: NSManagedObjectContext? = nil, completion: (() -> Void)? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            if self.libraryContains(manga: manga) { return }
            guard let mangaObject = self.getMangaObject(for: manga, context: context) else { return }

            let libraryObject = LibraryMangaObject(context: context)
            libraryObject.manga = mangaObject

            guard self.save(context: context) else { return }
//            self.loadLibrary()
            if let newManga = libraryObject.manga?.toManga() {
                self.libraryManga.append(newManga)
            }
            completion?()
            NotificationCenter.default.post(name: Notification.Name("addToLibrary"), object: manga)

            Task {
                let chapters = await self.getChapters(for: manga, fromSource: true)
                self.set(chapters: chapters, for: manga, context: self.backgroundContext)
//                self.loadLibrary()
                NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
            }
        }
    }

    func setOpened(manga: Manga, context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let libraryObject = self.getLibraryObject(for: manga, createIfMissing: false, context: context) else { return }
            libraryObject.lastOpened = Date()
            guard self.save(context: context) else { return }
            if let oldLibraryManga = self.libraryManga.first(where: {
                $0.sourceId == manga.sourceId && $0.id == manga.id }
            ) {
                oldLibraryManga.lastOpened = libraryObject.lastOpened
            }
            NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
        }
    }

    func setRead(manga: Manga) {
        guard let libraryObject = getLibraryObject(for: manga, createIfMissing: false) else { return }
        libraryObject.lastRead = Date()
        guard save() else { return }
        if let oldLibraryManga = libraryManga.first(where: {
            $0.sourceId == manga.sourceId && $0.id == manga.id }
        ) {
            oldLibraryManga.lastRead = libraryObject.lastRead
        }
        NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
    }

    func loadLibrary(checkUpdate: Bool = true) {
        guard let libraryObjects = try? getLibraryObjects() else { return }
        let newLibrary = libraryObjects.compactMap { libraryObject -> Manga? in
            if let oldManga = libraryManga.first(where: {
                $0.sourceId == libraryObject.manga?.sourceId && $0.id == libraryObject.manga?.id }
            ) {
                let newManga = oldManga.copy(from: oldManga)
                newManga.lastOpened = libraryObject.lastOpened
                newManga.lastRead = libraryObject.lastRead
                newManga.dateAdded = libraryObject.dateAdded
                return newManga
            }
            return libraryObject.manga?.toManga()
        }
        // de-duplicate
        var deduplicated = false
        var finalLibrary: [Manga] = []
        for manga in newLibrary {
            if finalLibrary.contains(where: { $0 == manga }) {
                LogManager.logger.debug("De-duplicating manga \(manga.title ?? manga.id)")
                deduplicate(manga: manga)
                deduplicated = true
            } else {
                finalLibrary.append(manga)
            }
        }
        if deduplicated {
            save()
        }
        libraryManga = finalLibrary

        guard checkUpdate else { return }

        Task.detached {
            let lastUpdated = UserDefaults.standard.double(forKey: "Library.lastUpdated")
            let interval: Double = [
                "never": Double(-1),
                "12hours": 43200,
                "daily": 86400,
                "2days": 172800,
                "weekly": 604800
            ][UserDefaults.standard.string(forKey: "Library.updateInterval")] ?? Double(0)
            guard interval > 0 else { return }
            if Date().timeIntervalSince1970 - lastUpdated > interval {
                await self.updateLibrary()
            }
        }
    }

    func deduplicate(manga: Manga) {
        let mangaObjects = (try? getMangaObjects(
            predicate: NSPredicate(
                format: "sourceId = %@ AND id = %@",
                manga.sourceId, manga.id
            )
        )) ?? []
        guard mangaObjects.count > 1 else { return }
        let toRemove = mangaObjects.dropFirst()
        toRemove.forEach { container.viewContext.delete($0) }
    }

    func getLatestMangaDetails() async {
        do {
            libraryManga = try await libraryManga.concurrentMap { manga in
                guard let newInfo = try? await SourceManager.shared.source(for: manga.sourceId)?.getMangaDetails(manga: manga) else {
                    return manga
                }
                return manga.copy(from: newInfo)
            }
        } catch {
            LogManager.logger.error("getLastestMangaDetails failed: \(error)")
        }
    }

    func getChapters(for manga: Manga, fromSource: Bool = false) async -> [Chapter] {
        if fromSource {
            return (try? await SourceManager.shared.source(for: manga.sourceId)?.getChapterList(manga: manga)) ?? []
        }
        return getChapterObjects(for: manga).map { $0.toChapter() }
    }

    @MainActor
    func getChapters(from sourceId: String, for mangaId: String, fromSource: Bool = false) async -> [Chapter] {
        if fromSource {
            if let manga = getMangaObject(withId: mangaId, sourceId: sourceId)?.toManga() {
                return (try? await SourceManager.shared.source(for: sourceId)?.getChapterList(manga: manga)) ?? []
            } else {
                return []
            }
        } else {
            return getChapterObjects(sourceId: sourceId, mangaId: mangaId).map { $0.toChapter() }
        }
    }

    func updateLibrary(forceAll: Bool = false, context: NSManagedObjectContext? = nil) async {
        let context = context ?? backgroundContext ?? container.viewContext

        if UserDefaults.standard.bool(forKey: "Library.updateOnlyOnWifi") && Reachability.getConnectionType() != .wifi {
            return
        }

        if forceAll || UserDefaults.standard.bool(forKey: "Library.refreshMetadata") {
            await getLatestMangaDetails()
        }

        let skipOptions = UserDefaults.standard.stringArray(forKey: "Library.skipTitles") ?? []
        let excludedCategories = UserDefaults.standard.stringArray(forKey: "Library.excludedUpdateCategories") ?? []

        let newChapters: [[Chapter]] = await (try? libraryManga.concurrentMap { await self.getChapters(for: $0, fromSource: true) }) ?? []

        context.perform {
            for (i, manga) in self.libraryManga.enumerated() {
                if !forceAll {
                    if (skipOptions.contains("completed") && manga.status == .completed)
                        || (skipOptions.contains("notStarted") && !self.hasHistory(for: manga, context: context))
                        || (skipOptions.contains("hasUnread") && self.hasUnread(manga: manga, context: context)) {
                        continue
                    }
                    let mangaCategories = self.getCategories(for: manga)
                    if excludedCategories.contains(where: mangaCategories.contains) {
                        continue
                    }
                }
                if let mangaObject = self.getMangaObject(for: manga, createIfMissing: false, context: context) {
                    mangaObject.load(from: manga)
                    guard i < newChapters.count else { continue }
                    let chapters = newChapters[i]
                    if mangaObject.chapters?.count != chapters.count && !chapters.isEmpty {
                        self.set(chapters: chapters, for: manga, context: context)
                        mangaObject.libraryObject?.lastUpdated = Date()
                    }
                }
            }

            self.save(context: context)

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Library.lastUpdated")
        }
    }

    func clearLibrary() {
        guard let items = try? getLibraryObjects() else { return }
        for item in items {
            container.viewContext.delete(item)
        }
        guard save() else { return }
        libraryManga = []
    }

    func getLibraryObject(for manga: Manga, createIfMissing: Bool = true, context: NSManagedObjectContext? = nil) -> LibraryMangaObject? {
        if let object = try? getLibraryObjects(
            predicate: NSPredicate(
                format: "manga.sourceId = %@ AND manga.id = %@",
                manga.sourceId, manga.id
            ),
            limit: 1,
            context: context
        ).first {
            return object
        } else if createIfMissing, let mangaObject = getMangaObject(for: manga, context: context) {
            let libraryObject = LibraryMangaObject(context: context ?? container.viewContext)
            libraryObject.manga = mangaObject
            return libraryObject
        }
        return nil
    }

    func getLibraryObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [LibraryMangaObject] {
        try fetch(
            request: LibraryMangaObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            context: context
        )
    }
}

// MARK: - Manga
extension DataManager {

    func add(manga: Manga, context: NSManagedObjectContext? = nil) -> MangaObject? {
        if libraryContains(manga: manga),
           let mangaObject = getMangaObject(for: manga, createIfMissing: false, context: context) {
            return mangaObject
        }

        let mangaObject = MangaObject(context: context ?? container.viewContext)
        mangaObject.load(from: manga)

        guard save(context: context) else { return nil }

        return mangaObject
    }

    func delete(manga: Manga, context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let mangaObject = self.getMangaObject(for: manga, context: context) else { return }

            context.delete(mangaObject)

            if self.save(context: context) {
                self.libraryManga.removeAll {
                    $0.sourceId == manga.sourceId && $0.id == manga.id
                }
                self.deleteChapters(for: manga, context: self.backgroundContext)
            }
        }
    }

    func update(manga: Manga, context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let mangaObject = self.getMangaObject(for: manga, context: context) else { return }
            mangaObject.load(from: manga)
            self.save(context: context)
        }
    }

    func clearManga() {
        guard let items = try? getMangaObjects() else { return }
        for item in items {
            container.viewContext.delete(item)
        }
        save()
    }

    // Clear stored manga not in library
    func purgeManga(context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let allManga = try? self.getMangaObjects(context: context) else { return }
            for manga in allManga {
                guard manga.libraryObject == nil else { continue }
                context.delete(manga)
            }
            self.save(context: context)
        }
    }

    func getMangaObject(withId id: String, sourceId: String, context: NSManagedObjectContext? = nil) -> MangaObject? {
        (try? getMangaObjects(
            predicate: NSPredicate(
                format: "sourceId = %@ AND id = %@",
                sourceId, id
            ),
            limit: 1,
            context: context
        ))?.first
    }

    func getMangaObject(for manga: Manga, createIfMissing: Bool = true, context: NSManagedObjectContext? = nil) -> MangaObject? {
        if let object = getMangaObject(withId: manga.id, sourceId: manga.sourceId, context: context) {
            return object
        } else if createIfMissing {
            return add(manga: manga, context: context)
        }
        return nil
    }

    func getMangaObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [MangaObject] {
        try fetch(
            request: MangaObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            context: context
        )
    }
}

// MARK: - Chapters
extension DataManager {

    func add(chapter: Chapter, manga: Manga? = nil, context: NSManagedObjectContext? = nil) -> ChapterObject? {
        let context = context ?? container.viewContext

        let chapterObject = ChapterObject(context: context)
        chapterObject.load(from: chapter)

        if let mangaObject = try? getMangaObjects(
            predicate: NSPredicate(format: "sourceId = %@ AND id = %@", chapter.sourceId, chapter.mangaId),
            limit: 1,
            context: context
        ).first {
            chapterObject.manga = mangaObject
        } else if let manga = manga, let mangaObject = getMangaObject(for: manga, context: context) {
            chapterObject.manga = mangaObject
        }

        guard save(context: context) else { return nil }

        return chapterObject
    }

    func set(chapters: [Chapter], for manga: Manga, context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext

        context.perform {
            var newChapters = chapters
            let chapterObjects = self.getChapterObjects(for: manga, context: context)
            for object in chapterObjects {
                if let newChapter = chapters.first(where: { $0.id == object.id }) {
                    object.load(from: newChapter)
                    newChapters.removeAll { $0.id == object.id }
                } else {
                    context.delete(object)
                }
            }
            for chapter in newChapters {
                _ = self.getChapterObject(for: chapter, manga: manga, context: context)
            }
            _ = self.save(context: context)
        }
    }

    func deleteChapters(for manga: Manga? = nil, context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            let chapters: [ChapterObject]
            if let manga = manga {
                chapters = self.getChapterObjects(for: manga, context: context)
            } else {
                chapters = (try? self.getChapterObjects(context: context)) ?? []
            }
            for chapter in chapters {
                context.delete(chapter)
            }
            _ = self.save(context: context)
        }
    }

    func clearChapters(context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        if let items = try? getChapterObjects(context: context) {
            for item in items {
                context.delete(item)
            }
            _ = save(context: context)
        }
    }

    func getChapterObject(
        for chapter: Chapter, manga: Manga? = nil,
        createIfMissing: Bool = true,
        context: NSManagedObjectContext? = nil
    ) -> ChapterObject? {
        if let object = try? getChapterObjects(
            predicate: NSPredicate(
                format: "sourceId = %@ AND id = %@ AND mangaId = %@",
                chapter.sourceId, chapter.id, chapter.mangaId
            ),
            limit: 1,
            context: context
        ).first {
            return object
        } else if createIfMissing {
            return add(chapter: chapter, manga: manga, context: context)
        }
        return nil
    }

    func getChapterObject(for source: String, id: String, mangaId: String, context: NSManagedObjectContext? = nil) -> ChapterObject? {
        try? getChapterObjects(
            predicate: NSPredicate(
                format: "sourceId = %@ AND id = %@ AND mangaId = %@",
                source, id, mangaId
            ),
            limit: 1,
            context: context
        ).first
    }

    func getChapterObjects(for manga: Manga, context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        getChapterObjects(sourceId: manga.sourceId, mangaId: manga.id, context: context)
    }
    func getChapterObjects(sourceId: String, mangaId: String, context: NSManagedObjectContext? = nil) -> [ChapterObject] {
        (try? getChapterObjects(predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@", sourceId, mangaId),
                                sortDescriptors: [NSSortDescriptor(key: "sourceOrder", ascending: true)],
                                context: context)) ?? []
    }

    func getChapterObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [ChapterObject] {
        try fetch(
            request: ChapterObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            context: context
        )
    }
}

// MARK: - Read History
// TODO: change function names
extension DataManager {

    func currentPage(for chapter: Chapter) -> Int {
        guard let historyObject = getHistoryObject(for: chapter, createIfMissing: false) else { return -1 }
        return Int(historyObject.progress)
    }

    func pageCount(for chapter: Chapter) -> Int {
        guard let historyObject = getHistoryObject(for: chapter, createIfMissing: false) else { return 0 }
        return Int(historyObject.total)
    }

    func setCurrentPage(_ page: Int, for chapter: Chapter, context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let historyObject = self.getHistoryObject(for: chapter, context: context) else { return }
            historyObject.progress = Int16(page)
            historyObject.dateRead = Date()
            self.save(context: context)
            NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
        }
    }

    func setPageCount(_ pages: Int, for chapter: Chapter, context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let historyObject = self.getHistoryObject(for: chapter, context: context) else { return }
            historyObject.total = Int16(pages)
            self.save(context: context)
        }
    }

    func setCompleted(chapter: Chapter, date: Date = Date(), context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let historyObject = self.getHistoryObject(for: chapter, context: context) else { return }
            historyObject.completed = true
            historyObject.dateRead = date
            self.save(context: context)
            NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
        }
    }

    func setCompleted(chapters: [Chapter], date: Date = Date(), context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            for chapter in chapters {
                if let historyObject = self.getHistoryObject(for: chapter, context: context), !historyObject.completed {
                    historyObject.dateRead = date
                    historyObject.completed = true
                }
            }
            self.save(context: context)
            NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
        }
    }

    func addHistory(for chapter: Chapter, page: Int? = nil, date: Date = Date()) {
        guard let historyObject = getHistoryObject(for: chapter) else { return }
        historyObject.dateRead = date
        if let page = page {
            historyObject.progress = Int16(page)
        }
        save()
        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
    }

    func addHistory(for chapters: [Chapter], date: Date = Date(), context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        for chapter in chapters {
            guard let historyObject = getHistoryObject(for: chapter, context: context) else { continue }
            historyObject.dateRead = date
        }
        save(context: context)
        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
    }

    func removeHistory(for manga: Manga, context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let readHistory = try? self.getReadHistory(
                predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@", manga.sourceId, manga.id),
                context: context
            ) else { return }
            for historyObject in readHistory {
                context.delete(historyObject)
            }
            self.save(context: context)
            NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
        }
    }

    func removeHistory(for chapter: Chapter) {
        guard let historyObject = getHistoryObject(for: chapter, createIfMissing: false) else { return }
        container.viewContext.delete(historyObject)
        save()
        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
    }

    func removeHistory(for chapters: [Chapter], context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        for chapter in chapters {
            guard let historyObject = getHistoryObject(for: chapter, createIfMissing: false, context: context) else { continue }
            context.delete(historyObject)
        }
        save(context: context)
        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
    }

    func hasHistory(for chapter: Chapter, context: NSManagedObjectContext? = nil) -> Bool {
        getHistoryObject(for: chapter, createIfMissing: false, context: context) != nil
    }

    func hasHistory(for manga: Manga, context: NSManagedObjectContext? = nil) -> Bool {
        (try? getReadHistory(
            predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@", manga.sourceId, manga.id),
            limit: 1,
            context: context
        ))?.first != nil
    }

    // check if stored chapter objects all have associated reading history
    func hasUnread(manga: Manga, context: NSManagedObjectContext? = nil) -> Bool {
        getChapterObjects(for: manga, context: context).contains { chapter in
            !((try? getReadHistory(
                predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@ AND chapterId = %@", chapter.sourceId, chapter.mangaId, chapter.id),
                limit: 1,
                context: context
            ))?.first?.completed ?? false)
        }
    }

    func clearHistory() {
        guard let items = try? getReadHistory() else { return }
        for item in items {
            container.viewContext.delete(item)
        }
        save()
        NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
    }

    // [chapterId: (page (-1 if completed), read date)]
    func getReadHistory(manga: Manga) -> [String: (Int, Int)] {
        var readHistory: [HistoryObject]?

        var updatedReadHistory = false

        container.viewContext.performAndWait {
            readHistory = try? getReadHistory(
                predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@", manga.sourceId, manga.id)
            )
            // if progress is less than page 1 then it should be marked as completed
            // previously, aidoku would only add read history when marking as read rather than marking as completed
            // this can probably be removed in the future since it only exists to aid migration
            for history in readHistory ?? [] where history.progress < 1 {
                updatedReadHistory = true
                history.completed = true
            }
        }

        guard let readHistory = readHistory else { return [:] }

        var readHistoryDict: [String: (Int, Int)] = [:]
        for history in readHistory {
            // remove duplicate read history objects for the same chapter
            if readHistoryDict[history.chapterId] != nil {
                updatedReadHistory = true
                container.viewContext.delete(history)
                continue
            }
            readHistoryDict[history.chapterId] = (
                history.completed || history.progress < 1 ? -1 : Int(history.progress),
                Int((history.dateRead ?? Date.distantPast).timeIntervalSince1970)
            )
        }

        if updatedReadHistory {
            save()
        }

        return readHistoryDict
    }

    func getHistoryObject(for chapter: Chapter, createIfMissing: Bool = true, context: NSManagedObjectContext? = nil) -> HistoryObject? {
        if let historyObject = try? getReadHistory(
            predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@ AND chapterId = %@", chapter.sourceId, chapter.mangaId, chapter.id),
            limit: 1,
            context: context
        ).first {
            return historyObject
        } else if createIfMissing {
            let readHistory = HistoryObject(context: context ?? container.viewContext)
            readHistory.dateRead = Date()
            readHistory.sourceId = chapter.sourceId
            readHistory.chapterId = chapter.id
            readHistory.mangaId = chapter.mangaId
            return readHistory
        }
        return nil
    }

    func getReadHistory(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = [NSSortDescriptor(key: "dateRead", ascending: false)],
        limit: Int? = nil,
        offset: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [HistoryObject] {
        try fetch(
            request: HistoryObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            offset: offset,
            context: context
        )
    }
}

// MARK: - Sources
extension DataManager {

    func add(source: Source, context: NSManagedObjectContext? = nil) async {
        let context = context ?? container.viewContext
        context.performAndWait {
            if self.getSourceObject(for: source, context: context) != nil { return }

            let sourceObject = SourceObject(context: context)
            sourceObject.load(from: source)

            _ = self.save(context: context)
        }
    }

    func delete(source: Source) {
        guard let sourceObject = getSourceObject(for: source) else { return }
        container.viewContext.delete(sourceObject)
        _ = save()
    }

    func hasSource(id: String) -> Bool {
        (try? getSourceObjects(
            predicate: NSPredicate(
                format: "id = %@",
                id
            ),
            limit: 1
        ).first) != nil
    }

    func setListing(for source: Source, listing: Int) {
        guard let sourceObject = getSourceObject(for: source) else { return }

        sourceObject.listing = Int16(listing)

        _ = save()
    }

    func getListing(for source: Source) -> Int {
        guard let sourceObject = getSourceObject(for: source) else { return 0 }
        return Int(sourceObject.listing)
    }

    func clearSources() {
        if let items = try? getSourceObjects() {
            for item in items {
                container.viewContext.delete(item)
            }
            _ = save()
        }
    }

    func getSourceObject(for source: Source, context: NSManagedObjectContext? = nil) -> SourceObject? {
        if let object = try? getSourceObjects(
            predicate: NSPredicate(
                format: "id = %@",
                source.id
            ),
            limit: 1,
            context: context
        ).first {
            return object
//        } else if createIfMissing {
//            return add(source: source, context: context)
        }
        return nil
    }

    func getSourceObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [SourceObject] {
        try fetch(
            request: SourceObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            context: context
        )
    }
}

// MARK: - Categories
extension DataManager {

    func getCategories() -> [String] {
        ((try? getCategoryObjects()) ?? []).compactMap { $0.title }
    }

    func addCategory(title: String) {
        guard getCategoryObject(title: title, createIfMissing: false) == nil else { return }
        let sort = getNextCategoryIndex()
        let categoryObject = CategoryObject(context: container.viewContext)
        categoryObject.title = title
        categoryObject.sort = sort
        save()
        NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
    }

    func deleteCategory(title: String) {
        guard let categoryObject = getCategoryObject(title: title, createIfMissing: false) else { return }
        let categories = (try? getCategoryObjects()) ?? []
        // decrement category indexes that follow the removed category
        for i in Int(categoryObject.sort)..<categories.count {
            categories[i].sort -= 1
        }
        container.viewContext.delete(categoryObject)
        save()
        NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
    }

    func moveCategory(title: String, toPosition index: Int) {
        guard index >= 0,
              let categoryObject = getCategoryObject(title: title, createIfMissing: false),
              categoryObject.sort != index else { return }
        let currentIndex = Int(categoryObject.sort)
        let categories = (try? getCategoryObjects()) ?? []
        guard index < categories.count else { return }
        if index > currentIndex { // move lower (higher index)
            for i in currentIndex + 1...index {
                categories[i].sort -= 1
            }
        } else { // move higher (lower index)
            for i in index..<currentIndex {
                categories[i].sort += 1
            }
        }
        categoryObject.sort = Int16(index)
        save()
        NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
    }

    func clearCategories() {
        let categories = (try? getCategoryObjects()) ?? []
        for category in categories {
            container.viewContext.delete(category)
        }
        save()
        NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
    }

    func setMangaCategories(manga: Manga, categories: [String], context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        context.perform {
            guard let libraryObject = self.getLibraryObject(for: manga, context: context) else { return }
            let objects = categories.compactMap { self.getCategoryObject(title: $0, context: context) }
            libraryObject.categories = NSSet(array: objects)
            self.save(context: context)
            NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
        }
    }

    func addMangaToCategories(manga: Manga, categories: [String]) {
        guard let libraryObject = getLibraryObject(for: manga) else { return }
        for category in categories {
            guard let categoryObject = getCategoryObject(title: category) else { continue }
            libraryObject.addToCategories(categoryObject)
        }
        save()
        NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
    }

    func getManga(inCategory category: String) -> [Manga] {
        ((try? getLibraryObjects(predicate: NSPredicate(
            format: "ANY categories.title = %@",
            category
        ))) ?? []).compactMap { libraryObject -> Manga? in
            libraryManga.first(where: {
                $0.sourceId == libraryObject.manga?.sourceId && $0.id == libraryObject.manga?.id }
            )
        }
    }

    func getCategories(for manga: Manga) -> [String] {
        guard let libraryObject = getLibraryObject(for: manga, createIfMissing: false) else { return [] }
        return ((libraryObject.categories?.allObjects as? [CategoryObject]) ?? []).compactMap { $0.title }
    }

    private func getNextCategoryIndex() -> Int16 {
        ((try? getCategoryObjects(
            sortDescriptors: [NSSortDescriptor(key: "sort", ascending: false)],
            limit: 1
        ).first?.sort) ?? -1) + 1
    }

    func getCategoryObject(title: String, createIfMissing: Bool = true, context: NSManagedObjectContext? = nil) -> CategoryObject? {
        if let object = try? getCategoryObjects(
            predicate: NSPredicate(
                format: "title = %@", title
            ),
            limit: 1,
            context: context
        ).first {
            return object
        } else if createIfMissing {
            let sort = getNextCategoryIndex()
            let categoryObject = CategoryObject(context: context ?? container.viewContext)
            categoryObject.title = title
            categoryObject.sort = sort
            return categoryObject
        } else {
            return nil
        }
    }

    func getCategoryObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = [NSSortDescriptor(key: "sort", ascending: true)],
        limit: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [CategoryObject] {
        try fetch(
            request: CategoryObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            context: context
        )
    }
    // swiftlint:disable:next file_length
}
