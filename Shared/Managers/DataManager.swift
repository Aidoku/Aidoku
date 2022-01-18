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
    
    func contains(manga: Manga) -> Bool {
        self.manga.firstIndex { $0.provider == manga.provider && $0.id == manga.id } != nil
    }
    
    func add(manga: Manga) -> Bool {
        if contains(manga: manga) {
            return false
        }
        
        guard let encodedManga = try? JSONEncoder().encode(manga) else {
            return false
        }

        let entity = NSEntityDescription.entity(
            forEntityName: "MangaData",
            in: container.viewContext
        )!
        let mangaData = NSManagedObject(entity: entity, insertInto: container.viewContext)
        
        mangaData.setValue(manga.provider + "." + manga.id, forKey: "id")
        mangaData.setValue(manga.title, forKey: "title")
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
    
    func delete(manga: Manga) {
        do {
            let mangaDatas = try getLibrary(predicate: NSPredicate(format: "id = %@", manga.provider + "." + manga.id))
            
            guard let objectToDelete = mangaDatas.first else { return }
            container.viewContext.delete(objectToDelete)
            
            try container.viewContext.save()
            
            self.manga.removeAll {
                $0.provider == manga.provider && $0.id == manga.id
            }
        } catch let error as NSError {
            print("Could not delete. \(error), \(error.userInfo)")
        }
    }
    
    func setOpened(manga: Manga) {
        do {
            let mangaObjs = try getLibrary(predicate: NSPredicate(format: "id = %@", manga.provider + "." + manga.id))
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
                guard let newInfo = try? await SourceManager.shared.source(for: m.provider)?.getMangaDetails(manga: m) else { return m }
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
    
    func currentPage(manga: Manga, chapterId: String) -> Int {
        do {
            let mangaObjs = try getReadHistory(predicate: NSPredicate(format: "mangaId = %@ AND chapterId = %@", manga.provider + "." + manga.id, chapterId), limit: 1)
            guard let mangaObj = mangaObjs.first else { return 0 }
            return mangaObj.value(forKey: "currentPage") as? Int ?? 0
        } catch let error as NSError {
            print("Could not get read history. \(error), \(error.userInfo)")
            return 0
        }
    }
    
    func setCurrentPage(manga: Manga, chapter: Chapter, page: Int) {
        do {
            let mangaObjs = try getReadHistory(predicate: NSPredicate(format: "mangaId = %@ AND chapterId = %@", manga.provider + "." + manga.id, chapter.id), limit: 1)
            guard let mangaObj = mangaObjs.first else { return }
            mangaObj.setValue(page, forKey: "currentPage")
            mangaObj.setValue(Date().timeIntervalSince1970, forKey: "lastOpened")
            try container.viewContext.save()
        } catch let error as NSError {
            print("Could not update. \(error), \(error.userInfo)")
        }
    }
    
    func addReadHistory(manga: Manga, chapter: Chapter, page: Int = 0) {
        guard ((try? getReadHistory(predicate: NSPredicate(format: "mangaId = %@ AND chapterId = %@", manga.provider + "." + manga.id, chapter.id), limit: 1)) ?? []).count == 0 else { return } // Read history already exists, ignore.
        
        let entity = NSEntityDescription.entity(
            forEntityName: "ReadHistory",
            in: container.viewContext
        )!
        let readHistory = NSManagedObject(entity: entity, insertInto: container.viewContext)
        
        readHistory.setValue(manga.provider + "." + manga.id, forKey: "mangaId")
        readHistory.setValue(chapter.id, forKey: "chapterId")
        readHistory.setValue(page, forKey: "currentPage")
        readHistory.setValue(Date().timeIntervalSince1970, forKey: "lastOpened")
        
        save()
    }
    
    func removeHistory(manga: Manga, chapter: Chapter) {
        do {
            let history = try getReadHistory(predicate: NSPredicate(format: "mangaId = %@ AND chapterId = %@", manga.provider + "." + manga.id, chapter.id), limit: 1)
            guard let objectToDelete = history.first else { return }
            container.viewContext.delete(objectToDelete)
            try container.viewContext.save()
        } catch let error as NSError {
            print("Error while removing chapter history: \(error), \(error.userInfo)")
        }
    }
    
    func getReadHistory(manga: Manga) -> [String: Int] {
        guard let readHistory = try? getReadHistory(
            predicate: NSPredicate(format: "mangaId = %@", manga.provider + "." + manga.id),
            sortDescriptors: [NSSortDescriptor(key: "lastOpened", ascending: false)]
        ) else { return [:] }
        
        var readHistoryDict: [String: Int] = [:]
        for history in readHistory {
            let chapterId = history.value(forKey: "chapterId") as! String
            readHistoryDict[chapterId] = history.value(forKey: "lastOpened") as? Int
        }
        
        return readHistoryDict
    }
    
    func getReadHistory(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, limit: Int? = nil) throws -> [NSManagedObject] {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ReadHistory")
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
