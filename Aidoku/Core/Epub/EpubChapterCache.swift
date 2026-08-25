//
//  EpubChapterCache.swift
//  Aidoku
//

import AidokuRunner
import Foundation

// downloads a server-side epub once so it reads through the same pipeline as an imported one
enum EpubChapterCache {
    static func fetch(request: URLRequest, sourceKey: String, chapterId: String) async throws -> URL {
        guard let root = directory else {
            throw SourceError.message("EPUB_DOWNLOAD_FAILED")
        }
        let file = root
            .appendingPathComponent(sanitized(sourceKey), isDirectory: true)
            .appendingPathComponent("\(sanitized(chapterId)).epub")
        if FileManager.default.fileExists(atPath: file.path), await !isStale(request: request, file: file) {
            markAccessed(file)
            return file
        }

        // a partial file would be served as the book, and no retry would get past the cache
        do {
            let response = try await URLSession.shared.download(for: request, to: file)
            if let lastModified = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified") {
                try? lastModified.write(to: lastModifiedSidecar(for: file), atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: lastModifiedSidecar(for: file))
            }
        } catch let error as URLSession.URLSessionError {
            guard case .httpError(let statusCode) = error else { throw error }
            LogManager.logger.error("Failed to download epub (HTTP \(statusCode)): \(request)")
            let sourceError = switch statusCode {
                case 401: SourceError.message("NOT_LOGGED_IN")
                case 403: SourceError.message("EPUB_DOWNLOAD_FORBIDDEN")
                default: SourceError.message("EPUB_DOWNLOAD_FAILED")
            }
            throw sourceError
        }
        markAccessed(file)
        evict(in: root, capacity: capacity, keeping: file)
        return file
    }

    static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EpubCache", isDirectory: true)
    }

    static var totalSize: Int {
        guard
            let directory,
            let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static let capacity = 500 * 1024 * 1024

    // keeping is never a victim, or a book larger than the capacity downloads again on every open
    static func evict(in root: URL, capacity: Int, keeping: URL?) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentAccessDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys) else { return }

        var books: [CachedBook] = []
        var total = 0
        for case let url as URL in enumerator {
            guard url.pathExtension == "epub" else {
                if url.pathExtension == "lastmodified",
                   !manager.fileExists(atPath: url.deletingPathExtension().path) {
                    try? manager.removeItem(at: url)
                }
                continue
            }
            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true,
                let size = values.fileSize
            else { continue }
            total += size
            books.append(CachedBook(url: url, size: size, accessed: values.contentAccessDate ?? .distantPast))
        }
        guard total > capacity else { return }

        for book in books.sorted(by: { $0.accessed < $1.accessed }) where total > capacity {
            guard book.url != keeping else { continue }
            try? manager.removeItem(at: book.url)
            try? manager.removeItem(at: lastModifiedSidecar(for: book.url))
            total -= book.size
        }
    }

    private struct CachedBook {
        let url: URL
        let size: Int
        let accessed: Date
    }

    private static func markAccessed(_ file: URL) {
        var file = file
        var values = URLResourceValues()
        values.contentAccessDate = Date()
        try? file.setResourceValues(values)
    }

    // trusted only as far as it parses: a complete body that is not a book, such as a proxy error
    // page, would be served for ever, EpubParser reporting no pages rather than an error
    static func pages(
        request: URLRequest,
        sourceKey: String,
        chapterId: String
    ) async throws -> [AidokuRunner.Page] {
        let file = try await fetch(request: request, sourceKey: sourceKey, chapterId: chapterId)
        let pages = LocalFileManager.shared.readEpubPages(from: file)
        guard !pages.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            LogManager.logger.error("Cached epub holds no readable pages, discarded: \(file)")
            throw SourceError.message("EPUB_DOWNLOAD_FAILED")
        }
        return pages
    }

    // a server that cannot answer keeps the cached book readable rather than making freshness a
    // requirement for reading. a replacement of identical size and date slips through
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

    private static func lastModifiedSidecar(for file: URL) -> URL {
        file.appendingPathExtension("lastmodified")
    }

    private static func sanitized(_ component: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_."))
        let cleaned = String(component.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.allSatisfy({ $0 == "." }) ? "_\(cleaned)" : cleaned
    }
}
