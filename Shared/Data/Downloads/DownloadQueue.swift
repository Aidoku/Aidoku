//
//  DownloadQueue.swift
//  Aidoku
//
//  Created by Skitty on 5/13/22.
//

import AidokuRunner
import Foundation

// stores queued and active downloads
// creates a downloadtask for every source
// only one chapter per source is downloaded at a time
actor DownloadQueue {
    private let cache: DownloadCache
    private var onCompletion: (() -> Void)?

    var queue: [String: [Download]] = [:] // all queued downloads stored under source id
    var tasks: [String: DownloadTask] = [:] // tasks for each source
    var progressBlocks: [ChapterIdentifier: (Int, Int) -> Void] = [:]

    var running: Bool = false

    private var sendCancelNotification = true

    init(cache: DownloadCache, onCompletion: (() -> Void)? = nil) {
        self.cache = cache
        self.onCompletion = onCompletion
    }

    func setOnCompletion(_ onCompletion: (() -> Void)?) {
        self.onCompletion = onCompletion
    }

    func start() async {
//        guard !running else { return }
        running = true

        for source in queue {
            if tasks[source.key] == nil {
                let task = DownloadTask(id: source.key, cache: cache, downloads: source.value)
                await task.setDelegate(delegate: self)
                tasks[source.key] = task
            }
            await tasks[source.key]?.resume()
        }
    }

    func resume() async {
        for task in tasks {
            await task.value.resume()
        }
        running = true
    }

    func pause() async {
        guard running else { return }
        for task in tasks {
            await task.value.pause()
        }
        running = false
    }

    @discardableResult
    func add(chapters: [AidokuRunner.Chapter], manga: AidokuRunner.Manga, autoStart: Bool = true) async -> [Download] {
        var downloads: [Download] = []
        for chapter in chapters {
            let identifier = ChapterIdentifier(
                sourceKey: manga.sourceKey,
                mangaKey: manga.key,
                chapterKey: chapter.key
            )
            if await cache.isChapterDownloaded(identifier: identifier) {
                continue
            }
            // create tmp directory so we know it's queued
            await cache.directory(for: manga.identifier)
                .appendingSafePathComponent(".tmp_\(chapter.id)")
                .createDirectory()
            let download = Download.from(
                manga: manga,
                chapter: chapter
            )
            downloads.append(download)
            if queue[manga.sourceKey] == nil {
                queue[manga.sourceKey] = [download]
            } else {
                queue[manga.sourceKey]?.append(download)
                await tasks[manga.sourceKey]?.add(download: download)
            }
        }
        if autoStart {
            await start()
        }
        saveQueueState()
        return downloads
    }

    func cancelDownload(for chapter: ChapterIdentifier) async {
        if let task = tasks[chapter.sourceKey] {
            await task.cancel(chapter: chapter)
        } else {
            // no longer in queue but the tmp download directory still exists, so we should remove it
            await cache.directory(for: chapter.mangaIdentifier)
                .appendingSafePathComponent(".tmp_\(chapter.chapterKey)")
                .removeItem()
        }
        saveQueueState()
    }

    func cancelDownloads(for chapters: [ChapterIdentifier]) async {
        sendCancelNotification = false
        defer { sendCancelNotification = true }
        for chapter in chapters {
            if let task = tasks[chapter.sourceKey] {
                await task.cancel(chapter: chapter)
            } else {
                await cache.directory(for: chapter.mangaIdentifier)
                    .appendingSafePathComponent(".tmp_\(chapter.chapterKey)")
                    .removeItem()
            }
            if let queueItem = queue[chapter.sourceKey]?.firstIndex(where: {
                $0.chapterIdentifier == chapter
            }) {
                queue[chapter.sourceKey]?.remove(at: queueItem)
            }
        }
        NotificationCenter.default.post(name: .downloadsCancelled, object: chapters)
        saveQueueState()
    }

    func cancelAll() async {
        sendCancelNotification = false
        defer { sendCancelNotification = true }
        for task in tasks {
            await task.value.cancel()
        }
        queue = [:]
        NotificationCenter.default.post(name: .downloadsCancelled, object: nil)
        saveQueueState()
    }

    // register callback for download progress change
    func onProgress(for chapter: ChapterIdentifier, block: @escaping (Int, Int) -> Void) {
        progressBlocks[chapter] = block
    }

    func removeProgressBlock(for chapter: ChapterIdentifier) {
        progressBlocks.removeValue(forKey: chapter)
    }

    func saveQueueState() {
        let queueData = try? JSONEncoder().encode(queue)
        UserDefaults.standard.set(queueData, forKey: "downloadQueueState")
    }

    func loadQueueState() async {
        guard
            let queueData = UserDefaults.standard.data(forKey: "downloadQueueState"),
            let queueState = try? JSONDecoder().decode([String: [Download]].self, from: queueData)
        else {
            return
        }
        queue = queueState
        if !queue.isEmpty {
            await start()
        }
    }

    func hasQueuedDownloads() -> Bool {
        !queue.isEmpty
    }
}

// MARK: - Task Delegate
extension DownloadQueue: DownloadTaskDelegate {

    func taskCancelled(task: DownloadTask) async {
        await taskFinished(task: task)
    }

    func taskPaused(task _: DownloadTask) async {}

    func taskFinished(task: DownloadTask) async {
        tasks.removeValue(forKey: task.id)
        queue.removeValue(forKey: task.id)
        running = !tasks.isEmpty
        saveQueueState()
    }

    func downloadFinished(download: Download) async {
        await downloadCancelled(download: download)
        onCompletion?()
        NotificationCenter.default.post(name: .downloadFinished, object: download)
    }

    func downloadCancelled(download: Download) async {
        var sourceDownloads = queue[download.chapterIdentifier.sourceKey] ?? []
        sourceDownloads.removeAll { $0 == download }
        if sourceDownloads.isEmpty {
            queue.removeValue(forKey: download.chapterIdentifier.sourceKey)
        } else {
            queue[download.chapterIdentifier.sourceKey] = sourceDownloads
        }
        saveQueueState()
        progressBlocks.removeValue(forKey: download.chapterIdentifier)
        if sendCancelNotification {
            NotificationCenter.default.post(name: .downloadCancelled, object: download)
        }
    }

    func downloadProgressChanged(download: Download) async {
        if let index = queue[download.chapterIdentifier.sourceKey]?.firstIndex(where: { $0 == download }) {
            queue[download.chapterIdentifier.sourceKey]?[index] = download
        }
        if let block = progressBlocks[download.chapterIdentifier] {
            block(download.progress, download.total)
        }
        NotificationCenter.default.post(name: .downloadProgressed, object: download)
    }
}
