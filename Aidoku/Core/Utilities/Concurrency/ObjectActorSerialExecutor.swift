//
//  ObjectActorSerialExecutor.swift
//  Aidoku
//
//  Created by Skitty on 6/10/25.
//

import CoreData

final class ObjectActorSerialExecutor: @unchecked Sendable, SerialExecutor {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func enqueue(_ job: UnownedJob) {
        self.context.perform {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
