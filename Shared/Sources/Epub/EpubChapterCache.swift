//
//  EpubChapterCache.swift
//  Aidoku
//

import AidokuRunner
import Foundation

/// Downloads a server-side ePub once, so a remote book reads through the same pipeline as an
/// imported one: the source hands the reader `.zipFile` spine pages backed by the cached file.
///
/// The cache lives in the caches directory, so the system reclaims it under storage pressure and
/// the next read simply downloads again.
enum EpubChapterCache {
    // file until the cache is purged; compare against the server's file size if that ever bites
    static func fetch(request: URLRequest, sourceKey: String, chapterId: String) async throws -> URL {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw SourceError.message("MISSING_CACHES_DIRECTORY")
        }
        let directory = cachesDirectory
            .appendingPathComponent("EpubCache", isDirectory: true)
            .appendingPathComponent(sourceKey, isDirectory: true)
        let file = directory.appendingPathComponent("\(chapterId).epub")
        if FileManager.default.fileExists(atPath: file.path) {
            return file
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw SourceError.message("HTTP \(response.statusCode)")
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }
}
