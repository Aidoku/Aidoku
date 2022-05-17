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

    var queue: [String: [Download]] = [:] // all queued downloads stored under source id
    var tasks: [String: DownloadTask] = [:] // tasks for each source

    var running: Bool = false

    init(cache: DownloadCache) {
        self.cache = cache
    }

    func start() async {
        guard !running else { return }
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

    func pause() async {
        guard running else { return }
        for task in tasks {
            await task.value.pause()
        }
        running = false
    }

    func refreshQueue() {
        guard running else { return }
    }

    func add(chapters: [Chapter], autoStart: Bool = true) async {
        for chapter in chapters {
            let download = Download.from(chapter: chapter)
            if queue[chapter.sourceId] == nil {
                queue[chapter.sourceId] = [download]
            } else {
                queue[chapter.sourceId]?.append(download)
                await tasks[chapter.sourceId]?.add(download: download)
            }
        }
        if autoStart && !running {
            await start()
        }
    }
}

// MARK: - Task Delegate
extension DownloadQueue: DownloadTaskDelegate {

    func taskCancelled(task: DownloadTask) async {
        tasks.removeValue(forKey: task.id)
    }

    func taskPaused(task: DownloadTask) async {
    }

    func taskFinished(task: DownloadTask) async {
        tasks.removeValue(forKey: task.id)
        self.running = !tasks.isEmpty
        if !running {
            // all downloads finished
        }
    }

    func downloadFinished(download: Download) async {
        NotificationCenter.default.post(name: NSNotification.Name("downloadFinished"), object: download)
    }

    func downloadProgressChanged(download: Download, progress: Int, total: Int) async {
        NotificationCenter.default.post(name: NSNotification.Name("downloadProgressed"), object: download)
    }
}
