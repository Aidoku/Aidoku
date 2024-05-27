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
//    private let store: DownloadStore // TODO: store downloads so if the app exits we can resume

    private(set) var downloadsPaused = false

    var ignoreConnectionType = false

    init() {
        self.cache = DownloadCache()
        self.queue = DownloadQueue(cache: cache)
        if !Self.directory.exists {
            Self.directory.createDirectory()
        }
    }

    func getDownloadQueue() async -> [String: [Download]] {
        await queue.queue
    }

    func getDownloadedPages(for chapter: Chapter) -> [Page] {
        var pages: [Page] = []
        let pageUrls = cache.directory(for: chapter).contents
        for page in pageUrls {
            if let data = try? Data(contentsOf: page) {
                pages.append(
                    Page(
                        sourceId: chapter.sourceId,
                        chapterId: chapter.id,
                        index: (Int(page.deletingPathExtension().lastPathComponent) ?? 1) - 1,
                        imageURL: nil,
                        base64: page.pathExtension == "txt" ? String(data: data, encoding: .utf8) : data.base64EncodedString(),
                        text: nil
                    )
                )
            }
        }
        return pages.sorted { $0.index < $1.index }
    }

    func getDownloadedPagesWithoutContents(for chapter: Chapter) -> [Page] {
        cache.directory(for: chapter).contents
            .compactMap { url in
                Page(
                    sourceId: chapter.sourceId,
                    chapterId: chapter.id,
                    index: (Int(url.deletingPathExtension().lastPathComponent) ?? 1) - 1,
                    imageURL: url.absoluteString
                )
            }
            .sorted { $0.index < $1.index }
    }

    func isChapterDownloaded(chapter: Chapter) -> Bool {
        cache.isChapterDownloaded(chapter: chapter)
    }

    func getDownloadStatus(for chapter: Chapter) -> DownloadStatus {
        if cache.isChapterDownloaded(chapter: chapter) {
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
}

extension DownloadManager {

    func downloadAll(manga: Manga) async {
        let chapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceId, mangaId: manga.id)
        download(chapters: chapters.reversed(), manga: manga)
    }

    func downloadUnread(manga: Manga) async {
        let readingHistory = await CoreDataManager.shared.getReadingHistory(sourceId: manga.sourceId, mangaId: manga.id)
        let chapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceId, mangaId: manga.id).filter {
            readingHistory[$0.id] == nil || readingHistory[$0.id]?.page != -1
        }
        download(chapters: chapters.reversed(), manga: manga)
    }

    func download(chapters: [Chapter], manga: Manga? = nil) {
        Task {
            let downloads = await queue.add(chapters: chapters, manga: manga, autoStart: true)
            NotificationCenter.default.post(name: NSNotification.Name("downloadsQueued"), object: downloads)
        }
    }

    func delete(chapters: [Chapter]) {
        for chapter in chapters {
            cache.directory(for: chapter).removeItem()
            cache.remove(chapter: chapter)
            NotificationCenter.default.post(name: NSNotification.Name("downloadRemoved"), object: chapter)
        }
    }

    func deleteChapters(for manga: Manga) {
        cache.directory(for: manga).removeItem()
        cache.remove(manga: manga)
        NotificationCenter.default.post(name: NSNotification.Name("downloadsRemoved"), object: manga)
    }

    func pauseDownloads(for chapters: [Chapter] = []) {
        Task {
            await queue.pause()
        }
        downloadsPaused = true
        NotificationCenter.default.post(name: Notification.Name("downloadsPaused"), object: nil)
    }

    func resumeDownloads(for chapters: [Chapter] = []) {
        Task {
            await queue.resume()
        }
        downloadsPaused = false
        NotificationCenter.default.post(name: Notification.Name("downloadsResumed"), object: nil)
    }

    func cancelDownload(for chapter: Chapter) {
        Task {
            await queue.cancelDownload(for: chapter)
        }
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
