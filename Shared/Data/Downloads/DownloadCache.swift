//
//  DownloadCache.swift
//  Aidoku
//
//  Created by Skitty on 5/13/22.
//

import Foundation

// cache of downloads directory contents on the filesystem
// TODO: should probably be reloaded every once in a while so we can recheck filesystem for user modifications
@MainActor
class DownloadCache {

    struct Directory {
        var url: URL
        var subdirectories: [String: Directory] = [:]
    }

    var rootDirectory = Directory(url: DownloadManager.directory)

    var loaded = false

    // create cache from filesystem
    func load() {
        for sourceDirectory in DownloadManager.directory.contents where sourceDirectory.isDirectory {
            rootDirectory.subdirectories[sourceDirectory.lastPathComponent] = Directory(url: sourceDirectory)
            for mangaDirectory in sourceDirectory.contents where mangaDirectory.isDirectory {
                var chapterDirectories: [String: Directory] = [:]
                for chapterDirectory in mangaDirectory.contents where chapterDirectory.isDirectory {
                    chapterDirectories[chapterDirectory.lastPathComponent] = Directory(url: chapterDirectory)
                }
                rootDirectory
                    .subdirectories[sourceDirectory.lastPathComponent]?
                    .subdirectories[mangaDirectory.lastPathComponent] = Directory(
                        url: mangaDirectory,
                        subdirectories: chapterDirectories
                    )
            }
        }

        loaded = true
    }

    // add chapter to directory cache
    func add(chapter: Chapter) {
        let sourceDirectory = rootDirectory.subdirectories[chapter.sourceId.directoryName]
        let sourceDirectoryURL = DownloadManager.directory.appendingSafePathComponent(chapter.sourceId)
        if sourceDirectory == nil {
            rootDirectory.subdirectories[chapter.sourceId.directoryName] = Directory(
                url: sourceDirectoryURL
            )
        }
        if sourceDirectory?.subdirectories[chapter.mangaId.directoryName] == nil {
            rootDirectory
                .subdirectories[chapter.sourceId.directoryName]?
                .subdirectories[chapter.mangaId.directoryName] = Directory(
                    url: sourceDirectoryURL.appendingSafePathComponent(chapter.mangaId)
                )
        }
        if sourceDirectory?.subdirectories[chapter.mangaId.directoryName]?.subdirectories[chapter.id.directoryName] == nil {
            rootDirectory
                .subdirectories[chapter.sourceId.directoryName]?
                .subdirectories[chapter.mangaId.directoryName]?
                .subdirectories[chapter.id.directoryName] = Directory(
                    url: directory(for: chapter)
                )
        }
    }

    func remove(manga: Manga) {
        rootDirectory.subdirectories[manga.sourceId.directoryName]?
            .subdirectories[manga.id.directoryName] = nil
    }

    func remove(chapter: Chapter) {
        rootDirectory.subdirectories[chapter.sourceId.directoryName]?
            .subdirectories[chapter.mangaId.directoryName]?
            .subdirectories[chapter.id.directoryName] = nil
    }
}

extension DownloadCache {
    // check if a chapter has a download directory
    func isChapterDownloaded(chapter: Chapter) -> Bool {
        if !loaded { load() }
        if let sourceDirectory = rootDirectory.subdirectories[chapter.sourceId.directoryName],
           let mangaDirectory = sourceDirectory.subdirectories[chapter.mangaId.directoryName] {
            return mangaDirectory.subdirectories[chapter.id.directoryName] != nil
        }
        return false
    }

    func hasDownloadedChapter(sourceId: String, mangaId: String) -> Bool {
        if !loaded { load() }
        if let sourceDirectory = rootDirectory.subdirectories[sourceId.directoryName],
           let mangaDirectory = sourceDirectory.subdirectories[mangaId.directoryName] {
            return !mangaDirectory.subdirectories.isEmpty
        }
        return false
    }
}

// MARK: - Directory Provider
extension DownloadCache {

    func directory(for source: Source) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(source.id)
    }

    func directory(for manga: Manga) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(manga.sourceId)
            .appendingSafePathComponent(manga.id)
    }

    func directory(for chapter: Chapter) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(chapter.sourceId)
            .appendingSafePathComponent(chapter.mangaId)
            .appendingSafePathComponent(chapter.id)
    }

    func directory(forSourceId sourceId: String, mangaId: String) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(sourceId)
            .appendingSafePathComponent(mangaId)
    }
}
