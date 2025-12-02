//
//  DownloadManager.swift
//  Aidoku
//
//  Created by Skitty on 5/2/22.
//

import AidokuRunner
import Foundation
import ZIPFoundation

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

    @MainActor
    private let cache: DownloadCache = .init()
    private let queue: DownloadQueue

    // for UI
    private var downloadedMangaCache: [DownloadedMangaInfo] = []
    private var lastCacheUpdate: Date = .distantPast
    private let cacheValidityDuration: TimeInterval = 60 // 1 minute

    init() {
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

    func getDownloadedPages(for chapter: ChapterIdentifier) async -> [AidokuRunner.Page] {
        let directory = cache.directory(for: chapter)

        let archiveURL = directory.appendingPathExtension("cbz")
        if archiveURL.exists {
            return LocalFileManager.shared.readPages(from: archiveURL)
        } else {
            var descriptionFiles: [URL] = []

            var pages = directory.contents
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                .compactMap { url -> AidokuRunner.Page? in
                    guard !url.lastPathComponent.hasPrefix(".") else {
                        return nil
                    }
                    if url.pathExtension == "txt" {
                        // add description file to list
                        if url.lastPathComponent.hasSuffix("desc.txt") {
                            descriptionFiles.append(url)
                            return nil
                        }
                        // otherwise, load file as text
                        let text: String? = try? String(contentsOf: url)
                        guard let text else { return nil }
                        return AidokuRunner.Page(content: .text(text))
                    } else if LocalFileManager.allowedImageExtensions.contains(url.pathExtension) {
                        // load file as image
                        return AidokuRunner.Page(content: .url(url: url, context: nil))
                    } else {
                        return nil
                    }
                }

            // load descriptions from files
            for descriptionFile in descriptionFiles {
                guard
                    let index = descriptionFile
                        .deletingPathExtension()
                        .lastPathComponent
                        .split(separator: ".", maxSplits: 1)
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
    }

    @MainActor
    func isChapterDownloaded(chapter: ChapterIdentifier) -> Bool {
        cache.isChapterDownloaded(identifier: chapter)
    }

    @MainActor
    func hasDownloadedChapter(from identifier: MangaIdentifier) -> Bool {
        cache.hasDownloadedChapter(from: identifier)
    }

    func downloadsCount(for identifier: MangaIdentifier) -> Int {
        cache.directory(for: identifier)
            .contents
            .filter { ($0.isDirectory || $0.pathExtension == "cbz") && !$0.lastPathComponent.hasPrefix(".tmp") }
            .count
    }

    func hasQueuedDownloads() async -> Bool {
        await queue.hasQueuedDownloads()
    }

    nonisolated func getDownloadStatus(for chapter: ChapterIdentifier) -> DownloadStatus {
        let chapterDirectory = cache.directory(for: chapter)
        if chapterDirectory.exists || chapterDirectory.appendingPathExtension("cbz").exists {
            return .finished
        } else {
            if cache.tmpDirectory(for: chapter).exists {
                return .queued
            } else {
                return .none
            }
        }
    }

    nonisolated func getMangaDirectoryUrl(identifier: MangaIdentifier) -> URL? {
        let path = cache.directory(for: identifier).path
        return URL(string: "shareddocuments://\(path)")
    }

    func getCompressedFile(for chapter: ChapterIdentifier) -> URL? {
        let chapterDirectory = cache.directory(for: chapter)
        let chapterFile = chapterDirectory.appendingPathExtension("cbz")
        if chapterFile.exists {
            return chapterFile
        }
        // otherwise we can compress it ourselves
        let tmpFile = FileManager.default.temporaryDirectory?.appendingPathComponent(chapterFile.lastPathComponent)
        guard let tmpFile else { return nil }
        do {
            try FileManager.default.zipItem(at: chapterDirectory, to: tmpFile, shouldKeepParent: false)
            return tmpFile
        } catch {
            return nil
        }
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
        invalidateDownloadedMangaCache()
    }

    /// Remove downloads for specified chapters.
    func delete(chapters: [ChapterIdentifier]) async {
        for chapter in chapters {
            let directory = cache.directory(for: chapter)
            let archiveURL = directory.appendingPathExtension("cbz")
            directory.removeItem()
            archiveURL.removeItem()
            await cache.remove(chapter: chapter)

            // check if all chapters have been removed (then remove manga directory)
            let manga = chapter.mangaIdentifier
            let hasRemainingChapters = cache.directory(for: manga)
                .contents
                .contains {
                    ($0.isDirectory || $0.pathExtension == "cbz") && !$0.lastPathComponent.hasPrefix(".tmp")
                }
            if !hasRemainingChapters {
                await deleteChapters(for: manga)
            }

            NotificationCenter.default.post(name: .downloadRemoved, object: chapter)
        }
        // Invalidate cache for UI
        invalidateDownloadedMangaCache()
    }

    /// Remove all downloads from a manga.
    func deleteChapters(for manga: MangaIdentifier) async {
        await queue.cancelDownloads(for: manga)
        cache.directory(for: manga).removeItem()
        await cache.remove(manga: manga)

        // remove source directory if there are no more manga folders
        let sourceDirectory = cache.directory(sourceKey: manga.sourceKey)
        let hasRemainingManga = !sourceDirectory.contents.isEmpty
        if !hasRemainingManga {
            sourceDirectory.removeItem()
        }

        NotificationCenter.default.post(name: .downloadsRemoved, object: manga)
        // Invalidate cache for UI
        invalidateDownloadedMangaCache()
    }

    /// Remove all downloads.
    func deleteAll() async {
        await cache.removeAll()
    }
}

// MARK: Queue Control

extension DownloadManager {
    func isQueuePaused() async -> Bool {
        !(await queue.isRunning())
    }

    func getDownloadQueue() async -> [String: [Download]] {
        await queue.queue
    }

    func pauseDownloads() async {
        await queue.pause()
        NotificationCenter.default.post(name: .downloadsPaused, object: nil)
        // Invalidate cache since paused state may affect display
        invalidateDownloadedMangaCache()
    }

    func resumeDownloads() async {
        await queue.resume()
        NotificationCenter.default.post(name: .downloadsResumed, object: nil)
        // Invalidate cache since resumed state may affect display
        invalidateDownloadedMangaCache()
    }

    func cancelDownload(for chapter: ChapterIdentifier) async {
        await queue.cancelDownload(for: chapter)
        // Invalidate cache since cancelled downloads may affect display
        invalidateDownloadedMangaCache()
    }

    func cancelDownloads(for chapters: [ChapterIdentifier] = []) async {
        if chapters.isEmpty {
            await queue.cancelAll()
        } else {
            await queue.cancelDownloads(for: chapters)
        }
        // Invalidate cache since cancelled downloads may affect display
        invalidateDownloadedMangaCache()
    }

    func onProgress(for chapter: ChapterIdentifier, block: @Sendable @escaping (Int, Int) -> Void) async {
        await queue.onProgress(for: chapter, block: block)
    }

    func removeProgressBlock(for chapter: ChapterIdentifier) async {
        await queue.removeProgressBlock(for: chapter)
    }
}

// MARK: - Downloads UI Support
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
                    ($0.isDirectory || $0.pathExtension == "cbz") && !$0.lastPathComponent.hasPrefix(".tmp")
                }

                guard !chapterDirectories.isEmpty else { continue }

                let totalSize = await calculateDirectorySize(mangaDirectory)
                let chapterCount = chapterDirectories.count

                // Try to load metadata from the manga directory first
                let firstComicInfo = findComicInfo(in: mangaDirectory)
                let extraData = firstComicInfo?.extraData()

                // Fallback to CoreData only if no stored metadata exists
                let mangaMetadata = if let firstComicInfo {
                    (
                        title: firstComicInfo.series,
                        coverUrl: mangaDirectory.appendingPathComponent("cover.png").absoluteString,
                        isInLibrary: await withCheckedContinuation { continuation in
                            CoreDataManager.shared.container.performBackgroundTask { context in
                                let isInLibrary = CoreDataManager.shared.hasLibraryManga(
                                    sourceId: sourceId,
                                    mangaId: extraData?.mangaKey ?? mangaId,
                                    context: context
                                )
                                continuation.resume(returning: isInLibrary)
                            }
                        },
                        actualMangaId: extraData?.mangaKey ?? mangaId
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
    func getDownloadedChapters(for identifier: MangaIdentifier) async -> [DownloadedChapterInfo] {
        let mangaDirectory = cache.directory(for: identifier)
        guard mangaDirectory.exists else { return [] }

        let chapterDirectories = mangaDirectory.contents.filter {
            ($0.isDirectory || $0.pathExtension == "cbz") && !$0.lastPathComponent.hasPrefix(".tmp")
        }

        var chapters: [DownloadedChapterInfo] = []

        for chapterDirectory in chapterDirectories {
            let chapterId = chapterDirectory.deletingPathExtension().lastPathComponent
            let size = await calculateDirectorySize(chapterDirectory)

            // Get directory creation date as download date
            let attributes = try? FileManager.default.attributesOfItem(atPath: chapterDirectory.path)
            let downloadDate = attributes?[.creationDate] as? Date

            // Try to load metadata from the chapter directory
            let metadata = getComicInfo(in: chapterDirectory)

            let chapterInfo = DownloadedChapterInfo(
                chapterId: chapterId,
                title: metadata?.title,
                chapterNumber: metadata?.number.flatMap { Float($0) },
                volumeNumber: metadata?.volume.flatMap { Float($0) },
                size: size,
                downloadDate: downloadDate,
                chapter: metadata?.toChapter()
            )

            chapters.append(chapterInfo)
        }

        // Sort chapters by ID
        chapters.sort { lhs, rhs in
            // Try to sort numerically if possible, otherwise alphabetically
            if let lhsNum = Double(lhs.chapterId), let rhsNum = Double(rhs.chapterId) {
                return lhsNum < rhsNum
            }
            return lhs.chapterId.localizedStandardCompare(rhs.chapterId) == .orderedAscending
        }

        return chapters
    }

    /// Save chapter metadata to ComicInfo.xml.
    func saveChapterMetadata(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter, to directory: URL) {
        let xml = ComicInfo.load(manga: manga, chapter: chapter).export()
        guard let data = xml.data(using: .utf8) else { return }
        do {
            let metadataURL = directory.appendingPathComponent("ComicInfo.xml")
            try data.write(to: metadataURL)
        } catch {
            LogManager.logger.error("Failed to save chapter metadata: \(error)")
        }
    }

    /// Load chapter metadata from chapter directory.
    private func getComicInfo(in directory: URL) -> ComicInfo? {
        do {
            if directory.pathExtension == "cbz" {
                return ComicInfo.load(from: directory)
            }

            guard directory.isDirectory else { return nil }

            let xmlURL = directory.appendingPathComponent("ComicInfo.xml")
            if xmlURL.exists {
                let data = try Data(contentsOf: xmlURL)
                if
                    let string = String(data: data, encoding: .utf8),
                    let comicInfo = ComicInfo.load(xmlString: string)
                {
                    return comicInfo
                }
            }

            return nil
        } catch {
            LogManager.logger.error("Failed to load chapter metadata: \(error)")
            return nil
        }
    }

    /// Load metadata from manga directory.
    private func findComicInfo(in directory: URL) -> ComicInfo? {
        // check for ComicInfo.xml in any subdirectory
        for subdirectory in directory.contents where subdirectory.isDirectory || subdirectory.pathExtension == "cbz" {
            do {
                if directory.pathExtension == "cbz" {
                    if let comicInfo = ComicInfo.load(from: directory) {
                        return comicInfo
                    }
                } else {
                    let xmlURL = subdirectory.appendingPathComponent("ComicInfo.xml")
                    if xmlURL.exists {
                        let data = try Data(contentsOf: xmlURL)
                        if
                            let string = String(data: data, encoding: .utf8),
                            let comicInfo = ComicInfo.load(xmlString: string)
                        {
                            return comicInfo
                        }
                    }
                }
            } catch {
                LogManager.logger.error("Failed to load manga metadata from ComicInfo.xml: \(error)")
            }
        }

        return nil
    }

    /// Calculate the total size of a directory in bytes.
    private func calculateDirectorySize(_ directory: URL) async -> Int64 {
        guard directory.exists else { return 0 }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var totalSize: Int64 = 0

                if directory.isDirectory {
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
                } else {
                    let resourceValues = try? directory.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if let resourceValues, resourceValues.isRegularFile == true {
                        totalSize = Int64(resourceValues.fileSize ?? 0)
                    }
                }

                continuation.resume(returning: totalSize)
            }
        }
    }

    /// Get formatted total download size string
    func getFormattedTotalDownloadedSize() async -> String {
        let totalSize = if Self.directory.exists {
            await calculateDirectorySize(Self.directory)
        } else {
            Int64(0)
        }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    /// Invalidate the downloaded manga cache (call when downloads are added/removed)
    private func invalidateDownloadedMangaCache() {
        lastCacheUpdate = .distantPast
    }
}

extension DownloadManager {
    /// Check if there is any old metadata files that need migration.
    func checkForOldMetadata() -> Bool {
        for sourceDirectory in Self.directory.contents where sourceDirectory.isDirectory {
            for mangaDirectory in sourceDirectory.contents where mangaDirectory.isDirectory {
                if mangaDirectory.appendingPathComponent(".manga_metadata.json").exists {
                    return true
                }
                for chapterDirectory in mangaDirectory.contents where chapterDirectory.isDirectory {
                    if chapterDirectory.appendingPathComponent(".metadata.json").exists {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Migrate old metadata files to new format.
    func migrateOldMetadata() {
        for sourceDirectory in Self.directory.contents where sourceDirectory.isDirectory {
            for mangaDirectory in sourceDirectory.contents where mangaDirectory.isDirectory {
                let mangaMetadataUrl = mangaDirectory.appendingPathComponent(".manga_metadata.json")
                var seriesTitle: String?
                if mangaMetadataUrl.exists {
                    if
                        let data = try? Data(contentsOf: mangaMetadataUrl),
                        let metadata = try? JSONDecoder().decode(MangaMetadata.self, from: data)
                    {
                        // save series title for chapter ComicInfo
                        seriesTitle = metadata.title
                        // save cover image data as cover.png
                        if
                            let thumbnailBase64 = metadata.thumbnailBase64,
                            let imageData = Data(base64Encoded: thumbnailBase64)
                        {
                            try? imageData.write(to: mangaDirectory.appendingPathComponent("cover.png"))
                        }
                    }
                    mangaMetadataUrl.removeItem()
                }
                for chapterDirectory in mangaDirectory.contents where chapterDirectory.isDirectory {
                    let chapterMetadataUrl = chapterDirectory.appendingPathComponent(".metadata.json")
                    if chapterMetadataUrl.exists {
                        if
                            let data = try? Data(contentsOf: chapterMetadataUrl),
                            let metadata = try? JSONDecoder().decode(ChapterMetadata.self, from: data)
                        {
                            let xml = ComicInfo(
                                title: metadata.title,
                                series: seriesTitle,
                                number: metadata.chapterNumber.flatMap { String($0) },
                                volume: metadata.volumeNumber.flatMap { Int(floor($0)) }
                            ).export()
                            guard let data = xml.data(using: .utf8) else { continue }
                            try? data.write(to: chapterDirectory.appendingPathComponent("ComicInfo.xml"))
                        }
                        chapterMetadataUrl.removeItem()
                    }
                }
            }
        }
        invalidateDownloadedMangaCache()
    }

    private struct ChapterMetadata: Codable {
        let title: String?
        let chapterNumber: Float?
        let volumeNumber: Float?
        var chapter: AidokuRunner.Chapter?
    }

    private struct MangaMetadata: Codable {
        let mangaId: String?
        let title: String?
        let cover: String?
        let thumbnailBase64: String?
        let description: String?
    }
}
