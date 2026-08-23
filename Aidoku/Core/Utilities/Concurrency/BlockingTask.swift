//
//  BlockingTask.swift
//  Aidoku
//
//  Created by Skitty on 5/8/25.
//

import Foundation

final class BlockingTask<T>: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private var result: T?

    init(block: @escaping @Sendable () async -> T) {
        Task {
            result = await block()
            semaphore.signal()
        }
    }

    func get() -> T {
        if let result { return result }
        semaphore.wait()
        return result!
    }
}

final class BlockingThrowingTask<T>: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private var result: T?
    private var error: Error?

    init(block: @escaping @Sendable () async throws -> T) {
        Task {
            do {
                result = try await block()
            } catch {
                self.error = error
            }
            semaphore.signal()
        }
    }

    func get() throws -> T {
        if let result { return result }
        semaphore.wait()
        if let error {
            throw error
        }
        return result!
    }
}
