//
//  EpubChapterCacheTests.swift
//  Aidoku
//

@testable import Aidoku
import Foundation
import Testing

struct EpubChapterCacheTests {
    /// A cached book is served without touching the network: the request here points at a port
    /// nothing listens on, so any fetch attempt would throw.
    @Test func cachedFileSkipsDownload() async throws {
        let sourceKey = "test-epub-cache"
        let chapterId = "cached-\(UUID().uuidString)"
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpubCache", isDirectory: true)
            .appendingPathComponent(sourceKey, isDirectory: true)
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
        let sourceKey = "test-epub-cache"
        let chapterId = "missing-\(UUID().uuidString)"
        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/unreachable")!)

        await #expect(throws: Error.self) {
            _ = try await EpubChapterCache.fetch(request: request, sourceKey: sourceKey, chapterId: chapterId)
        }

        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpubCache/\(sourceKey)/\(chapterId).epub")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
