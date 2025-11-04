//
//  DownloadManager.swift
//  Aidoku
//
//  Created by Skitty on 5/2/22.
//

import AidokuRunner
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
actor DownloadManager {
    static let shared = DownloadManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Downloads", isDirectory: true)

    nonisolated let cache: DownloadCache
    private let queue: DownloadQueue

    var ignoreConnectionType = false

    private static let allowedImageExtensions = Set(["jpg", "jpeg", "png", "webp", "gif", "heic"])

    // for download manager UI
    private var downloadedMangaCache: [DownloadedMangaInfo] = []
    private var lastCacheUpdate: Date = .distantPast
    private let cacheValidityDuration: TimeInterval = 60 // 1 minute

    init() {
        self.cache = DownloadCache()
        self.queue = DownloadQueue(cache: cache)
        if !Self.directory.exists {
            Self.directory.createDirectory()
        }
        Task {
            await self.queue.setOnCompletion { @Sendable [weak self] in
                Task { @MainActor in
                    await self?.invalidateDownloadedMangaCache()
                }
            }
        }
    }

    func loadQueueState() async {
        await queue.loadQueueState()

        // fetch loaded downloads to notify ui about
        let downloads = await queue.queue.flatMap(\.value)
        if !downloads.isEmpty {
            NotificationCenter.default.post(name: .downloadsQueued, object: downloads)
        }
    }

    func getDownloadedPages(for chapter: ChapterIdentifier) async -> [Page] {
        var descriptionFiles: [URL] = []

        var pages = await cache.directory(for: chapter).contents
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
                    sourceId: chapter.sourceKey,
                    chapterId: chapter.chapterKey,
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

    @MainActor
    func isChapterDownloaded(chapter: ChapterIdentifier) -> Bool {
        cache.isChapterDownloaded(identifier: chapter)
    }

    @MainActor
    func hasDownloadedChapter(from identifier: MangaIdentifier) -> Bool {
        cache.hasDownloadedChapter(from: identifier)
    }

    func hasQueuedDownloads() async -> Bool {
        await queue.hasQueuedDownloads()
    }

    @MainActor
    func getDownloadStatusSync(for chapter: ChapterIdentifier) -> DownloadStatus {
        if isChapterDownloaded(chapter: chapter) {
            return .finished
        } else {
            let tmpDirectory = cache.directory(for: chapter.mangaIdentifier)
                .appendingSafePathComponent(".tmp_\(chapter.chapterKey)")
            if tmpDirectory.exists {
                return .downloading
            } else {
                return .none
            }
        }
    }

    func getDownloadStatus(for chapter: ChapterIdentifier) async -> DownloadStatus {
        await getDownloadStatusSync(for: chapter)
    }
}

// MARK: File Management

extension DownloadManager {
    /// Download all chapters for a manga.
    func downloadAll(manga: AidokuRunner.Manga) async {
        let allChapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceKey, mangaId: manga.key)

        var chaptersToDownload: [AidokuRunner.Chapter] = []

        for chapter in allChapters {
            guard !chapter.locked else { continue }
            let downloaded = await isChapterDownloaded(chapter: chapter.identifier)
            if !downloaded {
                chaptersToDownload.append(chapter.toNew())
            }
        }

        await download(manga: manga, chapters: chaptersToDownload.reversed())
    }

    /// Download unread chapters for a manga.
    func downloadUnread(manga: AidokuRunner.Manga) async {
        let readingHistory = await CoreDataManager.shared.getReadingHistory(sourceId: manga.sourceKey, mangaId: manga.key)
        let allChapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceKey, mangaId: manga.key)

        var chaptersToDownload: [AidokuRunner.Chapter] = []

        for chapter in allChapters {
            guard !chapter.locked else { continue }
            let isUnread = readingHistory[chapter.id] == nil || readingHistory[chapter.id]?.page != -1
            guard isUnread else { continue }
            let downloaded = await isChapterDownloaded(chapter: chapter.identifier)
            if !downloaded {
                chaptersToDownload.append(chapter.toNew())
            }
        }

        await download(manga: manga, chapters: chaptersToDownload.reversed())
    }

    /// Download given chapters from a manga.
    func download(manga: AidokuRunner.Manga, chapters: [AidokuRunner.Chapter]) async {
        let downloads = await queue.add(chapters: chapters, manga: manga, autoStart: true)
        NotificationCenter.default.post(
            name: .downloadsQueued,
            object: downloads
        )
        // Invalidate cache since new downloads may affect the list
        await invalidateDownloadedMangaCache()
    }

    /// Remove downloads for specified chapters.
    func delete(chapters: [ChapterIdentifier]) async {
        for chapter in chapters {
            await cache.directory(for: chapter).removeItem()
            await cache.remove(chapter: chapter)
            NotificationCenter.default.post(name: .downloadRemoved, object: chapter)
        }
        // Invalidate cache for download manager UI
        await invalidateDownloadedMangaCache()
    }

    /// Remove all downloads from a manga.
    func deleteChapters(for manga: MangaIdentifier) async {
        await cache.directory(for: manga).removeItem()
        await cache.remove(manga: manga)
        NotificationCenter.default.post(name: .downloadsRemoved, object: manga)
        // Invalidate cache for download manager UI
        await invalidateDownloadedMangaCache()
    }

    /// Remove all downloads.
    func deleteAll() async {
        await cache.removeAll()
    }
}

// MARK: Queue Control

extension DownloadManager {
    func isQueuePaused() async -> Bool {
        !(await queue.running)
    }

    func getDownloadQueue() async -> [String: [Download]] {
        await queue.queue
    }

    func pauseDownloads() async {
        await queue.pause()
        NotificationCenter.default.post(name: .downloadsPaused, object: nil)
        // Invalidate cache since paused state may affect display
        await invalidateDownloadedMangaCache()
    }

    func resumeDownloads() async {
        await queue.resume()
        NotificationCenter.default.post(name: .downloadsResumed, object: nil)
        // Invalidate cache since resumed state may affect display
        await invalidateDownloadedMangaCache()
    }

    func cancelDownload(for chapter: ChapterIdentifier) async {
        await queue.cancelDownload(for: chapter)
        // Invalidate cache since cancelled downloads may affect display
        await invalidateDownloadedMangaCache()
    }

    func cancelDownloads(for chapters: [ChapterIdentifier] = []) async {
        if chapters.isEmpty {
            await queue.cancelAll()
        } else {
            await queue.cancelDownloads(for: chapters)
        }
        // Invalidate cache since cancelled downloads may affect display
        await invalidateDownloadedMangaCache()
    }

    func onProgress(for chapter: ChapterIdentifier, block: @Sendable @escaping (Int, Int) -> Void) async {
        await queue.onProgress(for: chapter, block: block)
    }

    func removeProgressBlock(for chapter: ChapterIdentifier) async {
        await queue.removeProgressBlock(for: chapter)
    }
}

// MARK: - Download Manager UI Support
extension DownloadManager {

    /// Get all downloaded manga with metadata from CoreData if available
    func getAllDownloadedManga() async -> [DownloadedMangaInfo] {
        // Return cached result if still valid
        let now = Date()
        if now.timeIntervalSince(lastCacheUpdate) < cacheValidityDuration {
            return downloadedMangaCache
        }

        var downloadedManga: [DownloadedMangaInfo] = []

        // Ensure downloads directory exists
        guard Self.directory.exists else {
            downloadedMangaCache = []
            lastCacheUpdate = now
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
        downloadedMangaCache = downloadedManga
        lastCacheUpdate = now

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
    func saveChapterMetadata(_ chapter: AidokuRunner.Chapter, to directory: URL) {
        let metadata = ChapterMetadata(
            title: chapter.title,
            chapterNumber: chapter.chapterNumber,
            volumeNumber: chapter.volumeNumber
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
    func saveMangaMetadata(_ manga: AidokuRunner.Manga, to directory: URL) async {
        // Get the cover image and convert to base64
        var thumbnailBase64: String?
        if let coverUrl = manga.cover.flatMap({ URL(string: $0) }) {
            do {
                let (data, _) = try await URLSession.shared.data(from: coverUrl)
                thumbnailBase64 = data.base64EncodedString()
            } catch {
                LogManager.logger.error("Failed to download manga cover: \(error)")
            }
        }

        let metadata = MangaMetadata(
            mangaId: manga.key,
            title: manga.title,
            cover: manga.cover,
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
    func deleteChaptersForManga(_ mangaInfo: DownloadedMangaInfo) async {
        await deleteChapters(for: mangaInfo.mangaIdentifier)

        // Invalidate cache
        lastCacheUpdate = .distantPast
    }

    /// Delete a specific chapter (used by download manager UI)
    func deleteChapter(_ chapterInfo: DownloadedChapterInfo, from mangaInfo: DownloadedMangaInfo) async {
        await delete(chapters: [
            .init(
                sourceKey: mangaInfo.sourceId,
                mangaKey: mangaInfo.mangaId,
                chapterKey: chapterInfo.chapterId
            )
        ])

        // Invalidate cache
        lastCacheUpdate = .distantPast
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
    func invalidateDownloadedMangaCache() async {
        lastCacheUpdate = .distantPast
    }
}
