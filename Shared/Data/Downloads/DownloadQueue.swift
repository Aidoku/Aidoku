//
//  DownloadQueue.swift
//  Aidoku
//
//  Created by Skitty on 5/13/22.
//

import AidokuRunner
@preconcurrency import BackgroundTasks
import Foundation

// stores queued and active downloads
// creates a downloadtask for every source
// only one chapter per source is downloaded at a time
actor DownloadQueue {
    private let cache: DownloadCache
    private var onCompletion: (() -> Void)?

    private(set) var queue: [String: [Download]] = [:] // all queued downloads stored under source id
    private var tasks: [String: DownloadTask] = [:] // tasks for each source
    private var progressBlocks: [ChapterIdentifier: (Int, Int) -> Void] = [:]

    private var paused = false
    private var registeredTask = false
    private var totalDownloads: Int = 0
    private var completedDownloads: Int = 0
    private var bgTask: ProgressReporting?
    private var sendCancelNotification = true

    private static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "") + ".download"

    init(cache: DownloadCache, onCompletion: (() -> Void)? = nil) {
        self.cache = cache
        self.onCompletion = onCompletion
    }

    func setOnCompletion(_ onCompletion: (() -> Void)?) {
        self.onCompletion = onCompletion
    }

    func start() async {
        paused = false

        guard !queue.isEmpty else { return }

#if !os(macOS) && !targetEnvironment(simulator)
        if bgTask == nil, #available(iOS 26.0, *) {
            await register()

            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.taskIdentifier,
                title: NSLocalizedString("DOWNLOADING"),
                subtitle: NSLocalizedString("PROCESSING_QUEUE")
            )
            do {
                try BGTaskScheduler.shared.submit(request)
                return
            } catch {
                LogManager.logger.error("Failed to start background downloading: \(error)")
            }
        }
#endif

        await initAndResumeTasks()
    }

    private func initAndResumeTasks() async {
        for (sourceKey, downloads) in queue {
            if tasks[sourceKey] == nil {
                let task = DownloadTask(id: sourceKey, cache: cache, downloads: downloads)
                await task.setDelegate(delegate: self)
                tasks[sourceKey] = task
            }
            await tasks[sourceKey]?.resume()
        }
    }

    func resume() async {
        paused = false

        if #available(iOS 26.0, *) {
            if bgTask == nil {
                await start()
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for task in tasks.values {
                group.addTask { await task.resume() }
            }
        }
    }

    func pause() async {
        paused = true

#if !os(macOS)
        if #available(iOS 26.0, *) {
            if let task = bgTask as? BGContinuedProcessingTask {
                task.updateTitle(
                    NSLocalizedString("DOWNLOADING"),
                    subtitle: NSLocalizedString("PAUSED")
                )
            }
        }
#endif

        await withTaskGroup(of: Void.self) { group in
            for task in tasks.values {
                group.addTask { await task.pause() }
            }
        }
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
            guard !(await cache.isChapterDownloaded(identifier: identifier)) else {
                continue
            }
            // create tmp directory so we know it's queued
            await cache.directory(for: manga.identifier)
                .appendingSafePathComponent(".tmp_\(chapter.key)")
                .createDirectory()
            let download = Download.from(manga: manga, chapter: chapter)
            downloads.append(download)
            if queue[manga.sourceKey] == nil {
                queue[manga.sourceKey] = [download]
            } else {
                queue[manga.sourceKey]?.append(download)
                await tasks[manga.sourceKey]?.add(download: download)
            }
        }
        totalDownloads += downloads.count
        bgTask?.progress.totalUnitCount = Int64(totalDownloads)
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
        // disable individual download cancelled notifications
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

    func cancelDownloads(for manga: MangaIdentifier) async {
        if let task = tasks[manga.sourceKey] {
            await task.cancel(manga: manga)
        } else {
            await cache.directory(for: manga)
                .contents
                .filter { $0.lastPathComponent.hasPrefix(".tmp") }
                .forEach { $0.removeItem() }
        }
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

    func isRunning() async -> Bool {
        for task in tasks where await task.value.running {
            return true
        }
        return false
    }
}

extension DownloadQueue {
    private func setBackgroundTask(_ task: ProgressReporting?) {
        bgTask = task
        totalDownloads = queue.values.reduce(0) { $0 + $1.count }
        completedDownloads = 0
        bgTask?.progress.totalUnitCount = Int64(totalDownloads)
    }

#if !os(macOS) && !targetEnvironment(simulator)
    @available(iOS 26.0, *)
    private func register() async {
        guard !registeredTask else { return }
        registeredTask = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { @Sendable [weak self] task in
            guard let self, let task = task as? BGContinuedProcessingTask else { return }

            task.expirationHandler = {
                Task {
                    await DownloadManager.shared.pauseDownloads()
                    await self.setBackgroundTask(nil)
                }
            }

            Task { @Sendable in
                await self.setBackgroundTask(task)
                await self.initAndResumeTasks()

                // wait until downloads complete
                while true {
                    if await self.queue.isEmpty {
                        break
                    }
                }

                await self.setBackgroundTask(nil)

                task.setTaskCompleted(success: true)
            }
        }
    }
#endif
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
        saveQueueState()
    }

    func downloadFinished(download: Download) async {
        await downloadCancelled(download: download)
        progressBlocks.removeValue(forKey: download.chapterIdentifier)
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

        completedDownloads += 1
        bgTask?.progress.completedUnitCount = Int64(completedDownloads)

#if !os(macOS)
        if #available(iOS 26.0, *) {
            if !paused, let task = bgTask as? BGContinuedProcessingTask {
                task.updateTitle(
                    NSLocalizedString("DOWNLOADING"),
                    subtitle: String(format: NSLocalizedString("%i_OF_%i"), completedDownloads, totalDownloads)
                )
            }
        }
#endif
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
