//
//  Sequence.swift
//  Aidoku
//
//  Created by Skitty on 1/3/22.
//

import Foundation

extension Sequence where Self: Sendable, Element: Sendable {
    func concurrentMap<T: Sendable>(
        _ transform: @escaping (Element) async throws -> T
    ) async rethrows -> [T] {
        let tasks = map { element in
            Task {
                try await transform(element)
            }
        }
        return try await tasks.asyncMap { task in
            try await task.value
        }
    }

    func concurrentFilter(
        _ predicate: @escaping (Element) async -> Bool
    ) async -> [Element] {
        await withTaskGroup(of: Element?.self) { group in
            for element in self {
                group.addTask {
                    await predicate(element) ? element : nil
                }
            }

            var results: [Element] = []
            for await result in group {
                if let value = result {
                    results.append(value)
                }
            }
            return results
        }
    }
}

extension Sequence where Element: Sendable {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            try await values.append(transform(element))
        }

        return values
    }

    func asyncCompactMap<T>(
        _ transform: (Element) async throws -> T?
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            let result = try await transform(element)
            if let result {
                values.append(result)
            }
        }

        return values
    }

//    func asyncForEach(
//        _ operation: (Element) async throws -> Void
//    ) async rethrows {
//        for element in self {
//            try await operation(element)
//        }
//    }

//    func concurrentForEach(
//        _ operation: @escaping (Element) async -> Void
//    ) async {
//        // A task group automatically waits for all of its
//        // sub-tasks to complete, while also performing those
//        // tasks in parallel:
//        await withTaskGroup(of: Void.self) { group in
//            for element in self {
//                group.addTask {
//                    await operation(element)
//                }
//            }
//        }
//    }
}

extension Sequence where Iterator.Element: Hashable {
    func unique() -> [Iterator.Element] {
        var seen: Set<Iterator.Element> = []
        return filter { seen.insert($0).inserted }
    }
}
