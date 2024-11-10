//
//  NSPersistentContainer.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/12/22.
//

import CoreData

extension NSPersistentContainer {
    func performBackgroundTask<T: Sendable>(_ block: @escaping (NSManagedObjectContext) -> T) async -> T {
        await withCheckedContinuation({ continuation in
            self.performBackgroundTask { context in
                let result = block(context)
                continuation.resume(returning: result)
            }
        })
    }
}
