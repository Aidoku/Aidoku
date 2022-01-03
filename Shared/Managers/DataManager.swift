//
//  DataManager.swift
//  Aidoku
//
//  Created by Skitty on 12/29/21.
//

import CoreData

class DataManager {
    
    static let shared = DataManager()
    
    var manga: [Manga] = []
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Aidoku")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
        loadLibrary()
    }
    
    func save() {
        let context = container.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error while saving context: \(error)")
            }
        }
    }
}

// MARK: - Manga Library
extension DataManager {
    
    func contains(id: String) -> Bool {
        manga.filter { $0.id == id }.isEmpty == false
    }
    
    func add(manga m: Manga) -> Bool {
        if contains(id: m.id) {
            return false
        }
        
        guard let encodedManga = try? JSONEncoder().encode(m) else {
            return false
        }

        let entity = NSEntityDescription.entity(
            forEntityName: "MangaData",
            in: container.viewContext
        )!
        let mangaData = NSManagedObject(entity: entity, insertInto: container.viewContext)
        
        mangaData.setValue(m.provider + "." + m.id, forKey: "id")
        mangaData.setValue(m.title, forKey: "title")
        mangaData.setValue(m.author, forKey: "author")
        mangaData.setValue(Date().timeIntervalSince1970, forKey: "lastOpened")
        mangaData.setValue(encodedManga, forKey: "payload")
        
        do {
            try container.viewContext.save()
            loadLibrary()
            return true
        } catch let error as NSError {
            print("Could not add. \(error), \(error.userInfo)")
            return false
        }
    }
    
    func deleteManga(_ m: Manga) {
        deleteManga(id: m.provider + "." + m.id)
    }
    
    func deleteManga(id: String) {
        do {
            let mangaDatas = try getLibrary(predicate: NSPredicate(format: "id = %@", id))
            
            guard let objectToDelete = mangaDatas.first else { return }
            container.viewContext.delete(objectToDelete)
            
            try container.viewContext.save()
            
            manga.removeAll {
                id.hasPrefix($0.provider) && id.hasSuffix($0.id)
            }
        } catch let error as NSError {
            print("Could not delete. \(error), \(error.userInfo)")
        }
    }
    
    func setMangaOpened(_ m: Manga) {
        setMangaOpened(id: m.provider + "." + m.id)
    }
    func setMangaOpened(id: String) {
        do {
            let mangaObjs = try getLibrary(predicate: NSPredicate(format: "id = %@", id))
            guard let mangaObj = mangaObjs.first else { return }
            mangaObj.setValue(Date().timeIntervalSince1970, forKey: "lastOpened")
            try container.viewContext.save()
            loadLibrary()
        } catch let error as NSError {
            print("Could not update. \(error), \(error.userInfo)")
        }
    }
    
    func loadLibrary() {
        do {
            let mangaDatas = try getLibrary(sortDescriptors: [NSSortDescriptor(key: "lastOpened", ascending: false)])
            manga = try mangaDatas.map { (mangaData) -> Manga in
                try JSONDecoder().decode(Manga.self, from: mangaData.value(forKey: "payload") as! Data)
            }
        } catch let error as NSError {
            print("Could not fetch. \(error), \(error.userInfo)")
        }
    }
    
    func getLibrary(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) throws -> [NSManagedObject] {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "MangaData")
        if let predicate = predicate {
            fetchRequest.predicate = predicate
        }
        if let sortDescriptors = sortDescriptors {
            fetchRequest.sortDescriptors = sortDescriptors
        }
        return try container.viewContext.fetch(fetchRequest)
    }
    
    func getLatestMangaDetails() async {
        do {
            manga = try await manga.concurrentMap { m in
                let provider = ProviderManager.shared.provider(for: m.provider)
                var newInfo = await provider.getMangaDetails(id: m.id)
                newInfo.thumbnailURL = await provider.getMangaCoverURL(manga: m)
                return m.copy(from: newInfo)
            }
        } catch {
            print("error: \(error)")
        }
    }
    
    func updateLibrary() async {
        do {
            try manga.forEach { m in
                let mangaObjs = try getLibrary(predicate: NSPredicate(format: "id = %@", m.provider + "." + m.id))
                if let mangaObj = mangaObjs.first, let encodedManga = try? JSONEncoder().encode(m) {
                    mangaObj.setValue(m.title, forKey: "title")
                    mangaObj.setValue(m.author, forKey: "author")
                    mangaObj.setValue(encodedManga, forKey: "payload")
                    try container.viewContext.save()
                }
            }
        } catch {
            print("error: \(error)")
        }
    }
    
    func clearLibrary() {
        do {
            let items = try getLibrary()
            for item in items {
                container.viewContext.delete(item)
            }
            try container.viewContext.save()
            manga = []
        } catch {
            print("Could not clear library. \(error)")
        }
    }
}

// MARK: - Read History
// TODO: change function names
extension DataManager {
    
    func currentPage(forManga manga: Manga, chapter: Chapter) -> Int {
        currentPage(forManga: manga.provider + "." + manga.id, chapter: chapter.id)
    }
    func currentPage(forManga mangaId: String, chapter chapterId: String) -> Int {
        do {
            let mangaObjs = try getReadHistory(predicate: NSPredicate(format: "mangaId = %@ AND chapterId = %@", mangaId, chapterId))
            guard let mangaObj = mangaObjs.first else { return 0 }
            return mangaObj.value(forKey: "currentPage") as? Int ?? 0
        } catch let error as NSError {
            print("Could not get read history. \(error), \(error.userInfo)")
            return 0
        }
    }
    
    func setCurrentPage(forManga manga: Manga, chapter: Chapter, page: Int) {
        setCurrentPage(forManga: manga.provider + "." + manga.id, chapter: chapter.id, page: page)
    }
    func setCurrentPage(forManga mangaId: String, chapter chapterId: String, page: Int) {
        do {
            let mangaObjs = try getReadHistory(predicate: NSPredicate(format: "mangaId = %@ AND chapterId = %@", mangaId, chapterId))
            guard let mangaObj = mangaObjs.first else { return }
            mangaObj.setValue(page, forKey: "currentPage")
            mangaObj.setValue(Date().timeIntervalSince1970, forKey: "lastOpened")
            try container.viewContext.save()
        } catch let error as NSError {
            print("Could not update. \(error), \(error.userInfo)")
        }
    }
    
    func addReadHistory(forManga manga: Manga, chapter: Chapter, page: Int = 0) {
        addReadHistory(forMangaId: manga.provider + "." + manga.id, chapterId: chapter.id, page: page)
    }
    func addReadHistory(forMangaId mangaId: String, chapterId: String, page: Int = 0) {
        guard ((try? getReadHistory(predicate: NSPredicate(format: "mangaId = %@ AND chapterId = %@", mangaId, chapterId))) ?? []).count == 0 else { return } // Read history already exists, ignore.
        
        let entity = NSEntityDescription.entity(
            forEntityName: "ReadHistory",
            in: container.viewContext
        )!
        let readHistory = NSManagedObject(entity: entity, insertInto: container.viewContext)
        
        readHistory.setValue(mangaId, forKey: "mangaId")
        readHistory.setValue(chapterId, forKey: "chapterId")
        readHistory.setValue(page, forKey: "currentPage")
        readHistory.setValue(Date().timeIntervalSince1970, forKey: "lastOpened")
        
        save()
    }
    
    func removeHistory(forChapterId id: String) {
        do {
            let history = try getReadHistory(predicate: NSPredicate(format: "chapterId = %@", id))
            guard let objectToDelete = history.first else { return }
            container.viewContext.delete(objectToDelete)
            try container.viewContext.save()
        } catch let error as NSError {
            print("Error while removing chapter history: \(error), \(error.userInfo)")
        }
    }
    
    func getReadHistory(forManga manga: Manga) -> [String: Bool] {
        getReadHistory(forMangaId: manga.provider + "." + manga.id)
    }
    func getReadHistory(forMangaId mangaId: String) -> [String: Bool] {
        guard let readHistory = try? getReadHistory(predicate: NSPredicate(format: "mangaId = %@", mangaId)) else { return [:] }
        
        var readHistoryDict: [String: Bool] = [:]
        for history in readHistory {
            let chapterId = history.value(forKey: "chapterId") as! String
            readHistoryDict[chapterId] = true
        }
        
        return readHistoryDict
    }
    
    func getReadHistory(predicate: NSPredicate? = nil) throws -> [NSManagedObject] {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ReadHistory")
        if let predicate = predicate {
            fetchRequest.predicate = predicate
        }
        return try container.viewContext.fetch(fetchRequest)
    }
    
    func clearHistory() {
        do {
            let items = try getReadHistory()
            for item in items {
                container.viewContext.delete(item)
            }
            try container.viewContext.save()
        } catch let error as NSError {
            print("Could not clear read history. \(error), \(error.userInfo)")
        }
    }
}
