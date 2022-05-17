//
//  DownloadTask.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import Foundation

protocol DownloadTaskDelegate: AnyObject {
    func taskCancelled(task: DownloadTask) async
    func taskPaused(task: DownloadTask) async
    func taskFinished(task: DownloadTask) async
    func downloadProgressChanged(download: Download, progress: Int, total: Int) async
    func downloadFinished(download: Download) async
}

// performs the actual download operations
actor DownloadTask: Identifiable {

    let id: String
    let cache: DownloadCache
    var downloads: [Download]
    weak var delegate: DownloadTaskDelegate?

    var running: Bool = false

    var currentPage: Int = 0
    var pages: [Page] = []

    init(id: String, cache: DownloadCache, downloads: [Download]) {
        self.id = id
        self.cache = cache
        self.downloads = downloads
    }

    func setDelegate(delegate: DownloadTaskDelegate?) {
        self.delegate = delegate
    }

    func getCurrentDownload() -> Download? {
        downloads.first
    }

    func next() async {
        guard running else { return }

        // done with all downloads
        if downloads.isEmpty {
            running = false
            await delegate?.taskFinished(task: self)
            return
        }

        if let download = downloads.first,
           let source = SourceManager.shared.source(for: download.sourceId) {

            let chapter = Chapter(sourceId: download.sourceId, id: download.chapterId, mangaId: download.mangaId, title: nil, sourceOrder: -1)

            // if directory exists (chapter already downloaded) return
            let directory = cache.directory(for: chapter)
            guard !directory.exists else {
                downloads.removeFirst()
                return await next()
            }

            // download has been cancelled or failed, move to next
            if download.status != .queued && download.status != .paused {
                downloads.removeFirst()
                return await next()
            }

            Task {
                await self.download(download, from: source, to: directory)
            }
        } else {
            downloads.removeFirst()
            await next()
        }
    }

    // perform download
    func download(_ download: Download, from source: Source, to directory: URL) async {
        let chapter = download.toChapter()
        let tmpDirectory = cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
            .appendingSafePathComponent(".tmp_\(chapter.id)")
        tmpDirectory.createDirectory()

        downloads[0].status = .downloading

        if pages.isEmpty {
            pages = (try? await source.getPageList(
                chapter: chapter,
                skipDownloadedCheck: true
            )) ?? []
        }
        while currentPage < pages.count && running {
            downloads[0].progress = Float(currentPage + 1) / Float(pages.count)
            await delegate?.downloadProgressChanged(download: getCurrentDownload()!, progress: currentPage + 1, total: pages.count)
            let page = pages[currentPage]
            let pageNumber = String(format: "%03d", page.index + 1) // XXX.png
            if let urlString = page.imageURL, let url = URL(string: urlString) {
                var urlRequest = URLRequest(url: url)
                // let source modify image request
                if let request = try? await source.getImageRequest(url: urlString) {
                    for (key, value) in request.headers {
                        urlRequest.setValue(value, forHTTPHeaderField: key)
                    }
                    if let body = request.body { urlRequest.httpBody = body }
                }
                if let data = try? await URLSession.shared.data(for: urlRequest) {
                    try? data.write(to: tmpDirectory.appendingPathComponent(pageNumber).appendingPathExtension("png"))
                }
            } else if let base64 = page.base64, let data = Data(base64Encoded: base64) {
                try? data.write(to: tmpDirectory.appendingPathComponent(pageNumber).appendingPathExtension("png"))
            } else if let text = page.text, let data = text.data(using: .utf8) {
                try? data.write(to: tmpDirectory.appendingPathComponent(pageNumber).appendingPathExtension("txt"))
            }
            currentPage += 1
        }

        if currentPage == pages.count {
            if (try? FileManager.default.moveItem(at: tmpDirectory, to: directory)) != nil {
                cache.add(chapter: chapter)
            }
            downloads[0].status = .finished
            await delegate?.downloadFinished(download: getCurrentDownload()!)
            downloads.removeFirst()
            pages = []
            currentPage = 0
            await next()
        }
    }

    func resume() {
        guard !running else { return }
        running = true
        Task {
            await next()
        }
    }

    func pause() async {
        running = false
        downloads[0].status = .paused
        Task {
            await delegate?.taskPaused(task: self)
        }
    }

    func cancel() {
        running = false
        downloads[0].status = .cancelled
        pages = []
        currentPage = 0
        Task {
            await delegate?.taskCancelled(task: self)
        }
    }

    func add(download: Download, autostart: Bool = false) {
        guard !downloads.contains(where: { $0 == download }) else { return }
        downloads.append(download)
        if !running && autostart {
            resume()
        }
    }
}
