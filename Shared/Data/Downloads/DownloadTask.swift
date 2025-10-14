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

        if
            let download = downloads.first,
            let source = SourceManager.shared.source(for: download.sourceId)
        {
            let chapter = Chapter(
                sourceId: download.sourceId,
                id: download.chapterId,
                mangaId: download.mangaId,
                title: nil,
                sourceOrder: -1
            )

            // if directory exists (chapter already downloaded) return
            let directory = await cache.directory(for: chapter)
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
                guard downloads.count >= 1 else { return }
                await self.download(0, from: source, to: directory)
            }
        } else {
            downloads.removeFirst()
            await next()
        }
    }

    // perform download
    func download(_ downloadIndex: Int, from source: AidokuRunner.Source, to directory: URL) async {
        guard !downloads.isEmpty && downloads.count >= downloadIndex else { return }

        let pageInterceptor = PageInterceptorProcessor(source: source)
        let manga = downloads[downloadIndex].toManga()
        let chapter = downloads[downloadIndex].toChapter()
        let tmpDirectory = await cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
            .appendingSafePathComponent(".tmp_\(chapter.id)")
        tmpDirectory.createDirectory()

        downloads[downloadIndex].status = .downloading

        if pages.isEmpty {
            pages = ((try? await source.getPageList(
                manga: manga.toNew(),
                chapter: chapter.toNew()
            )) ?? []).map { $0.toOld(sourceId: source.key, chapterId: chapter.id) }
            downloads[downloadIndex].total = pages.count
        }

        var failedPages = 0

        while !pages.isEmpty && currentPage < pages.count && running {
            downloads[downloadIndex].progress = currentPage + 1
            await delegate?.downloadProgressChanged(download: getDownload(downloadIndex)!)

            let page = pages[currentPage]
            let pageNumber = String(format: "%03d", currentPage + 1) // XXX.png

            currentPage += 1

            if let urlString = page.imageURL, let url = URL(string: urlString) {
                // let source modify image request
                let urlRequest = await source.getModifiedImageRequest(
                    url: url,
                    context: page.context
                )

                let result = try? await URLSession.shared.data(for: urlRequest)

                if source.features.processesPages {
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
                        try data?.write(
                            to: tmpDirectory
                                .appendingPathComponent(pageNumber)
                                .appendingPathExtension("png")
                        )
                        continue
                    } catch {
                        LogManager.logger.error("Error processing image: \(error)")
                    }
                }

                if let (data, res) = result {
                    // See if we can guess the file extension
                    let fileExtention = self.guessFileExtension(response: res, defaultValue: "png")
                    do {
                        try data.write(
                            to: tmpDirectory
                                .appendingPathComponent(pageNumber)
                                .appendingPathExtension(fileExtention)
                        )
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
                        try data.write(to: tmpDirectory.appendingPathComponent(pageNumber).appendingPathExtension("png"))
                    } else if let text = page.text, let data = text.data(using: .utf8) {
                        try data.write(to: tmpDirectory.appendingPathComponent(pageNumber).appendingPathExtension("txt"))
                    } else if let image = page.image {
                        let data = image.pngData()
                        try data?.write(
                            to: tmpDirectory
                                .appendingPathComponent(pageNumber)
                                .appendingPathExtension("png")
                        )
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
                    let path = tmpDirectory.appendingPathComponent(pageNumber).appendingPathExtension("desc.txt")
                    try? data?.write(to: path)
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
                    await DownloadManager.shared.saveChapterMetadata(chapter, to: directory)

                    // Save manga metadata when first chapter for this manga is downloaded
                    let mangaDirectory = await cache.directory(forSourceId: chapter.sourceId, mangaId: chapter.mangaId)
                    let metadataPath = mangaDirectory.appendingPathComponent(".manga_metadata.json")
                    if !metadataPath.exists, let mangaInfo = downloads[downloadIndex].manga {
                        await DownloadManager.shared.saveMangaMetadata(mangaInfo, to: mangaDirectory)
                    }

                    await cache.add(chapter: chapter)
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
