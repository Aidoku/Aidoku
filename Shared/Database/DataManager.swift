//
//  DataManager.swift
//  Aidoku
//
//  Created by Skitty on 12/29/21.
//

import CoreData

class DataManager {
    
    static let shared = DataManager()
    
    let container: NSPersistentContainer
    
    var libraryManga: [Manga] = []
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Aidoku")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error)")
            }
        }
        loadLibrary()
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
            await updateLibrary()
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
            libraryObject.manga.toManga()
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
                let mangaObject = self.getMangaObject(for: manga)
                if mangaObject?.chapters?.count != chapters.count {
                    self.set(chapters: chapters, for: manga)
                }
                if let mangaObject = mangaObject {
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
        
        _  = save()
        
        libraryManga.removeAll {
            $0.sourceId == manga.sourceId && $0.id == manga.id
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
                format: "sourceId = %@ AND id = %@",
                chapter.sourceId, chapter.id
            ),
            limit: 1
        ).first {
            return object
        } else if createIfMissing {
            return add(chapter: chapter, manga: manga)
        }
        return nil
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
        guard let chapterObject = getChapterObject(for: chapter, createIfMissing: false) else { return 0 }
        return Int(chapterObject.progress)
    }
    
    func setCurrentPage(_ page: Int, for chapter: Chapter) {
        guard let chapterObject = getChapterObject(for: chapter) else { return }
        chapterObject.progress = Int16(page)
        chapterObject.history?.dateRead = Date()
        _ = save()
    }
    
    func setCompleted(chapter: Chapter) {
        guard let historyObject = getHistoryObject(for: chapter) else { return }
        historyObject.chapter.read = true
        historyObject.dateRead = Date()
        _ = save()
    }
    
    func addHistory(for chapter: Chapter, page: Int? = nil) {
        guard let historyObject = getHistoryObject(for: chapter) else { print("ayo")
            return }
        historyObject.dateRead = Date()
        if let page = page {
            historyObject.chapter.progress = Int16(page)
        }
        _ = save()
    }
    
    func removeHistory(for chapter: Chapter) {
        guard let chapterObject = getChapterObject(for: chapter) else { return }
        chapterObject.read = false
        chapterObject.progress = 0
        if let history = chapterObject.history {
            container.viewContext.delete(history)
        }
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
            predicate: NSPredicate(format: "chapter.sourceId = %@ AND chapter.mangaId = %@", manga.sourceId, manga.id),
            sortDescriptors: [NSSortDescriptor(key: "dateRead", ascending: false)]
        ) else { return [:] }
        
        var readHistoryDict: [String: Int] = [:]
        for history in readHistory {
            let chapterId = history.chapter.id
            readHistoryDict[chapterId] = Int(history.dateRead.timeIntervalSince1970)
        }
        
        return readHistoryDict
    }
    
    func getHistoryObject(for chapter: Chapter, createIfMissing: Bool = true) -> HistoryObject? {
        if let historyObject = try? getReadHistory(predicate: NSPredicate(format: "chapter.sourceId = %@ AND chapter.id = %@", chapter.sourceId, chapter.id), limit: 1).first {
            return historyObject
        } else if createIfMissing, let chapterObject = getChapterObject(for: chapter) {
            let readHistory = HistoryObject(context: container.viewContext)
            readHistory.dateRead = Date()
            readHistory.chapter = chapterObject
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
