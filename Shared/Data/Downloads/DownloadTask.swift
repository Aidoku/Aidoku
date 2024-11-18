//
//  DownloadTask.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import Foundation
import UniformTypeIdentifiers

protocol DownloadTaskDelegate: AnyObject {
    func taskCancelled(task: DownloadTask) async
    func taskPaused(task: DownloadTask) async
    func taskFinished(task: DownloadTask) async
    func downloadProgressChanged(download: Download) async
    func downloadFinished(download: Download) async
    func downloadCancelled(download: Download) async
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

    func getDownload(_ index: Int = 0) -> Download? {
        downloads.count >= index ? downloads[index] : nil
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
            let directory = await cache.directory(for: chapter)
            guard !directory.exists else {
                downloads.removeFirst()
                return await next()
            }

            // download has been cancelled or failed, move to next
            if download.status != .queued && download.status != .downloading && download.status != .paused {
                downloads.removeFirst()
                return await next()
            }

            Task {
                guard downloads.count >= 1 else { return }
                await self.download(0, from: source, to: directory)
            }
        } else {
            downloads.removeFirst()
            await next()
        }
    }

    // perform download
    func download(_ downloadIndex: Int, from source: Source, to directory: URL) async {
        guard !downloads.isEmpty && downloads.count >= downloadIndex else { return }

        let chapter = downloads[downloadIndex].toChapter()
        let tmpDirectory = await cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
            .appendingSafePathComponent(".tmp_\(chapter.id)")
        tmpDirectory.createDirectory()

        downloads[downloadIndex].status = .downloading

        if pages.isEmpty {
            pages = (try? await source.getPageList(
                chapter: chapter,
                skipDownloadedCheck: true
            )) ?? []
            downloads[downloadIndex].total = pages.count
        }
        while !pages.isEmpty && currentPage < pages.count && running {
            downloads[downloadIndex].progress = currentPage + 1
            let page = pages[currentPage]
            await delegate?.downloadProgressChanged(download: getDownload(downloadIndex)!)
            let pageNumber = String(format: "%03d", currentPage + 1) // XXX.png
            if let urlString = page.imageURL, let url = URL(string: urlString) {
                var urlRequest = URLRequest(url: url)
                // let source modify image request
                if let request = try? await source.getImageRequest(url: urlString) {
                    for (key, value) in request.headers {
                        urlRequest.setValue(value, forHTTPHeaderField: key)
                    }
                    if let body = request.body { urlRequest.httpBody = body }
                }
                if let (data, res) = try? await URLSession.shared.data(for: urlRequest) {
                    // See if we can guess the file extension
                    let fileExtention = self.guessFileExtension(response: res, defaultValue: "png")
                    try? data.write(to: tmpDirectory.appendingPathComponent(pageNumber).appendingPathExtension(fileExtention))
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
                await cache.add(chapter: chapter)
            }
            downloads[downloadIndex].status = .finished
            await delegate?.downloadFinished(download: getDownload(downloadIndex)!)
            downloads.remove(at: downloadIndex)
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
        for (i, download) in downloads.enumerated() where download.status == .downloading {
            downloads[i].status = .paused
        }
        Task {
            await delegate?.taskPaused(task: self)
        }
    }

    func cancel(chapter: Chapter? = nil) {
        if let chapter = chapter,
           let index = downloads.firstIndex(where: { $0.chapterId == chapter.id }) {
            // cancel specific chapter download
            let wasRunning = running
            running = false
            downloads[index].status = .cancelled
            if index == 0 {
                pages = []
                currentPage = 0
            }
            // remove chapter tmp download directory
            let download = downloads[index]
            Task {
                await cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
                    .appendingSafePathComponent(".tmp_\(chapter.id)")
                    .removeItem()
                await delegate?.downloadCancelled(download: download)
                downloads.removeAll { $0 == download }
                if wasRunning {
                    resume()
                }
            }
        } else {
            // cancel all downloads in task
            running = false
            var manga: [Manga] = []
            for i in downloads.indices {
                guard i < downloads.count else { continue }
                downloads[i].status = .cancelled
                if !manga.contains(where: { $0.id == downloads[i].mangaId }) {
                    manga.append(Manga(sourceId: downloads[i].sourceId, id: downloads[i].mangaId))
                }
                downloads.remove(at: i)
            }
            // remove cached tmp directories
            Task {
                for manga in manga {
                    await cache.directory(forSourceId: manga.sourceId, mangaId: manga.id)
                        .contents
                        .filter { $0.lastPathComponent.hasPrefix(".tmp") }
                        .forEach { $0.removeItem() }
                }
                pages = []
                currentPage = 0
                await delegate?.taskCancelled(task: self)
            }
        }
    }

    func add(download: Download, autostart: Bool = false) {
        guard !downloads.contains(where: { $0 == download }) else { return }
        downloads.append(download)
        if !running && autostart {
            resume()
        }
    }

    // MARK: Utility
    private func guessFileExtension(response: URLResponse, defaultValue: String) -> String {
        if let suggestedFilename = response.suggestedFilename, !suggestedFilename.isEmpty {
            return URL(string: suggestedFilename)?.pathExtension ?? defaultValue
        }

        guard let mimeType = response.mimeType,
              let type = UTType(mimeType: mimeType) else {
            return defaultValue
        }

        return type.preferredFilenameExtension ?? defaultValue
    }
}
