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
        container = NSPersistentCloudKitContainer(name: "Aidoku")
        self.inMemory = inMemory
        setupContainer(cloudSync: NSUbiquitousKeyValueStore.default.bool(forKey: "cloudSync"))
        loadLibrary()
        
        NotificationCenter.default.addObserver(forName: Notification.Name("updateSourceList"), object: nil, queue: nil) { _ in
            Task {
                await self.updateLibrary()
            }
        }
    }
    
    func setupContainer(cloudSync: Bool = true) {
        container = NSPersistentCloudKitContainer(name: "Aidoku")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .overwriteMergePolicyType)
        
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if !cloudSync || inMemory {
            container.persistentStoreDescriptions.first?.cloudKitContainerOptions = nil
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error)")
            }
        }
    }
    
    func fetch<T>(request: NSFetchRequest<T>, predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, limit: Int? = nil) throws -> [T] {
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
        libraryManga.firstIndex { $0.sourceId == manga.sourceId && $0.id == manga.id } != nil
    }
    
    func addToLibrary(manga: Manga) -> LibraryMangaObject? {
        if libraryContains(manga: manga) { return getLibraryObject(for: manga, createIfMissing: false) }
        guard let mangaObject = getMangaObject(for: manga) else { return nil }
        
        let libraryObject = LibraryMangaObject(context: container.viewContext)
        libraryObject.manga = mangaObject
        
        guard save() else { return nil }
        loadLibrary()
        
        Task {
            let chapters = await getChapters(for: manga, fromSource: true)
            DispatchQueue.main.async {
                self.set(chapters: chapters, for: manga)
            }
        }
        
        return libraryObject
    }
    
    func setOpened(manga: Manga) {
        guard let libraryObject = getLibraryObject(for: manga, createIfMissing: false) else { return }
        libraryObject.lastOpened = Date()
        guard save() else { return }
        loadLibrary()
    }
    
    func loadLibrary() {
        guard let libraryObjects = try? getLibraryObjects(sortDescriptors: [NSSortDescriptor(key: "lastOpened", ascending: false)]) else { return }
        libraryManga = libraryObjects.map { (libraryObject) -> Manga in
            if let oldManga = libraryManga.first(where: { $0.sourceId == libraryObject.manga.sourceId && $0.id == libraryObject.manga.id }) {
                return oldManga
            }
            return libraryObject.manga.toManga()
        }
    }
    
    func getLatestMangaDetails() async {
        do {
            libraryManga = try await libraryManga.concurrentMap { manga in
                guard let newInfo = try? await SourceManager.shared.source(for: manga.sourceId)?.getMangaDetails(manga: manga) else { return manga }
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
    
    func updateLibrary() async {
        await getLatestMangaDetails()
        
        for manga in libraryManga {
            let chapters = await getChapters(for: manga, fromSource: true)
            DispatchQueue.main.async {
                if let mangaObject = self.getMangaObject(for: manga) {
                    if mangaObject.chapters?.count != chapters.count {
                        if chapters.count > mangaObject.chapters?.count ?? 0 {
                            mangaObject.libraryObject?.newChaptersCount = Int16(chapters.count - (mangaObject.chapters?.count ?? 0))
                        }
                        self.set(chapters: chapters, for: manga)
                    }
                    mangaObject.load(from: manga)
                    mangaObject.libraryObject?.lastUpdated = Date()
                    _ = self.save()
                }
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
    
    func getLibraryObjects(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, limit: Int? = nil) throws -> [LibraryMangaObject] {
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
    
    func getMangaObject(for manga: Manga, createIfMissing: Bool = true) -> MangaObject? {
        if let object = try? getMangaObjects(
            predicate: NSPredicate(
                format: "sourceId = %@ AND id = %@",
                manga.sourceId, manga.id
            ),
            limit: 1
        ).first {
            return object
        } else if createIfMissing {
            return add(manga: manga)
        }
        return nil
    }
    
    func getMangaObjects(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, limit: Int? = nil) throws -> [MangaObject] {
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
        
        if let mangaObject = try? getMangaObjects(predicate: NSPredicate(format: "sourceId = %@ AND id = %@", chapter.sourceId, chapter.mangaId), limit: 1).first {
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
        (try? getChapterObjects(predicate: NSPredicate(format: "sourceId = %@ AND mangaId = %@", manga.sourceId, manga.id), sortDescriptors: [NSSortDescriptor(key: "sourceOrder", ascending: true)])) ?? []
    }
    
    func getChapterObjects(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, limit: Int? = nil) throws -> [ChapterObject] {
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
    }
    
    func setCompleted(chapters: [Chapter], date: Date = Date()) {
        for chapter in chapters {
            if let historyObject = getHistoryObject(for: chapter) {
                historyObject.dateRead = date
                historyObject.completed = true
            }
        }
        _ = save()
    }
    
    func addHistory(for chapter: Chapter, page: Int? = nil) {
        guard let historyObject = getHistoryObject(for: chapter) else {
            return }
        historyObject.dateRead = Date()
        if let page = page {
            historyObject.progress = Int16(page)
        }
        _ = save()
    }
    
    func removeHistory(for chapter: Chapter) {
        guard let historyObject = getHistoryObject(for: chapter, createIfMissing: false) else { return }
        container.viewContext.delete(historyObject)
        _ = save()
    }
    
    func clearHistory() {
        if let items = try? getReadHistory() {
            for item in items {
                container.viewContext.delete(item)
            }
            _ = save()
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
        if let historyObject = try? getReadHistory(predicate: NSPredicate(format: "sourceId = %@ AND chapterId = %@", chapter.sourceId, chapter.id), limit: 1).first {
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
    
    func getReadHistory(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, limit: Int? = nil) throws -> [HistoryObject] {
        try fetch(
            request: HistoryObject.fetchRequest(),
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit
        )
    }
}
