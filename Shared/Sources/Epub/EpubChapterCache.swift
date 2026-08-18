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
    /// A book replaced on the server keeps being served from the previously downloaded file until
    /// the cache is purged; compare against the server's file size if that ever bites.
    static func fetch(request: URLRequest, sourceKey: String, chapterId: String) async throws -> URL {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw SourceError.message("EPUB_DOWNLOAD_FAILED")
        }
        let directory = cachesDirectory
            .appendingPathComponent("EpubCache", isDirectory: true)
            .appendingPathComponent(sanitized(sourceKey), isDirectory: true)
        let file = directory.appendingPathComponent("\(sanitized(chapterId)).epub")
        if FileManager.default.fileExists(atPath: file.path) {
            return file
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            LogManager.logger.error("Failed to download epub (HTTP \(response.statusCode)): \(request)")
            // Kavita gates its download endpoint behind the download role, and Komga behind the
            // file-download permission, so a forbidden response is a lasting property of the
            // account rather than something a retry or a fresh token can resolve.
            let error = switch response.statusCode {
                case 401: SourceError.message("NOT_LOGGED_IN")
                case 403: SourceError.message("EPUB_DOWNLOAD_FORBIDDEN")
                default: SourceError.message("EPUB_DOWNLOAD_FAILED")
            }
            throw error
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }

    /// A source key and a chapter id both become one path component, and neither is ours to trust:
    /// a separator in either would place the file outside the cache directory it belongs to.
    private static func sanitized(_ component: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_."))
        let cleaned = String(component.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        // A name of dots alone still traverses, and an empty one is not a name at all.
        return cleaned.allSatisfy({ $0 == "." }) ? "_\(cleaned)" : cleaned
    }
}
