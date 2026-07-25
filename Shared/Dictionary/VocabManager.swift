//
//  VocabManager.swift
//  Aidoku
//
//  Created by skitty on 7/20/26.
//

import CoreData
import Foundation

final actor VocabManager {
    static let shared = VocabManager()

    private let context: NSManagedObjectContext
    private let objectExecutor: ObjectActorSerialExecutor
    public nonisolated let unownedExecutor: UnownedSerialExecutor

    init() {
        context = CoreDataManager.shared.container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        self.objectExecutor = ObjectActorSerialExecutor(context: context)
        self.unownedExecutor = objectExecutor.asUnownedSerialExecutor()
    }
}

extension VocabManager {
    func has(word: String, reading: String? = nil) -> Bool {
        CoreDataManager.shared.hasVocab(word: word, reading: reading, context: context)
    }

    func create(entry: VocabEntry) {
        CoreDataManager.shared.createVocab(entry: entry, context: context)
        do {
            try context.save()
            NotificationCenter.default.post(name: .dictionaryVocabChanged, object: nil)
        } catch {
            LogManager.logger.error("Failed to create vocab entry: \(error)")
        }
    }

    func delete(entry: VocabEntry) {
        CoreDataManager.shared.removeVocab(
            word: entry.word,
            reading: entry.reading,
            context: context
        )
        do {
            try context.save()
            NotificationCenter.default.post(name: .dictionaryVocabChanged, object: nil)
        } catch {
            LogManager.logger.error("Failed to delete vocab entry: \(error)")
        }
    }

    func update(entry: VocabEntry) {
        let object = CoreDataManager.shared.getVocab(
            word: entry.word,
            reading: entry.reading,
            context: context
        )
        object?.load(from: entry)
        do {
            try context.save()
            NotificationCenter.default.post(name: .dictionaryVocabChanged, object: nil)
        } catch {
            LogManager.logger.error("Failed to update vocab entry: \(error)")
        }
    }

    func get(word: String, reading: String? = nil) -> VocabEntry? {
        let object = CoreDataManager.shared.getVocab(word: word, reading: reading, context: context)
        return object?.toEntry()
    }

    func getEntries() -> [VocabEntry] {
        let objects = CoreDataManager.shared.getVocab(context: context)
        return objects.compactMap { $0.toEntry() }
    }
}
