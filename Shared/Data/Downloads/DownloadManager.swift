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
class DownloadManager {

    static let shared = DownloadManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Downloads", isDirectory: true)

    private let cache: DownloadCache
    private let queue: DownloadQueue
//    private let store: DownloadStore // TODO: store downloads so if the app exits we can resume

    init() {
        self.cache = DownloadCache()
        self.queue = DownloadQueue(cache: cache)
        if !Self.directory.exists {
            Self.directory.createDirectory()
        }
    }

    func getDownloadedPages(for chapter: Chapter) -> [Page] {
        var pages: [Page] = []
        let pageUrls = cache.directory(for: chapter).contents
        for page in pageUrls {
            if let data = try? Data(contentsOf: page) {
                pages.append(
                    Page(
                        index: (Int(page.deletingPathExtension().lastPathComponent) ?? 1) - 1,
                        imageURL: nil,
                        base64: page.pathExtension == "txt" ? String(data: data, encoding: .utf8) : data.base64EncodedString(),
                        text: nil
                    )
                )
            }
        }
        return pages.sorted { $0.index < $1.index }
    }

    func isChapterDownloaded(chapter: Chapter) -> Bool {
        cache.isChapterDownloaded(chapter: chapter)
    }

    func hasDownloadedChapter(manga: Manga) -> Bool {
        cache.hasDownloadedChapter(manga: manga)
    }
}

extension DownloadManager {

    func download(chapters: [Chapter]) {
        Task {
            await queue.add(chapters: chapters)
            for chapter in chapters {
                NotificationCenter.default.post(name: NSNotification.Name("downloadQueued"), object: chapter)
            }
        }
    }

    func delete(chapters: [Chapter]) {
        for chapter in chapters {
            cache.directory(for: chapter).removeItem()
            cache.remove(chapter: chapter)
            NotificationCenter.default.post(name: NSNotification.Name("downloadRemoved"), object: chapter)
        }
    }
}
