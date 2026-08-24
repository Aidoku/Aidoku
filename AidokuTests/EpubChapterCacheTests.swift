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

    // MARK: - Eviction

    /// A directory of its own per test, since eviction reads a whole cache root and the suite runs
    /// its tests in parallel.
    private static func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EpubCacheEviction-\(UUID().uuidString)", isDirectory: true)
    }

    @discardableResult
    private static func plantBook(
        _ name: String,
        bytes: Int,
        accessed: Date,
        in directory: URL,
        sidecar: String? = nil
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var file = directory.appendingPathComponent("\(name).epub")
        try Data(count: bytes).write(to: file)
        if let sidecar {
            try Data(sidecar.utf8).write(to: file.appendingPathExtension("lastmodified"))
        }
        var values = URLResourceValues()
        values.contentAccessDate = accessed
        try file.setResourceValues(values)
        return file
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func accessDate(of url: URL) -> Date? {
        try? URL(fileURLWithPath: url.path)
            .resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
    }

    /// Books go in order of how long ago they were read, and only as far as the capacity requires.
    @Test func evictionRemovesTheLeastRecentlyReadFirst() throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("source", isDirectory: true)

        let now = Date()
        let oldest = try Self.plantBook("oldest", bytes: 400, accessed: now.addingTimeInterval(-3600), in: directory)
        let middle = try Self.plantBook("middle", bytes: 400, accessed: now.addingTimeInterval(-60), in: directory)
        let newest = try Self.plantBook("newest", bytes: 400, accessed: now, in: directory)

        EpubChapterCache.evict(in: root, capacity: 1000, keeping: nil)

        #expect(!Self.exists(oldest))
        #expect(Self.exists(middle))
        #expect(Self.exists(newest))
    }

    /// A cache already within its capacity is left alone.
    @Test func evictionLeavesACacheUnderCapacityAlone() throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("source", isDirectory: true)

        let book = try Self.plantBook("book", bytes: 400, accessed: .distantPast, in: directory, sidecar: "Tue")

        EpubChapterCache.evict(in: root, capacity: 1000, keeping: nil)

        #expect(Self.exists(book))
        #expect(Self.exists(book.appendingPathExtension("lastmodified")))
    }

    /// A chapter is two files, and the one describing the book is not a book: it must go with what
    /// it describes, and must never be counted or chosen as a victim itself.
    @Test func evictionTakesTheSidecarWithItsBook() throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("source", isDirectory: true)

        let old = try Self.plantBook("old", bytes: 800, accessed: .distantPast, in: directory, sidecar: "Mon")
        let new = try Self.plantBook("new", bytes: 800, accessed: Date(), in: directory, sidecar: "Tue")

        EpubChapterCache.evict(in: root, capacity: 1000, keeping: nil)

        #expect(!Self.exists(old))
        #expect(!Self.exists(old.appendingPathExtension("lastmodified")))
        #expect(Self.exists(new))
        #expect(Self.exists(new.appendingPathExtension("lastmodified")))
    }

    /// The book about to be read survives even when it alone exceeds the capacity, since evicting
    /// it would mean downloading it again on the next open and every open after that.
    @Test func evictionSparesTheBookBeingRead() throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("source", isDirectory: true)

        let reading = try Self.plantBook("reading", bytes: 2000, accessed: .distantPast, in: directory)
        let other = try Self.plantBook("other", bytes: 400, accessed: Date(), in: directory)

        EpubChapterCache.evict(in: root, capacity: 1000, keeping: reading)

        #expect(Self.exists(reading))
        #expect(!Self.exists(other))
    }

    /// `pages` discards a book that holds nothing readable and leaves its sidecar behind, so the
    /// pass that walks the cache is where that orphan is cleared.
    @Test func evictionClearsSidecarsWhoseBookIsGone() throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let orphan = directory.appendingPathComponent("gone.epub.lastmodified")
        try Data("Mon".utf8).write(to: orphan)
        let kept = try Self.plantBook("kept", bytes: 10, accessed: Date(), in: directory, sidecar: "Tue")

        EpubChapterCache.evict(in: root, capacity: 1000, keeping: nil)

        #expect(!Self.exists(orphan))
        #expect(Self.exists(kept.appendingPathExtension("lastmodified")))
    }

    /// Eviction orders by an access time this cache writes itself, so serving a book from the
    /// cache has to move it. The request points at a port nothing listens on, which is a cache hit:
    /// a server that cannot be reached leaves the cached book readable.
    @Test func readingACachedBookMarksItRecentlyUsed() async throws {
        let sourceKey = Self.uniqueSourceKey()
        let chapterId = "accessed-\(UUID().uuidString)"
        let directory = Self.cacheDirectory(for: sourceKey)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try Self.plantBook(chapterId, bytes: 4, accessed: .distantPast, in: directory)

        // Read through a fresh URL each time: a URL caches the resource values it has been given,
        // so the one that planted the date answers with it rather than with what is on disk.
        let before = try #require(Self.accessDate(of: file))
        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/unreachable")!)
        _ = try await EpubChapterCache.fetch(request: request, sourceKey: sourceKey, chapterId: chapterId)

        let after = try #require(Self.accessDate(of: file))
        #expect(after > before)
    }
}
