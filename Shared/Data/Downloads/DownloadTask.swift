//
//  DownloadTask.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import Foundation
import AidokuRunner
import UniformTypeIdentifiers
import Nuke

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
    private var pages: [Page] = []

    private(set) var running: Bool = false

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
        for (i, download) in downloads.enumerated() where download.status == .downloading {
            downloads[i].status = .paused
        }
        Task {
            await delegate?.taskPaused(task: self)
        }
    }

    func cancel(chapter: ChapterIdentifier? = nil) {
        if
            let chapter = chapter,
            let index = downloads.firstIndex(where: { $0.chapterIdentifier == chapter })
        {
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
                await cache.directory(for: chapter.mangaIdentifier)
                    .appendingSafePathComponent(".tmp_\(chapter.chapterKey)")
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
            var manga: Set<MangaIdentifier> = []
            for i in downloads.indices {
                downloads[i].status = .cancelled
                manga.insert(downloads[i].mangaIdentifier)
            }
            downloads.removeAll()
            // remove cached tmp directories
            Task {
                for manga in manga {
                    await cache.directory(for: manga)
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
            // if directory exists (chapter already downloaded) return
            let directory = await cache.directory(for: download.chapterIdentifier)
            guard !directory.exists else {
                downloads.removeFirst()
                await delegate?.downloadFinished(download: download)
                return await next()
            }

            // download has been cancelled or failed, move to next
            if download.status != .queued && download.status != .downloading && download.status != .paused {
                downloads.removeFirst()
                await delegate?.downloadCancelled(download: download)
                return await next()
            }

            Task {
                guard !downloads.isEmpty else { return }
                await self.download(0, from: source, to: directory)
            }
        } else {
            // source not found, skip this download
            downloads.removeFirst()
            await next()
        }
    }

    // perform download
    private func download(_ downloadIndex: Int, from source: AidokuRunner.Source, to directory: URL) async {
        guard !downloads.isEmpty && downloads.count >= downloadIndex else { return }

        let download = downloads[downloadIndex]
        let pageInterceptor: PageInterceptorProcessor? = if source.features.processesPages {
            PageInterceptorProcessor(source: source)
        } else {
            nil
        }

        let tmpDirectory = await cache.directory(for: download.mangaIdentifier)
            .appendingSafePathComponent(".tmp_\(download.chapterIdentifier.chapterKey)")
        tmpDirectory.createDirectory()

        downloads[downloadIndex].status = .downloading

        if pages.isEmpty {
            pages = ((try? await source.getPageList(
                manga: download.manga,
                chapter: download.chapter
            )) ?? []).map {
                $0.toOld(sourceId: source.key, chapterId: download.chapterIdentifier.chapterKey)
            }
            downloads[downloadIndex].total = pages.count
        }

        var failedPages = 0

        while !pages.isEmpty && currentPage < pages.count && running {
            let page = pages[currentPage]
            let pageNumber = String(format: "%03d", currentPage + 1) // XXX.png
            let targetPath = tmpDirectory.appendingPathComponent(pageNumber)

            currentPage += 1

            downloads[downloadIndex].progress = currentPage
            await delegate?.downloadProgressChanged(download: downloads[downloadIndex])

            if let urlString = page.imageURL, let url = URL(string: urlString) {
                // let source modify image request
                let urlRequest = await source.getModifiedImageRequest(
                    url: url,
                    context: page.context
                )

                let result = try? await URLSession.shared.data(for: urlRequest)

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
                        if let data {
                            try data.write(to: targetPath.appendingPathExtension("png"))
                        } else {
                            failedPages += 1
                            LogManager.logger.error("Error processing image: missing result")
                        }
                    } catch {
                        failedPages += 1
                        LogManager.logger.error("Error processing image: \(error)")
                    }
                } else if let (data, res) = result {
                    let fileExtention = guessFileExtension(response: res, defaultValue: "png")
                    do {
                        try data.write(to: targetPath.appendingPathExtension(fileExtention))
                    } catch {
                        failedPages += 1
                        LogManager.logger.error("Error writing downloaded image: \(error)")
                    }
                } else {
                    failedPages += 1
                    LogManager.logger.error("Error downloading image with url \(urlRequest)")
                }
            } else {
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

        // handle completion of the current download
        if currentPage == pages.count {
            if failedPages == pages.count {
                // the entire chapter failed to download, skip adding to cache and cancel
                tmpDirectory.removeItem()
                if let download = downloads[safe: downloadIndex] {
                    downloads[downloadIndex].status = .cancelled
                    downloads.remove(at: downloadIndex)
                    await delegate?.downloadCancelled(download: download)
                }
            } else {
                if (try? FileManager.default.moveItem(at: tmpDirectory, to: directory)) != nil {
                    // Save chapter metadata after successful download
                    await DownloadManager.shared.saveChapterMetadata(download.chapter, to: directory)

                    // Save manga metadata when first chapter for this manga is downloaded
                    let mangaDirectory = await cache.directory(for: download.mangaIdentifier)
                    let metadataPath = mangaDirectory.appendingPathComponent(".manga_metadata.json")
                    if !metadataPath.exists {
                        let mangaInfo = downloads[downloadIndex].manga
                        await DownloadManager.shared.saveMangaMetadata(mangaInfo, to: mangaDirectory)
                    }

                    await cache.add(chapter: download.chapterIdentifier)
                } else {
                    LogManager.logger.error("Error moving temporary download directory to final location")
                }
                if let download = downloads[safe: downloadIndex] {
                    downloads[downloadIndex].status = .finished
                    downloads.remove(at: downloadIndex)
                    await delegate?.downloadFinished(download: download)
                }
            }
            pages = []
            currentPage = 0
            await next()
        }
    }
}

// MARK: Utility
extension DownloadTask {
    private func guessFileExtension(response: URLResponse, defaultValue: String) -> String {
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
