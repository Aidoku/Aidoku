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

        // A book arrives whole or not at all. A part of one left at `file` would be served from
        // then on as though it were the book: `EpubParser` would fail to read it, the reader would
        // report a chapter that cannot be loaded, and no retry would ever get past the cache.
        do {
            try await URLSession.shared.download(for: request, to: file)
        } catch let error as URLSession.URLSessionError {
            guard case .httpError(let statusCode) = error else { throw error }
            LogManager.logger.error("Failed to download epub (HTTP \(statusCode)): \(request)")
            // Kavita gates its download endpoint behind the download role, and Komga behind the
            // file-download permission, so a forbidden response is a lasting property of the
            // account rather than something a retry or a fresh token can resolve.
            let sourceError = switch statusCode {
                case 401: SourceError.message("NOT_LOGGED_IN")
                case 403: SourceError.message("EPUB_DOWNLOAD_FORBIDDEN")
                default: SourceError.message("EPUB_DOWNLOAD_FAILED")
            }
            throw sourceError
        }
        return file
    }

    /// Fetches the book unless it is already cached, and reads the spine pages out of it.
    ///
    /// A cached file is trusted only as far as it parses. A body that arrived complete without
    /// being a book, which is what a proxy's error page or a wrapper around the file looks like,
    /// would otherwise be served from the cache for ever: `EpubParser` reports no pages rather than
    /// an error, so the chapter would read as empty on every open with nothing able to retry it.
    static func pages(
        request: URLRequest,
        sourceKey: String,
        chapterId: String
    ) async throws -> [AidokuRunner.Page] {
        let file = try await fetch(request: request, sourceKey: sourceKey, chapterId: chapterId)
        let pages = LocalFileManager.shared.readEpubPages(from: file)
        guard !pages.isEmpty else {
            // Discarded rather than kept, so that opening the chapter again downloads it again.
            try? FileManager.default.removeItem(at: file)
            LogManager.logger.error("Cached epub holds no readable pages, discarded: \(file)")
            throw SourceError.message("EPUB_DOWNLOAD_FAILED")
        }
        return pages
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
