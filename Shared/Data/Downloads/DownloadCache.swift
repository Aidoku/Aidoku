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

    private var rootDirectory = Directory(url: DownloadManager.directory)
    private var loaded = false

    // create cache from filesystem
    private func load() {
        for sourceDirectory in DownloadManager.directory.contents where sourceDirectory.isDirectory {
            rootDirectory.subdirectories[sourceDirectory.lastPathComponent] = Directory(url: sourceDirectory)
            for mangaDirectory in sourceDirectory.contents where mangaDirectory.isDirectory {
                var chapterDirectories: [String: Directory] = [:]
                for chapterFileOrDirectory in mangaDirectory.contents {
                    let key = if chapterFileOrDirectory.pathExtension.isEmpty {
                        chapterFileOrDirectory.lastPathComponent
                    } else {
                        chapterFileOrDirectory.deletingPathExtension().lastPathComponent
                    }
                    chapterDirectories[key] = Directory(url: chapterFileOrDirectory)
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
    func add(chapter: ChapterIdentifier) {
        let sourceDirectory = rootDirectory.subdirectories[chapter.sourceKey.directoryName]
        let sourceDirectoryURL = DownloadManager.directory.appendingSafePathComponent(chapter.sourceKey)
        if sourceDirectory == nil {
            rootDirectory.subdirectories[chapter.sourceKey.directoryName] = Directory(
                url: sourceDirectoryURL
            )
        }
        if sourceDirectory?.subdirectories[chapter.mangaKey.directoryName] == nil {
            rootDirectory
                .subdirectories[chapter.sourceKey.directoryName]?
                .subdirectories[chapter.mangaKey.directoryName] = Directory(
                    url: sourceDirectoryURL.appendingSafePathComponent(chapter.mangaKey)
                )
        }
        if sourceDirectory?.subdirectories[chapter.mangaKey.directoryName]?.subdirectories[chapter.chapterKey.directoryName] == nil {
            rootDirectory
                .subdirectories[chapter.sourceKey.directoryName]?
                .subdirectories[chapter.mangaKey.directoryName]?
                .subdirectories[chapter.chapterKey.directoryName] = Directory(
                    url: directory(for: chapter)
                )
        }
    }

    func remove(manga: MangaIdentifier) {
        rootDirectory.subdirectories[manga.sourceKey.directoryName]?
            .subdirectories[manga.mangaKey.directoryName] = nil
    }

    func remove(chapter: ChapterIdentifier) {
        rootDirectory.subdirectories[chapter.sourceKey.directoryName]?
            .subdirectories[chapter.mangaKey.directoryName]?
            .subdirectories[chapter.chapterKey.directoryName] = nil
    }

    func removeAll() {
        DownloadManager.directory.removeItem()
    }
}

extension DownloadCache {
    // check if a chapter has a download directory
    func isChapterDownloaded(identifier: ChapterIdentifier) -> Bool {
        if !loaded { load() }
        guard
            let sourceDirectory = rootDirectory.subdirectories[identifier.sourceKey.directoryName],
            let mangaDirectory = sourceDirectory.subdirectories[identifier.mangaKey.directoryName]
        else {
            return false
        }
        return mangaDirectory.subdirectories[identifier.chapterKey.directoryName] != nil
    }

    // check if any chapter subdirectories exist
    func hasDownloadedChapter(from identifier: MangaIdentifier) -> Bool {
        if !loaded { load() }
        guard
            let sourceDirectory = rootDirectory.subdirectories[identifier.sourceKey.directoryName],
            let mangaDirectory = sourceDirectory.subdirectories[identifier.mangaKey.directoryName]
        else {
            return false
        }
        return mangaDirectory.subdirectories.contains { !$0.value.url.lastPathComponent.hasPrefix(".tmp") }
    }
}

// MARK: Directory Provider
extension DownloadCache {
    nonisolated func directory(sourceKey: String) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(sourceKey)
    }

    nonisolated func directory(for manga: MangaIdentifier) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(manga.sourceKey)
            .appendingSafePathComponent(manga.mangaKey)
    }

    nonisolated func directory(for chapter: ChapterIdentifier) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(chapter.sourceKey)
            .appendingSafePathComponent(chapter.mangaKey)
            .appendingSafePathComponent(chapter.chapterKey)
    }

    nonisolated func tmpDirectory(for chapter: ChapterIdentifier) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(chapter.sourceKey)
            .appendingSafePathComponent(chapter.mangaKey)
            .appendingSafePathComponent(".tmp_\(chapter.chapterKey)")
    }
}
