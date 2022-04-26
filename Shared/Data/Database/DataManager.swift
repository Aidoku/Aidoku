//
//  DataManager.swift
//  Aidoku
//
//  Created by Skitty on 12/29/21.
//

import CoreData

class DataManager {

    static let shared = DataManager()

    var container: NSPersistentCloudKitContainer
    var inMemory: Bool

    var libraryManga: [Manga] = [] {
        didSet {
            NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
        }
    }

    init(inMemory: Bool = false) {
        self.inMemory = inMemory

        container = NSPersistentCloudKitContainer(name: "Aidoku")
        setupContainer(cloudSync: UserDefaults.standard.bool(forKey: "General.icloudSync"))

        NotificationCenter.default.addObserver(forName: Notification.Name("updateSourceList"), object: nil, queue: nil) { _ in
            Task {
                await self.updateLibrary()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("General.icloudSync"), object: nil, queue: nil) { _ in
            self.setupContainer(cloudSync: UserDefaults.standard.bool(forKey: "General.icloudSync"))
        }
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
                print("[Error] CoreData Error: \(error)")
            } else if desciption.configuration == "Cloud" {
                self.loadLibrary()
            }
        }
    }

    func fetch<T>(
        request: NSFetchRequest<T>,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) throws -> [T] {
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
        return try container.viewContext.fetch(fetchRequest)
    }

    func save() -> Bool {
        let context = container.viewContext

        if context.hasChanges {
            do {
                try context.save()
                return true
            } catch {
                print("[Error] save: \(error)")
                return false
            }
        }
        return false
    }
}

// MARK: - Library Manga
extension DataManager {

    func libraryContains(manga: Manga) -> Bool {
        libraryManga.contains { $0.sourceId == manga.sourceId && $0.id == manga.id }
    }

    func addToLibrary(manga: Manga) -> LibraryMangaObject? {
        if libraryContains(manga: manga) { return getLibraryObject(for: manga, createIfMissing: false) }
        guard let mangaObject = getMangaObject(for: manga) else { return nil }

        let libraryObject = LibraryMangaObject(context: container.viewContext)
        libraryObject.manga = mangaObject

        guard save() else { return nil }
        loadLibrary()

        Task { @MainActor in
            let chapters = await getChapters(for: manga, fromSource: true)
            self.set(chapters: chapters, for: manga)
            NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
        }

        return libraryObject
    }

    func setOpened(manga: Manga) {
        guard let libraryObject = getLibraryObject(for: manga, createIfMissing: false) else { return }
        libraryObject.lastOpened = Date()
        guard save() else { return }
        if let oldLibraryManga = libraryManga.first(where: {
            $0.sourceId == manga.sourceId && $0.id == manga.id }
        ) {
            oldLibraryManga.lastOpened = libraryObject.lastOpened
        }
        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
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
        NotificationCenter.default.post(name: Notification.Name("resortLibrary"), object: nil)
    }

    func loadLibrary() {
        guard let libraryObjects = try? getLibraryObjects() else { return }
        libraryManga = libraryObjects.compactMap { libraryObject -> Manga? in
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
            print("[Error] getLastestMangaDetails: \(error)")
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

    @MainActor
    func updateLibrary() async {
        await getLatestMangaDetails()

        for manga in libraryManga {
            let chapters = await getChapters(for: manga, fromSource: true)
            if let mangaObject = self.getMangaObject(for: manga) {
                mangaObject.load(from: manga)
                if mangaObject.chapters?.count != chapters.count && !chapters.isEmpty {
                    // TODO: do something with this -- notifications?
//                    if chapters.count > mangaObject.chapters?.count ?? 0 {
//                        _ = Int16(chapters.count - (mangaObject.chapters?.count ?? 0))
//                    }
                    self.set(chapters: chapters, for: manga)
                    mangaObject.libraryObject?.lastUpdated = Date()
                }
                _ = self.save()
            }
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

    func getLibraryObject(for manga: Manga, createIfMissing: Bool = true) -> LibraryMangaObject? {
        if let object = try? getLibraryObjects(
            predicate: NSPredicate(
                format: "manga.sourceId = %@ AND manga.id = %@",
                manga.sourceId, manga.id
            ),
            limit: 1
        ).first {
            return object
        } else if createIfMissing, let mangaObject = getMangaObject(for: manga) {
            let libraryObject = LibraryMangaObject(context: container.viewContext)
            libraryObject.manga = mangaObject
            return libraryObject
        }
        return nil
    }

    func getLibraryObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) throws -> [LibraryMangaObject] {
        try fetch(
            request: LibraryMangaObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit
        )
    }
}

// MARK: - Manga
extension DataManager {

    func add(manga: Manga) -> MangaObject? {
        if libraryContains(manga: manga) { return getMangaObject(for: manga, createIfMissing: false) }

        let mangaObject = MangaObject(context: container.viewContext)
        mangaObject.load(from: manga)

        guard save() else { return nil }

        return mangaObject
    }

    func delete(manga: Manga) {
        guard let mangaObject = getMangaObject(for: manga) else { return }

        container.viewContext.delete(mangaObject)

        if save() {
            deleteChapters(for: manga)
            libraryManga.removeAll {
                $0.sourceId == manga.sourceId && $0.id == manga.id
            }
        }
    }

    func clearManga() {
        if let items = try? getMangaObjects() {
            for item in items {
                container.viewContext.delete(item)
            }
            _ = save()
        }
    }

    // Clear stored manga not in library
    func purgeManga() {
        guard let allManga = try? getMangaObjects() else { return }
        for manga in allManga {
            guard manga.libraryObject == nil else { continue }
            container.viewContext.delete(manga)
        }
        _ = save()
    }

    func getMangaObject(withId id: String, sourceId: String) -> MangaObject? {
        try? getMangaObjects(
            predicate: NSPredicate(
                format: "sourceId = %@ AND id = %@",
                sourceId, id
            ),
            limit: 1
        ).first
    }

    func getMangaObject(for manga: Manga, createIfMissing: Bool = true) -> MangaObject? {
        if let object = getMangaObject(withId: manga.id, sourceId: manga.sourceId) {
            return object
        } else if createIfMissing {
            return add(manga: manga)
        }
        return nil
    }

    func getMangaObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) throws -> [MangaObject] {
        try fetch(
            request: MangaObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit
        )
    }
}

// MARK: - Chapters
extension DataManager {

    func add(chapter: Chapter, manga: Manga? = nil) -> ChapterObject? {
        let chapterObject = ChapterObject(context: container.viewContext)
        chapterObject.load(from: chapter)

        if let mangaObject = try? getMangaObjects(
            predicate: NSPredicate(format: "sourceId = %@ AND id = %@", chapter.sourceId, chapter.mangaId),
            limit: 1
        ).first {
            chapterObject.manga = mangaObject
        } else if let manga = manga, let mangaObject = getMangaObject(for: manga) {
            chapterObject.manga = mangaObject
        }

        guard save() else { return nil }

        return chapterObject
    }

    func set(chapters: [Chapter], for manga: Manga) {
        var newChapters = chapters
        let chapterObjects = getChapterObjects(for: manga)
        for object in chapterObjects {
            if let newChapter = chapters.first(where: { $0.id == object.id }) {
                object.load(from: newChapter)
                newChapters.removeAll { $0.id == object.id }
            } else {
                container.viewContext.delete(object)
            }
        }
        for chapter in newChapters {
            _ = getChapterObject(for: chapter, manga: manga)
        }
        _ = save()
    }

    func deleteChapters(for manga: Manga? = nil) {
        let chapters: [ChapterObject]
        if let manga = manga {
            chapters = getChapterObjects(for: manga)
        } else {
            chapters = (try? getChapterObjects()) ?? []
        }
        for chapter in chapters {
            container.viewContext.delete(chapter)
        }
        _ = save()
    }

    func clearChapters() {
        if let items = try? getChapterObjects() {
            for item in items {
                container.viewContext.delete(item)
            }
            _ = save()
        }
    }

    func getChapterObject(for chapter: Chapter, manga: Manga? = nil, createIfMissing: Bool = true) -> ChapterObject? {
        if let object = try? getChapterObjects(
            predicate: NSPredicate(
                format: "sourceId = %@ AND id = %@ AND mangaId = %@",
                chapter.sourceId, chapter.id, chapter.mangaId
            ),
            limit: 1
        ).first {
            return object
        } else if createIfMissing {
            return add(chapter: chapter, manga: manga)
        }
        return nil
    }

    func getChapterObject(for source: String, id: String, mangaId: String) -> ChapterObject? {
        try? getChapterObjects(
            predicate: NSPredicate(
                format: "sourceId = %@ AND id = %@ AND mangaId = %@",
                source, id, mangaId
            ),
            limit: 1
        ).first
    }

    func getChapterObjects(for manga: Manga) -> [ChapterObject] {
        getChapterObjects(sourceId: manga.sourceId, mangaId: manga.id)
    }
    func getChapterObjects(sourceId: String, mangaId: String) -> [ChapterObject] {
        (try? getChapterObjects(predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@", sourceId, mangaId),
                                sortDescriptors: [NSSortDescriptor(key: "sourceOrder", ascending: true)])) ?? []
    }

    func getChapterObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) throws -> [ChapterObject] {
        try fetch(
            request: ChapterObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit
        )
    }
}

// MARK: - Read History
// TODO: change function names
extension DataManager {

    func currentPage(for chapter: Chapter) -> Int {
        guard let historyObject = getHistoryObject(for: chapter, createIfMissing: false) else { return 0 }
        return Int(historyObject.progress)
    }

    func setCurrentPage(_ page: Int, for chapter: Chapter) {
        guard let historyObject = getHistoryObject(for: chapter) else { return }
        historyObject.progress = Int16(page)
        historyObject.dateRead = Date()
        _ = save()
    }

    func setCompleted(chapter: Chapter, date: Date = Date()) {
        guard let historyObject = getHistoryObject(for: chapter) else { return }
        historyObject.completed = true
        historyObject.dateRead = date
        _ = save()
        NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
    }

    func setCompleted(chapters: [Chapter], date: Date = Date()) {
        for chapter in chapters {
            if let historyObject = getHistoryObject(for: chapter) {
                historyObject.dateRead = date
                historyObject.completed = true
            }
        }
        _ = save()
        NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
    }

    func addHistory(for chapter: Chapter, page: Int? = nil, date: Date = Date()) {
        guard let historyObject = getHistoryObject(for: chapter) else { return }
        historyObject.dateRead = date
        if let page = page {
            historyObject.progress = Int16(page)
        }
        _ = save()
        NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
    }

    func removeHistory(for manga: Manga) {
        guard let readHistory = try? getReadHistory(
            predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@", manga.sourceId, manga.id)
        ) else { return }
        for historyObject in readHistory {
            container.viewContext.delete(historyObject)
        }
        _ = save()
        NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
    }

    func removeHistory(for chapter: Chapter) {
        guard let historyObject = getHistoryObject(for: chapter, createIfMissing: false) else { return }
        container.viewContext.delete(historyObject)
        _ = save()
        NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
    }

    func removeHistory(for chapters: [Chapter]) {
        for chapter in chapters {
            guard let historyObject = getHistoryObject(for: chapter, createIfMissing: false) else { continue }
            container.viewContext.delete(historyObject)
        }
        _ = save()
        NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
    }

    func clearHistory() {
        if let items = try? getReadHistory() {
            for item in items {
                container.viewContext.delete(item)
            }
            _ = save()
            NotificationCenter.default.post(name: Notification.Name("reloadLibrary"), object: nil)
        }
    }

    func getReadHistory(manga: Manga) -> [String: Int] {
        guard let readHistory = try? getReadHistory(
            predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@", manga.sourceId, manga.id),
            sortDescriptors: [NSSortDescriptor(key: "dateRead", ascending: false)]
        ) else { return [:] }

        var readHistoryDict: [String: Int] = [:]
        for history in readHistory {
            let chapterId = history.chapterId
            readHistoryDict[chapterId] = Int(history.dateRead.timeIntervalSince1970)
        }

        return readHistoryDict
    }

    func getHistoryObject(for chapter: Chapter, createIfMissing: Bool = true) -> HistoryObject? {
        if let historyObject = try? getReadHistory(
            predicate: NSPredicate(format: "sourceId = %@ AND chapterId = %@", chapter.sourceId, chapter.id),
            limit: 1
        ).first {
            return historyObject
        } else if createIfMissing {
            let readHistory = HistoryObject(context: container.viewContext)
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
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) throws -> [HistoryObject] {
        try fetch(
            request: HistoryObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit
        )
    }
}

// MARK: - Sources
extension DataManager {

    func add(source: Source) -> SourceObject? {
        if let sourceObject = getSourceObject(for: source, createIfMissing: false) {
            return sourceObject
        }

        let sourceObject = SourceObject(context: container.viewContext)
        sourceObject.load(from: source)

        guard save() else { return nil }

        return sourceObject
    }

    func delete(source: Source) {
        guard let sourceObject = getSourceObject(for: source, createIfMissing: false) else { return }
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

    func getSourceObject(for source: Source, createIfMissing: Bool = true) -> SourceObject? {
        if let object = try? getSourceObjects(
            predicate: NSPredicate(
                format: "id = %@",
                source.id
            ),
            limit: 1
        ).first {
            return object
        } else if createIfMissing {
            return add(source: source)
        }
        return nil
    }

    func getSourceObjects(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) throws -> [SourceObject] {
        try fetch(
            request: SourceObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit
        )
    }
}
