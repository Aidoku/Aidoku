//
//  PartialDownloadTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/20/26.
//

@testable import Aidoku
import Foundation
import Testing

/// A download that stops with pages missing and one that is still running are both a staging
/// directory on disk, and only the failure marker tells them apart. These cover that distinction,
/// which is what a chapter being reported as downloaded while incomplete turned on.
@MainActor
struct PartialDownloadTests {
    @Test func reportsNoneWithoutAnyDirectory() {
        let chapter = identifier("none")
        defer { removeDirectories(for: chapter) }

        #expect(DownloadManager.shared.getDownloadStatus(for: chapter) == DownloadStatus.none)
    }

    @Test func reportsQueuedForUnmarkedStagingDirectory() {
        let cache = DownloadCache()
        let chapter = identifier("queued")
        defer { removeDirectories(for: chapter) }

        cache.tmpDirectory(for: chapter).createDirectory()

        #expect(DownloadManager.shared.getDownloadStatus(for: chapter) == .queued)
    }

    @Test func reportsFailedForMarkedStagingDirectory() throws {
        let cache = DownloadCache()
        let chapter = identifier("failed")
        defer { removeDirectories(for: chapter) }

        let tmpDirectory = cache.tmpDirectory(for: chapter)
        tmpDirectory.createDirectory()
        try Data("[3,7]".utf8).write(to: cache.failureMarker(inTmpDirectory: tmpDirectory))

        #expect(cache.hasFailureMarker(inTmpDirectory: tmpDirectory))
        #expect(DownloadManager.shared.getDownloadStatus(for: chapter) == .failed)
    }

    @Test func reportsFinishedForChapterDirectory() {
        let cache = DownloadCache()
        let chapter = identifier("finished")
        defer { removeDirectories(for: chapter) }

        cache.directory(for: chapter).createDirectory()

        #expect(DownloadManager.shared.getDownloadStatus(for: chapter) == .finished)
    }

    /// A retry refetches every page and the extension comes from the response, so anything the
    /// failed attempt left behind has to go or the chapter can end up holding a page twice.
    @Test func discardingAFailedDownloadTakesItsPagesWithIt() throws {
        let cache = DownloadCache()
        let chapter = identifier("discarded")
        defer { removeDirectories(for: chapter) }

        let tmpDirectory = cache.tmpDirectory(for: chapter)
        tmpDirectory.createDirectory()
        try Data().write(to: tmpDirectory.appendingPathComponent("001.png"))
        try Data("[2]".utf8).write(to: cache.failureMarker(inTmpDirectory: tmpDirectory))

        cache.discardFailedDownload(for: chapter)

        #expect(!tmpDirectory.exists)
    }

    /// Only a failed download is discarded: the same directory shape belongs to a download that is
    /// still running, and removing that would cancel it.
    @Test func discardingLeavesAnUnmarkedStagingDirectoryAlone() throws {
        let cache = DownloadCache()
        let chapter = identifier("running")
        defer { removeDirectories(for: chapter) }

        let tmpDirectory = cache.tmpDirectory(for: chapter)
        tmpDirectory.createDirectory()
        try Data().write(to: tmpDirectory.appendingPathComponent("001.png"))

        cache.discardFailedDownload(for: chapter)

        #expect(tmpDirectory.exists)
    }

    /// The marker lives inside the staging directory, so discarding a failed download stays a
    /// single removal and nothing is left beside it.
    @Test func markerLivesInsideTheStagingDirectory() {
        let cache = DownloadCache()
        let chapter = identifier("contained")
        defer { removeDirectories(for: chapter) }

        let tmpDirectory = cache.tmpDirectory(for: chapter)

        let marker = cache.failureMarker(inTmpDirectory: tmpDirectory)

        #expect(marker.deletingLastPathComponent().path == tmpDirectory.path)
    }
}

private extension PartialDownloadTests {
    // each test gets its own manga so that a leftover directory cannot affect another
    func identifier(_ name: String) -> ChapterIdentifier {
        .init(sourceKey: "test.partial-download", mangaKey: name, chapterKey: "1")
    }

    func removeDirectories(for chapter: ChapterIdentifier) {
        DownloadCache().directory(for: chapter.mangaIdentifier).removeItem()
    }
}
