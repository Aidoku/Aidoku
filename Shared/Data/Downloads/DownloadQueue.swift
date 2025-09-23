//
//  DownloadQueue.swift
//  Aidoku
//
//  Created by Skitty on 5/13/22.
//

import Foundation

// stores queued and active downloads
// creates a downloadtask for every source
// only one chapter per source is downloaded at a time
actor DownloadQueue {

    private let cache: DownloadCache
    private var onCompletion: (() -> Void)?

    var queue: [String: [Download]] = [:] // all queued downloads stored under source id
    var tasks: [String: DownloadTask] = [:] // tasks for each source
    var progressBlocks: [Chapter: (Int, Int) -> Void] = [:]

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
    func add(chapters: [Chapter], manga: Manga? = nil, autoStart: Bool = true) async -> [Download] {
        var downloads: [Download] = []
        for chapter in chapters {
            if await cache.isChapterDownloaded(sourceId: chapter.sourceId, mangaId: chapter.mangaId, chapterId: chapter.id) {
                continue
            }
            // create tmp directory so we know it's queued
            await cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
                .appendingSafePathComponent(".tmp_\(chapter.id)")
                .createDirectory()
            var download = Download.from(chapter: chapter)
            download.manga = manga
            downloads.append(download)
            if queue[chapter.sourceId] == nil {
                queue[chapter.sourceId] = [download]
            } else {
                queue[chapter.sourceId]?.append(download)
                await tasks[chapter.sourceId]?.add(download: download)
            }
        }
        if autoStart {
            await start()
        }
        saveQueueState()
        return downloads
    }

    func cancelDownload(for chapter: Chapter) async {
        if let task = tasks[chapter.sourceId] {
            await task.cancel(chapter: chapter)
        } else {
            // no longer in queue but the tmp download directory still exists, so we should remove it
            await cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
                .appendingSafePathComponent(".tmp_\(chapter.id)")
                .removeItem()
        }
        saveQueueState()
    }

    func cancelDownloads(for chapters: [Chapter]) async {
        sendCancelNotification = false
        defer { sendCancelNotification = true }
        for chapter in chapters {
            if let task = tasks[chapter.sourceId] {
                await task.cancel(chapter: chapter)
            } else {
                await cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
                    .appendingSafePathComponent(".tmp_\(chapter.id)")
                    .removeItem()
            }
            if let queueItem = queue[chapter.sourceId]?.firstIndex(where: {
                $0.chapterId == chapter.id && $0.mangaId == chapter.mangaId
            }) {
                queue[chapter.sourceId]?.remove(at: queueItem)
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name("downloadsCancelled"), object: chapters)
        saveQueueState()
    }

    func cancelAll() async {
        sendCancelNotification = false
        defer { sendCancelNotification = true }
        for task in tasks {
            await task.value.cancel()
        }
        queue = [:]
        NotificationCenter.default.post(name: NSNotification.Name("downloadsCancelled"), object: nil)
        saveQueueState()
    }

    // register callback for download progress change
    func onProgress(for chapter: Chapter, block: @escaping (Int, Int) -> Void) {
        progressBlocks[chapter] = block
    }

    func removeProgressBlock(for chapter: Chapter) {
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
}

extension DownloadQueue {

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
        NotificationCenter.default.post(name: NSNotification.Name("downloadFinished"), object: download)
    }

    func downloadCancelled(download: Download) async {
        var sourceDownloads = queue[download.sourceId] ?? []
        sourceDownloads.removeAll { $0 == download }
        if sourceDownloads.isEmpty {
            queue.removeValue(forKey: download.sourceId)
        } else {
            queue[download.sourceId] = sourceDownloads
        }
        saveQueueState()
        if let chapter = download.chapter {
            progressBlocks.removeValue(forKey: chapter)
        }
        if sendCancelNotification {
            NotificationCenter.default.post(name: NSNotification.Name("downloadCancelled"), object: download)
        }
    }

    func downloadProgressChanged(download: Download) async {
        if let index = queue[download.sourceId]?.firstIndex(where: { $0 == download }) {
            queue[download.sourceId]?[index] = download
        }
        if let chapter = download.chapter, let block = progressBlocks[chapter] {
            block(download.progress, download.total)
        }
        NotificationCenter.default.post(name: NSNotification.Name("downloadProgressed"), object: download)
    }
}
