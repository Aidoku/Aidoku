//
//  DownloadManager.swift
//  Aidoku
//
//  Created by Skitty on 5/2/22.
//

import Foundation

/*
 File Structure:
   Downloads/
     sourceId/
       mangaId/
         chapterId/
           .metadata.json     Chapter info stored here     (title, chapter number, volume number, source order)
           001.png
           002.png
           ...
 */

// global class to manage downloads
@MainActor
class DownloadManager {
    static let shared = DownloadManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Downloads", isDirectory: true)

    private let cache: DownloadCache
    private let queue: DownloadQueue

    private(set) var downloadsPaused = false

    var ignoreConnectionType = false

    private static let allowedImageExtensions = Set(["jpg", "jpeg", "png", "webp", "gif", "heic"])

    init() {
        self.cache = DownloadCache()
        self.queue = DownloadQueue(cache: cache)
        if !Self.directory.exists {
            Self.directory.createDirectory()
        }
        Task {
            await self.queue.setOnCompletion { [weak self] in
                self?.invalidateDownloadedMangaCache()
            }
        }
    }

    func getDownloadQueue() async -> [String: [Download]] {
        await queue.queue
    }

    func getDownloadedPagesWithoutContents(for chapter: Chapter) -> [Page] {
        var descriptionFiles: [URL] = []

        var pages = cache.directory(for: chapter).contents
            .compactMap { url -> Page? in
                let imageURL: String?
                let text: String?
                if url.pathExtension == "txt" {
                    // add description file to list
                    if url.lastPathComponent.hasSuffix("desc.txt") {
                        descriptionFiles.append(url)
                        return nil
                    }
                    // otherwise, load file as text
                    imageURL = nil
                    text = try? String(contentsOf: url)
                } else if Self.allowedImageExtensions.contains(url.pathExtension) {
                    // load file as image
                    imageURL = url.absoluteString
                    text = nil
                } else {
                    return nil
                }
                return Page(
                    sourceId: chapter.sourceId,
                    chapterId: chapter.id,
                    index: (Int(url.deletingPathExtension().lastPathComponent) ?? 1) - 1,
                    imageURL: imageURL,
                    text: text,
                )
            }
            .sorted { $0.index < $1.index }

        // load descriptions from files
        for descriptionFile in descriptionFiles {
            guard
                let index = descriptionFile
                    .deletingPathExtension()
                    .lastPathComponent
                    .split(separator: ".")
                    .first
                    .flatMap({ Int($0) }),
                index > 0,
                index <= pages.count
            else { break }
            pages[index - 1].hasDescription = true
            pages[index - 1].description = try? String(contentsOf: descriptionFile)
        }

        return pages
    }

    func isChapterDownloaded(chapter: Chapter) -> Bool {
        cache.isChapterDownloaded(sourceId: chapter.sourceId, mangaId: chapter.mangaId, chapterId: chapter.id)
    }

    func isChapterDownloaded(sourceId: String, mangaId: String, chapterId: String) -> Bool {
        cache.isChapterDownloaded(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId)
    }

    func getDownloadStatus(for chapter: Chapter) -> DownloadStatus {
        if isChapterDownloaded(chapter: chapter) {
            return .finished
        } else {
            let tmpDirectory = cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
                .appendingSafePathComponent(".tmp_\(chapter.id)")
            if tmpDirectory.exists {
                return .downloading
            } else {
                return .none
            }
        }
    }

    func hasDownloadedChapter(sourceId: String, mangaId: String) -> Bool {
        cache.hasDownloadedChapter(sourceId: sourceId, mangaId: mangaId)
    }

    func hasQueuedDownloads() async -> Bool {
        await queue.hasQueuedDownloads()
    }

    func loadQueueState() async {
        await queue.loadQueueState()

        // fetch loaded downloads to notify ui about
        let downloads = await queue.queue.flatMap(\.value)
        if !downloads.isEmpty {
            NotificationCenter.default.post(name: NSNotification.Name("downloadsQueued"), object: downloads)
        }
    }
}

extension DownloadManager {

    func downloadAll(manga: Manga) async {
        let chapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceId, mangaId: manga.id)
            .filter {
                // filter out chapters that are locked and already downloaded
                !$0.locked && !isChapterDownloaded(chapter: $0)
            }
        download(chapters: chapters.reversed(), manga: manga)
    }

    func downloadUnread(manga: Manga) async {
        let readingHistory = await CoreDataManager.shared.getReadingHistory(sourceId: manga.sourceId, mangaId: manga.id)
        let chapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceId, mangaId: manga.id)
            .filter {
                (readingHistory[$0.id] == nil || readingHistory[$0.id]?.page != -1)
                    && !$0.locked && !isChapterDownloaded(chapter: $0)
            }
        download(chapters: chapters.reversed(), manga: manga)
    }

    func download(chapters: [Chapter], manga: Manga? = nil) {
        Task {
            let downloads = await queue.add(chapters: chapters, manga: manga, autoStart: true)
            NotificationCenter.default.post(
                name: NSNotification.Name("downloadsQueued"),
                object: downloads
            )
            // Invalidate cache since new downloads may affect the list
            invalidateDownloadedMangaCache()
        }
    }

    func delete(chapters: [Chapter]) {
        for chapter in chapters {
            cache.directory(for: chapter).removeItem()
            cache.remove(chapter: chapter)
            NotificationCenter.default.post(name: NSNotification.Name("downloadRemoved"), object: chapter)
        }
        // Invalidate cache for download manager UI
        invalidateDownloadedMangaCache()
    }

    func deleteChapters(for manga: Manga) {
        cache.directory(for: manga).removeItem()
        cache.remove(manga: manga)
        NotificationCenter.default.post(name: NSNotification.Name("downloadsRemoved"), object: manga)
        // Invalidate cache for download manager UI
        invalidateDownloadedMangaCache()
    }

    func deleteAll() {
        cache.removeAll()
    }

    func pauseDownloads() {
        Task {
            await queue.pause()
        }
        downloadsPaused = true
        NotificationCenter.default.post(name: Notification.Name("downloadsPaused"), object: nil)
        // Invalidate cache since paused state may affect display
        invalidateDownloadedMangaCache()
    }

    func resumeDownloads() {
        Task {
            await queue.resume()
        }
        downloadsPaused = false
        NotificationCenter.default.post(name: Notification.Name("downloadsResumed"), object: nil)
        // Invalidate cache since resumed state may affect display
        invalidateDownloadedMangaCache()
    }

    func cancelDownload(for chapter: Chapter) {
        Task {
            await queue.cancelDownload(for: chapter)
        }
        // Invalidate cache since cancelled downloads may affect display
        invalidateDownloadedMangaCache()
    }

    func cancelDownloads(for chapters: [Chapter] = []) {
        Task {
            if chapters.isEmpty {
                await queue.cancelAll()
            } else {
                await queue.cancelDownloads(for: chapters)
            }
        }
        downloadsPaused = false
        // Invalidate cache since cancelled downloads may affect display
        invalidateDownloadedMangaCache()
    }

    func onProgress(for chapter: Chapter, block: @escaping (Int, Int) -> Void) {
        Task {
            await queue.onProgress(for: chapter, block: block)
        }
    }

    func removeProgressBlock(for chapter: Chapter) {
        Task {
            await queue.removeProgressBlock(for: chapter)
        }
    }
}

// MARK: - Download Manager UI Support
extension DownloadManager {
    private static var downloadedMangaCache: [DownloadedMangaInfo] = []
    private static var lastCacheUpdate: Date = .distantPast
    private static let cacheValidityDuration: TimeInterval = 60 // 1 minute

    /// Get all downloaded manga with metadata from CoreData if available
    func getAllDownloadedManga() async -> [DownloadedMangaInfo] {
        // Return cached result if still valid
        let now = Date()
        if now.timeIntervalSince(Self.lastCacheUpdate) < Self.cacheValidityDuration {
            return Self.downloadedMangaCache
        }

        var downloadedManga: [DownloadedMangaInfo] = []

        // Ensure downloads directory exists
        guard Self.directory.exists else {
            Self.downloadedMangaCache = []
            Self.lastCacheUpdate = now
            return []
        }

        // Scan source directories
        let sourceDirectories = Self.directory.contents.filter { $0.isDirectory }

        for sourceDirectory in sourceDirectories {
            let sourceId = sourceDirectory.lastPathComponent
            let mangaDirectories = sourceDirectory.contents.filter { $0.isDirectory }

            for mangaDirectory in mangaDirectories {
                let mangaId = mangaDirectory.lastPathComponent

                // Count chapters and calculate total size
                let chapterDirectories = mangaDirectory.contents.filter {
                    $0.isDirectory && !$0.lastPathComponent.hasPrefix(".tmp")
                }

                guard !chapterDirectories.isEmpty else { continue }

                let totalSize = await calculateDirectorySize(mangaDirectory)
                let chapterCount = chapterDirectories.count

                // Try to load metadata from the manga directory first
                let storedMetadata = loadMangaMetadata(from: mangaDirectory)

                // Fallback to CoreData only if no stored metadata exists
                let mangaMetadata = if let storedMetadata {
                    (
                        title: storedMetadata.title,
                        coverUrl: storedMetadata.thumbnailBase64 != nil ?
                            "data:image;base64,\(storedMetadata.thumbnailBase64!)" : storedMetadata.cover,
                        isInLibrary: await withCheckedContinuation { continuation in
                            CoreDataManager.shared.container.performBackgroundTask { context in
                                let isInLibrary = CoreDataManager.shared.hasLibraryManga(
                                    sourceId: sourceId,
                                    mangaId: storedMetadata.mangaId ?? mangaId,
                                    context: context
                                )
                                continuation.resume(returning: isInLibrary)
                            }
                        },
                        actualMangaId: storedMetadata.mangaId ?? mangaId
                    )
                } else {
                    await withCheckedContinuation { continuation in
                        CoreDataManager.shared.container.performBackgroundTask { context in
                            // First try direct lookup with the directory name
                            var mangaObject = CoreDataManager.shared.getManga(
                                sourceId: sourceId,
                                mangaId: mangaId,
                                context: context
                            )
                            var isInLibrary = CoreDataManager.shared.hasLibraryManga(
                                sourceId: sourceId,
                                mangaId: mangaId,
                                context: context
                            )

                            // If not found, try to find a manga whose sanitized ID matches the directory name
                            if mangaObject == nil {
                                let allMangaForSource = CoreDataManager.shared.getManga(context: context)
                                    .filter { $0.sourceId == sourceId }

                                for candidateManga in allMangaForSource {
                                    let candidateId = candidateManga.id
                                    if candidateId.directoryName == mangaId {
                                        mangaObject = candidateManga
                                        isInLibrary = CoreDataManager.shared.hasLibraryManga(
                                            sourceId: sourceId,
                                            mangaId: candidateId,
                                            context: context
                                        )
                                        break
                                    }
                                }
                            }

                            let result = (
                                title: mangaObject?.title,
                                coverUrl: mangaObject?.cover,
                                isInLibrary: isInLibrary,
                                actualMangaId: mangaObject?.id ?? mangaId
                            )
                            continuation.resume(returning: result)
                        }
                    }
                }

                let downloadedMangaInfo = DownloadedMangaInfo(
                    sourceId: sourceId,
                    mangaId: mangaMetadata.actualMangaId, // Use the actual manga ID, not directory name
                    directoryMangaId: mangaId, // Keep directory name for file access
                    title: mangaMetadata.title,
                    coverUrl: mangaMetadata.coverUrl,
                    totalSize: totalSize,
                    chapterCount: chapterCount,
                    isInLibrary: mangaMetadata.isInLibrary
                )

                downloadedManga.append(downloadedMangaInfo)
            }
        }

        // Sort by source ID, then by title/manga ID
        downloadedManga.sort { lhs, rhs in
            if lhs.sourceId != rhs.sourceId {
                return lhs.sourceId < rhs.sourceId
            }
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }

        // Cache the result
        Self.downloadedMangaCache = downloadedManga
        Self.lastCacheUpdate = now

        return downloadedManga
    }

    /// Get downloaded chapters for a specific manga
    func getDownloadedChapters(for mangaInfo: DownloadedMangaInfo) async -> [DownloadedChapterInfo] {
        let mangaDirectory = Self.directory
            .appendingSafePathComponent(mangaInfo.sourceId)
            .appendingSafePathComponent(mangaInfo.directoryMangaId)

        guard mangaDirectory.exists else { return [] }

        let chapterDirectories = mangaDirectory.contents.filter {
            $0.isDirectory && !$0.lastPathComponent.hasPrefix(".tmp")
        }

        var chapters: [DownloadedChapterInfo] = []

        for chapterDirectory in chapterDirectories {
            let chapterId = chapterDirectory.lastPathComponent
            let size = await calculateDirectorySize(chapterDirectory)

            // Get directory creation date as download date
            let attributes = try? FileManager.default.attributesOfItem(atPath: chapterDirectory.path)
            let downloadDate = attributes?[.creationDate] as? Date

            // Try to load metadata from the chapter directory
            let metadata = loadChapterMetadata(from: chapterDirectory)

            let chapterInfo = DownloadedChapterInfo(
                chapterId: chapterId,
                title: metadata?.title,
                chapterNumber: metadata?.chapterNumber,
                volumeNumber: metadata?.volumeNumber,
                size: size,
                downloadDate: downloadDate
            )

            chapters.append(chapterInfo)
        }

        // Sort chapters by ID (which should correspond to chapter order)
        chapters.sort { lhs, rhs in
            // Try to sort numerically if possible, otherwise alphabetically
            if let lhsNum = Double(lhs.chapterId), let rhsNum = Double(rhs.chapterId) {
                return lhsNum < rhsNum
            }
            return lhs.chapterId.localizedStandardCompare(rhs.chapterId) == .orderedAscending
        }

        return chapters
    }

    /// Save chapter metadata when downloading
    func saveChapterMetadata(_ chapter: Chapter, to directory: URL) {
        let metadata = ChapterMetadata(
            title: chapter.title,
            chapterNumber: chapter.chapterNum,
            volumeNumber: chapter.volumeNum,
            sourceOrder: chapter.sourceOrder
        )

        let metadataURL = directory.appendingPathComponent(".metadata.json")

        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL)
        } catch {
            LogManager.logger.error("Failed to save chapter metadata: \(error)")
        }
    }

    /// Save manga metadata when first downloading from it
    func saveMangaMetadata(_ manga: Manga, to directory: URL) async {
        // Get the cover image and convert to base64
        var thumbnailBase64: String?
        if let coverUrl = manga.coverUrl {
            do {
                let (data, _) = try await URLSession.shared.data(from: coverUrl)
                thumbnailBase64 = data.base64EncodedString()
            } catch {
                LogManager.logger.error("Failed to download manga cover: \(error)")
            }
        }

        let metadata = MangaMetadata(
            mangaId: manga.id,
            title: manga.title,
            cover: manga.coverUrl?.absoluteString,
            thumbnailBase64: thumbnailBase64,
            description: manga.description
        )

        let metadataURL = directory.appendingPathComponent(".manga_metadata.json")

        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL)
        } catch {
            LogManager.logger.error("Failed to save manga metadata: \(error)")
        }
    }

    /// Load chapter metadata from directory
    private func loadChapterMetadata(from directory: URL) -> ChapterMetadata? {
        let metadataURL = directory.appendingPathComponent(".metadata.json")

        guard metadataURL.exists else { return nil }

        do {
            let data = try Data(contentsOf: metadataURL)
            return try JSONDecoder().decode(ChapterMetadata.self, from: data)
        } catch {
            LogManager.logger.error("Failed to load chapter metadata: \(error)")
            return nil
        }
    }

    /// Load manga metadata from directory
    private func loadMangaMetadata(from directory: URL) -> MangaMetadata? {
        let metadataURL = directory.appendingPathComponent(".manga_metadata.json")

        guard metadataURL.exists else { return nil }

        do {
            let data = try Data(contentsOf: metadataURL)
            return try JSONDecoder().decode(MangaMetadata.self, from: data)
        } catch {
            LogManager.logger.error("Failed to load manga metadata: \(error)")
            return nil
        }
    }

    /// Simple chapter metadata structure
    private struct ChapterMetadata: Codable {
        let title: String?
        let chapterNumber: Float?
        let volumeNumber: Float?
        let sourceOrder: Int
    }

    /// Simple manga metadata structure
    private struct MangaMetadata: Codable {
        let mangaId: String?
        let title: String?
        let cover: String?
        let thumbnailBase64: String?
        let description: String?
    }

    /// Calculate the total size of a directory in bytes
    private func calculateDirectorySize(_ directory: URL) async -> Int64 {
        guard directory.exists else { return 0 }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var totalSize: Int64 = 0

                if let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                            if resourceValues.isRegularFile == true {
                                totalSize += Int64(resourceValues.fileSize ?? 0)
                            }
                        } catch {
                            // Skip files that can't be accessed
                            continue
                        }
                    }
                }

                continuation.resume(returning: totalSize)
            }
        }
    }

    /// Delete chapters for a specific manga (used by download manager UI)
    func deleteChaptersForManga(_ mangaInfo: DownloadedMangaInfo) {
        let manga = Manga(sourceId: mangaInfo.sourceId, id: mangaInfo.directoryMangaId)
        deleteChapters(for: manga)

        // Invalidate cache
        Self.lastCacheUpdate = .distantPast
    }

    /// Delete a specific chapter (used by download manager UI)
    func deleteChapter(_ chapterInfo: DownloadedChapterInfo, from mangaInfo: DownloadedMangaInfo) {
        let chapter = Chapter(
            sourceId: mangaInfo.sourceId,
            id: chapterInfo.chapterId,
            mangaId: mangaInfo.directoryMangaId, // Use directory name for file system operations
            title: chapterInfo.title,
            sourceOrder: -1
        )
        delete(chapters: [chapter])

        // Invalidate cache
        Self.lastCacheUpdate = .distantPast
    }

    /// Get total size of all downloads
    func getTotalDownloadedSize() async -> Int64 {
        guard Self.directory.exists else { return 0 }
        return await calculateDirectorySize(Self.directory)
    }

    /// Get formatted total download size string
    func getFormattedTotalDownloadedSize() async -> String {
        let totalSize = await getTotalDownloadedSize()
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    /// Invalidate the downloaded manga cache (call when downloads are added/removed)
    func invalidateDownloadedMangaCache() {
        Self.lastCacheUpdate = .distantPast
    }
}
