//
//  EpubChapterCacheTests.swift
//  Aidoku
//

@testable import Aidoku
import Foundation
import Testing

struct EpubChapterCacheTests {
    /// Tests run in parallel and each one clears up after itself by deleting the directory
    /// belonging to its source, so no two may share a source key.
    private static func uniqueSourceKey() -> String {
        "test-epub-cache-\(UUID().uuidString)"
    }

    private static func cacheDirectory(for sourceKey: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpubCache", isDirectory: true)
            .appendingPathComponent(sourceKey, isDirectory: true)
    }

    /// A cached book is served without touching the network: the request here points at a port
    /// nothing listens on, so any fetch attempt would throw.
    @Test func cachedFileSkipsDownload() async throws {
        let sourceKey = Self.uniqueSourceKey()
        let chapterId = "cached-\(UUID().uuidString)"
        let directory = Self.cacheDirectory(for: sourceKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(chapterId).epub")
        try Data("stub".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: directory) }

        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/unreachable")!)
        let result = try await EpubChapterCache.fetch(request: request, sourceKey: sourceKey, chapterId: chapterId)

        #expect(result == file)
        #expect(try Data(contentsOf: result) == Data("stub".utf8))
    }

    /// A miss downloads, and a failing download leaves no file behind to be mistaken for a book.
    @Test func failedDownloadWritesNothing() async throws {
        let sourceKey = Self.uniqueSourceKey()
        let chapterId = "missing-\(UUID().uuidString)"
        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/unreachable")!)
        defer { try? FileManager.default.removeItem(at: Self.cacheDirectory(for: sourceKey)) }

        await #expect(throws: Error.self) {
            _ = try await EpubChapterCache.fetch(request: request, sourceKey: sourceKey, chapterId: chapterId)
        }

        let file = Self.cacheDirectory(for: sourceKey).appendingPathComponent("\(chapterId).epub")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// A chapter id is a server's string and becomes one path component, so a separator in it must
    /// not reach a file outside the source's own directory. The escaping id is planted with a real
    /// file at the location it would traverse to: resolving it would return that file, and closing
    /// the traversal leaves the fetch to miss the cache and fail against an unreachable host.
    @Test func aTraversingChapterIdStaysInsideTheCache() async throws {
        let sourceKey = Self.uniqueSourceKey()
        let directory = Self.cacheDirectory(for: sourceKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let escapedName = "escaped-\(UUID().uuidString)"
        let escapedFile = directory.deletingLastPathComponent().appendingPathComponent("\(escapedName).epub")
        try Data("outside".utf8).write(to: escapedFile)
        defer { try? FileManager.default.removeItem(at: escapedFile) }

        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/unreachable")!)
        await #expect(throws: Error.self) {
            _ = try await EpubChapterCache.fetch(
                request: request,
                sourceKey: sourceKey,
                chapterId: "../\(escapedName)"
            )
        }
        // The planted file is still the only thing at that path: nothing was served from it and
        // nothing overwrote it.
        #expect(try Data(contentsOf: escapedFile) == Data("outside".utf8))
    }
}
