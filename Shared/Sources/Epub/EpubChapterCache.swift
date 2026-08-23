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
    /// A book replaced on the server must not keep being served from the previously downloaded
    /// file, so a cache hit is first checked against the server's file size.
    static func fetch(request: URLRequest, sourceKey: String, chapterId: String) async throws -> URL {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw SourceError.message("EPUB_DOWNLOAD_FAILED")
        }
        let directory = cachesDirectory
            .appendingPathComponent("EpubCache", isDirectory: true)
            .appendingPathComponent(sanitized(sourceKey), isDirectory: true)
        let file = directory.appendingPathComponent("\(sanitized(chapterId)).epub")
        if FileManager.default.fileExists(atPath: file.path), await !isStale(request: request, file: file) {
            return file
        }

        // A book arrives whole or not at all. A part of one left at `file` would be served from
        // then on as though it were the book: `EpubParser` would fail to read it, the reader would
        // report a chapter that cannot be loaded, and no retry would ever get past the cache.
        do {
            let response = try await URLSession.shared.download(for: request, to: file)
            // The header is kept verbatim rather than parsed: staleness is "the server says
            // something different than it said when this file was downloaded", which string
            // equality answers without caring how the server formats its dates.
            if let lastModified = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified") {
                try? lastModified.write(to: lastModifiedSidecar(for: file), atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: lastModifiedSidecar(for: file))
            }
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

    /// Whether the server holds a different file than the cached one, judged via a HEAD request
    /// by Last-Modified against what the download reported, and by size against the file itself.
    /// A server that cannot answer — offline, erroring, or without HEAD support — keeps the
    /// cached book readable rather than making freshness a requirement for reading at all.
    // ponytail: a replacement with identical size and Last-Modified slips through — compare
    // ETag if that ever bites.
    private static func isStale(request: URLRequest, file: URL) async -> Bool {
        var head = request
        head.httpMethod = "HEAD"
        guard
            let (_, response) = try? await URLSession.shared.data(for: head),
            let response = response as? HTTPURLResponse,
            response.statusCode == 200
        else { return false }
        if let stored = try? String(contentsOf: lastModifiedSidecar(for: file), encoding: .utf8),
           let server = response.value(forHTTPHeaderField: "Last-Modified"),
           stored != server {
            return true
        }
        guard response.expectedContentLength > 0 else { return false }
        let cachedSize = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int64
        return cachedSize != response.expectedContentLength
    }

    /// Where the Last-Modified value the book was downloaded with lives, next to the book itself
    /// so the two are kept or reclaimed together.
    private static func lastModifiedSidecar(for file: URL) -> URL {
        file.appendingPathExtension("lastmodified")
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
