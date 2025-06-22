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

//    func getDownloadedPages(for chapter: Chapter) -> [Page] {
//        var pages: [Page] = []
//        let pageUrls = cache.directory(for: chapter).contents
//        for page in pageUrls {
//            if let data = try? Data(contentsOf: page) {
//                pages.append(
//                    Page(
//                        sourceId: chapter.sourceId,
//                        chapterId: chapter.id,
//                        index: (Int(page.deletingPathExtension().lastPathComponent) ?? 1) - 1,
//                        imageURL: nil,
//                        base64: page.pathExtension == "txt" ? String(data: data, encoding: .utf8) : data.base64EncodedString(),
//                        text: nil
//                    )
//                )
//            }
//        }
//        return pages.sorted { $0.index < $1.index }
//    }

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
                } else {
                    // load file as image
                    imageURL = url.absoluteString
                    text = nil
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

    func pauseDownloads() {
        Task {
            await queue.pause()
        }
        downloadsPaused = true
        NotificationCenter.default.post(name: Notification.Name("downloadsPaused"), object: nil)
    }

    func resumeDownloads() {
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
