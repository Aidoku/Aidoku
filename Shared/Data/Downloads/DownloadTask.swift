//
//  DownloadTask.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import AidokuRunner
import Foundation
import Nuke
import UniformTypeIdentifiers
import ZIPFoundation

protocol DownloadTaskDelegate: AnyObject, Sendable {
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

    private let cache: DownloadCache
    private var downloads: [Download]
    private weak var delegate: DownloadTaskDelegate?

    private var currentPage: Int = 0
    private var failedPages: Int = 0
    private var pages: [Page] = []

    private(set) var running: Bool = false

    private static let maxConcurrentPageTasks = 5

    init(id: String, cache: DownloadCache, downloads: [Download]) {
        self.id = id
        self.cache = cache
        self.downloads = downloads
    }

    func setDelegate(delegate: DownloadTaskDelegate?) {
        self.delegate = delegate
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
        for (i, download) in downloads.enumerated() where download.status == .queued || download.status == .downloading {
            downloads[i].status = .paused
        }
        Task {
            await delegate?.taskPaused(task: self)
        }
    }

    func cancel(manga: MangaIdentifier? = nil, chapter: ChapterIdentifier? = nil) {
        if let chapter {
            guard let index = downloads.firstIndex(where: { $0.chapterIdentifier == chapter }) else { return }
            // cancel specific chapter download
            let wasRunning = running
            running = false
            downloads[index].status = .cancelled
            if index == 0 {
                pages = []
                currentPage = 0
                failedPages = 0
            }
            // remove chapter tmp download directory
            let download = downloads[index]
            Task {
                cache.tmpDirectory(for: chapter).removeItem()
                await delegate?.downloadCancelled(download: download)
                downloads.removeAll { $0 == download }
                if wasRunning {
                    resume()
                }
            }
        } else if let manga {
            let wasRunning = running
            running = false
            Task {
                var cancelled: IndexSet = []
                for i in downloads.indices where downloads[i].mangaIdentifier == manga {
                    if i == 0 {
                        pages = []
                        currentPage = 0
                        failedPages = 0
                    }
                    downloads[i].status = .cancelled
                    await delegate?.downloadCancelled(download: downloads[i])
                    cancelled.insert(i)
                }
                downloads.remove(atOffsets: cancelled)
                cache.directory(for: manga)
                    .contents
                    .filter { $0.lastPathComponent.hasPrefix(".tmp") }
                    .forEach { $0.removeItem() }
                if wasRunning {
                    resume()
                }
            }
        } else {
            // cancel all downloads in task
            running = false
            var manga: Set<MangaIdentifier> = []
            for i in downloads.indices {
                downloads[i].status = .cancelled
                manga.insert(downloads[i].mangaIdentifier)
            }
            downloads.removeAll()
            // remove cached tmp directories
            Task {
                for manga in manga {
                    cache.directory(for: manga)
                        .contents
                        .filter { $0.lastPathComponent.hasPrefix(".tmp") }
                        .forEach { $0.removeItem() }
                }
                pages = []
                currentPage = 0
                failedPages = 0
                await delegate?.taskCancelled(task: self)
            }
        }
    }

    func add(download: Download) {
        guard !downloads.contains(where: { $0 == download }) else { return }
        downloads.append(download)
    }
}

extension DownloadTask {
    private func next() async {
        guard running else { return }

        // done with all downloads
        if downloads.isEmpty {
            running = false
            await delegate?.taskFinished(task: self)
            return
        }

        // attempt to download first chapter in the queue
        if
            let download = downloads.first,
            let source = SourceManager.shared.source(for: download.chapterIdentifier.sourceKey)
        {
            // if chapter already downloaded, skip
            let directory = cache.directory(for: download.chapterIdentifier)
            guard !directory.exists && !directory.appendingPathExtension("cbz").exists else {
                downloads.removeFirst()
                await delegate?.downloadFinished(download: download)
                return await next()
            }

            // download has been cancelled or failed, skip
            if download.status != .queued && download.status != .downloading && download.status != .paused {
                downloads.removeFirst()
                await delegate?.downloadCancelled(download: download)
                return await next()
            }

            Task {
                await self.download(from: source)
            }
        } else {
            // source not found, skip this download
            downloads.removeFirst()
            await next()
        }
    }

    // perform download
    private func download(from source: AidokuRunner.Source) async {
        guard running && !downloads.isEmpty else { return }

        let download = downloads[0]
        downloads[0].status = .downloading

        let tmpDirectory = cache.tmpDirectory(for: download.chapterIdentifier)
        tmpDirectory.createDirectory()

        if pages.isEmpty {
            pages = ((try? await source.getPageList(
                manga: download.manga,
                chapter: download.chapter
            )) ?? []).map {
                $0.toOld(sourceId: source.key, chapterId: download.chapterIdentifier.chapterKey)
            }
            guard running && downloads.first == download else { return }
            downloads[0].total = pages.count
        }

        struct NetworkPage {
            let url: URL
            let context: PageContext?
            let targetPath: URL
        }

        var networkPages: [NetworkPage] = []

        for (i, page) in pages.enumerated() {
            let pageNumber = String(format: "%03d", i + 1)
            let targetPath = tmpDirectory.appendingPathComponent(pageNumber)

            if let urlString = page.imageURL, let url = URL(string: urlString) {
                // add pages that require network requests to a concurrent queue
                networkPages.append(.init(
                    url: url,
                    context: page.context,
                    targetPath: targetPath
                ))
            } else {
                currentPage += 1
                do {
                    if let base64 = page.base64, let data = Data(base64Encoded: base64) {
                        try data.write(to: targetPath.appendingPathExtension("png"))
                    } else if let text = page.text, let data = text.data(using: .utf8) {
                        try data.write(to: targetPath.appendingPathExtension("txt"))
                    } else if let image = page.image {
                        let data = image.pngData()
                        try data?.write(to: targetPath.appendingPathExtension("png"))
                    }
                } catch {
                    failedPages += 1
                    LogManager.logger.error("Error writing page data: \(error)")
                }
            }

            if page.hasDescription {
                var description = page.description
                if description == nil {
                    description = try? await source.getPageDescription(page: page.toNew())
                }
                if let description {
                    let data = description.data(using: .utf8)
                    try? data?.write(to: targetPath.appendingPathExtension("desc.txt"))
                }
            }
        }

        let pageInterceptor: PageInterceptorProcessor? = if source.features.processesPages {
            PageInterceptorProcessor(source: source)
        } else {
            nil
        }

        // download pages from the network concurrently
        await withTaskGroup(of: (Data?, URL?).self) { taskGroup in
            for pageGroup in networkPages.chunked(into: Self.maxConcurrentPageTasks) {
                for page in pageGroup {
                    taskGroup.addTask {
                        let urlRequest = await source.getModifiedImageRequest(
                            url: page.url,
                            context: page.context
                        )

                        let result = try? await URLSession.shared.data(for: urlRequest)

                        var resultData: Data?
                        var resultPath: URL?

                        if let pageInterceptor {
                            let image = result.flatMap { PlatformImage(data: $0.0) } ?? .mangaPlaceholder
                            do {
                                let container = ImageContainer(image: image)
                                let request = ImageRequest(
                                    urlRequest: urlRequest,
                                    userInfo: [.contextKey: page.context ?? [:]]
                                )
                                let newImage = try pageInterceptor.process(
                                    container,
                                    context: .init(
                                        request: request,
                                        response: .init(
                                            container: container,
                                            request: request,
                                            urlResponse: result?.1 ?? (request.url ?? request.urlRequest?.url).flatMap {
                                                HTTPURLResponse(
                                                    url: $0,
                                                    statusCode: 404,
                                                    httpVersion: nil,
                                                    headerFields: nil
                                                )
                                            }
                                        ),
                                        isCompleted: true
                                    )
                                )
                                let data = newImage.image.pngData()
                                resultData = data
                                resultPath = page.targetPath.appendingPathExtension("png")
                            } catch {
                                LogManager.logger.error("Error processing image: \(error)")
                            }
                        } else if let (data, res) = result {
                            let fileExtention = self.guessFileExtension(response: res, defaultValue: "png")
                            resultData = data
                            resultPath = page.targetPath.appendingPathExtension(fileExtention)
                        } else {
                            LogManager.logger.error("Error downloading image with url \(urlRequest)")
                        }

                        return (resultData, resultPath)
                    }
                }
                for await (data, path) in taskGroup {
                    guard tmpDirectory.exists else {
                        // download was cancelled, stop processing
                        return
                    }
                    if let data, let path {
                        do {
                            try data.write(to: path)
                        } catch {
                            LogManager.logger.error("Error writing downloaded image: \(error)")
                        }
                    }
                    await self.incrementProgress(for: download.chapterIdentifier, failed: data == nil)
                }
            }
        }

        // handle completion of the current download
        if networkPages.isEmpty && currentPage == pages.count {
            await handleChapterDownloadFinish(download: download)
        }
    }

    private func incrementProgress(for id: ChapterIdentifier, failed: Bool = false) async {
        guard let downloadIndex = downloads.firstIndex(where: { $0.chapterIdentifier == id }) else {
            return
        }
        currentPage += 1
        downloads[downloadIndex].progress = currentPage
        let download = downloads[downloadIndex]
        Task {
            await delegate?.downloadProgressChanged(download: download)
        }
        if failed {
            failedPages += 1
        }
        if currentPage == pages.count {
            await handleChapterDownloadFinish(download: download)
        }
    }

    private func handleChapterDownloadFinish(download: Download) async {
        let tmpDirectory = cache.tmpDirectory(for: download.chapterIdentifier)

        if failedPages == pages.count {
            // the entire chapter failed to download, skip adding to cache and cancel
            tmpDirectory.removeItem()
            if let downloadIndex = downloads.firstIndex(where: { $0 == download }) {
                downloads[downloadIndex].status = .cancelled
                downloads.remove(at: downloadIndex)
                await delegate?.downloadCancelled(download: download)
            }
            LogManager.logger.error("Chapter failed to download: \(download.chapter.formattedTitle())")
        } else {
            if failedPages > 0 {
                LogManager.logger.error("Chapter downloaded with \(failedPages) failed pages: \(download.chapter.formattedTitle())")
            }
            do {
                // Save chapter metadata after successful download
                await DownloadManager.shared.saveChapterMetadata(manga: download.manga, chapter: download.chapter, to: tmpDirectory)

                let directory = cache.directory(for: download.chapterIdentifier)

                try FileManager.default.moveItem(at: tmpDirectory, to: directory)

                if UserDefaults.standard.bool(forKey: "Downloads.compress") {
                    try FileManager.default.zipItem(at: directory, to: directory.appendingPathExtension("cbz"), shouldKeepParent: false)
                    directory.removeItem()
                }

                // save manga cover if not already present
                let mangaDirectory = cache.directory(for: download.mangaIdentifier)
                let coverPath = mangaDirectory.appendingPathComponent("cover.png")
                if
                    !coverPath.exists,
                    let coverUrl = download.manga.cover.flatMap({ URL(string: $0) }),
                    let source = SourceManager.shared.source(for: download.chapterIdentifier.sourceKey)
                {
                    let request = await source.getModifiedImageRequest(url: coverUrl, context: nil)
                    let result = try? await URLSession.shared.data(for: request)
                    if let data = result?.0 {
                        try? data.write(to: coverPath)
                    }
                }

                await cache.add(chapter: download.chapterIdentifier)
            } catch {
                LogManager.logger.error("Error moving temporary download directory (\(tmpDirectory)) to final location: \(error)")
            }
            if let downloadIndex = downloads.firstIndex(where: { $0 == download }) {
                downloads[downloadIndex].status = .finished
                downloads.remove(at: downloadIndex)
                await delegate?.downloadFinished(download: download)
            }
        }
        pages = []
        currentPage = 0
        failedPages = 0
        await next()
    }
}

// MARK: Utility
extension DownloadTask {
    private nonisolated func guessFileExtension(response: URLResponse, defaultValue: String) -> String {
        if let suggestedFilename = response.suggestedFilename, !suggestedFilename.isEmpty {
            return URL(string: suggestedFilename)?.pathExtension ?? defaultValue
        }
        guard
            let mimeType = response.mimeType,
            let type = UTType(mimeType: mimeType)
        else {
            return defaultValue
        }
        return type.preferredFilenameExtension ?? defaultValue
    }
}
