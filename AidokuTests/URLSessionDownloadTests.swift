//
//  URLSessionDownloadTests.swift
//  Aidoku
//

@testable import Aidoku
import Foundation
import Testing

struct URLSessionDownloadTests {
    /// A directory of this test's own, so tests running in parallel cannot disturb each other.
    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("URLSessionDownloadTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The body reaches the destination, and the intermediate directories it needs are created.
    @Test func downloadWritesTheBodyToTheDestination() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.epub")
        try Data("a whole book".utf8).write(to: source)
        let destination = directory.appendingPathComponent("nested/inner/book.epub")

        try await URLSession.shared.download(for: URLRequest(url: source), to: destination)

        #expect(try Data(contentsOf: destination) == Data("a whole book".utf8))
    }

    /// A destination that already holds a file is replaced rather than refused.
    @Test func downloadReplacesAnExistingFile() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.epub")
        try Data("the new book".utf8).write(to: source)
        let destination = directory.appendingPathComponent("book.epub")
        try Data("the old book".utf8).write(to: destination)

        try await URLSession.shared.download(for: URLRequest(url: source), to: destination)

        #expect(try Data(contentsOf: destination) == Data("the new book".utf8))
    }

    /// A download that fails leaves the destination as it found it. This is the property the cache
    /// depends on: a half-written file at that path would be served from then on as a whole book.
    @Test func aFailedDownloadLeavesTheDestinationAlone() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("book.epub")
        try Data("the book already here".utf8).write(to: destination)

        // Nothing listens on this port, so the request cannot complete.
        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/unreachable")!)
        await #expect(throws: Error.self) {
            try await URLSession.shared.download(for: request, to: destination)
        }

        #expect(try Data(contentsOf: destination) == Data("the book already here".utf8))
    }

    /// A destination that was not there before a failed download is still not there afterwards.
    @Test func aFailedDownloadCreatesNothing() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("book.epub")
        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/unreachable")!)

        await #expect(throws: Error.self) {
            try await URLSession.shared.download(for: request, to: destination)
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
