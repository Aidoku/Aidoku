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

    /// Prefix of the directory a chapter is downloaded into before it is promoted to a chapter.
    nonisolated static let tmpDirectoryPrefix = ".tmp_"

    nonisolated func tmpDirectory(for chapter: ChapterIdentifier) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(chapter.sourceKey)
            .appendingSafePathComponent(chapter.mangaKey)
            .appendingSafePathComponent("\(Self.tmpDirectoryPrefix)\(chapter.chapterKey)")
    }

    /// Marks a staging directory as a download that finished with pages missing.
    ///
    /// A partial failure and a download still in progress are otherwise identical on disk: both are
    /// a `.tmp` directory holding some of the pages, so without this a failed chapter would report
    /// itself queued for ever. The marker names the pages that failed, which is what a later resume
    /// would need to refetch only those.
    ///
    /// It is inside the staging directory rather than beside it so that discarding the download is
    /// still one `removeItem`, and it is named so that it cannot be mistaken for a page: pages are
    /// `%03d` with an image extension.
    nonisolated func failureMarker(inTmpDirectory directory: URL) -> URL {
        directory.appendingPathComponent(Self.failureMarkerName)
    }

    nonisolated static let failureMarkerName = ".failed"

    /// Whether a staging directory holds a download that failed rather than one still running.
    nonisolated func hasFailureMarker(inTmpDirectory directory: URL) -> Bool {
        failureMarker(inTmpDirectory: directory).exists
    }

    /// Discards whatever a previous attempt left behind for a chapter that failed.
    ///
    /// A retry refetches every page, and the extension a page is stored under comes from its
    /// response, so a page arriving as a jpeg where it was a png before would leave both files in
    /// place and the chapter would end up showing that page twice.
    nonisolated func discardFailedDownload(for chapter: ChapterIdentifier) {
        let directory = tmpDirectory(for: chapter)
        guard hasFailureMarker(inTmpDirectory: directory) else { return }
        directory.removeItem()
    }
}
