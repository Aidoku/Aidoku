//
//  EpubDownloadLayoutTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 9/4/26.
//

@testable import Aidoku
import AidokuRunner
import Foundation
import Testing
import ZIPFoundation

// a downloaded epub is one file beside the cbz files, carrying ComicInfo.xml inside it
@MainActor
struct EpubDownloadLayoutTests {
    @Test func aBookBesideTheArchivesIsAFinishedDownload() async throws {
        let book = try EpubFixture.makeBook(documents: [2, 3])
        defer { EpubFixture.remove(book.url) }
        let chapter = ChapterIdentifier(sourceKey: "epub-layout-test", mangaKey: "series", chapterKey: "book-1")
        let cache = DownloadCache()
        let sourceDirectory = cache.directory(sourceKey: chapter.sourceKey)
        defer { sourceDirectory.removeItem() }
        let target = cache.directory(for: chapter).appendingPathExtension("epub")
        target.deletingLastPathComponent().createDirectory()
        try FileManager.default.copyItem(at: book.url, to: target)

        #expect(cache.downloadedItem(for: chapter) == target)
        #expect(DownloadManager.shared.getDownloadStatus(for: chapter) == .finished)
        #expect(await DownloadManager.shared.downloadsCount(for: chapter.mangaIdentifier) == 1)
        #expect(await DownloadManager.shared.getCompressedFile(for: chapter) == target)
        let pages = await DownloadManager.shared.getDownloadedPages(for: chapter)
        #expect(pages.count == 2)
        #expect(pages.allSatisfy {
            if case .zipFile(let url, _) = $0.content { url == target } else { false }
        })
    }

    @Test func metadataAddedToTheBookIsReadBackAndTheBookStillOpens() throws {
        let book = try EpubFixture.makeBook(documents: [1])
        defer { EpubFixture.remove(book.url) }
        let manga = AidokuRunner.Manga(sourceKey: "epub-layout-test", key: "series", title: "Series")
        let chapter = AidokuRunner.Chapter(key: "book-1", title: "The Book", chapterNumber: 7)
        let metadata = FileManager.default.temporaryDirectory.appendingPathComponent("ComicInfo-\(UUID().uuidString).xml")
        try ComicInfo.load(manga: manga, chapter: chapter).export().write(to: metadata, atomically: true, encoding: .utf8)
        defer { metadata.removeItem() }

        let archive = try Archive(url: book.url, accessMode: .update)
        try archive.addEntry(with: "ComicInfo.xml", fileURL: metadata, compressionMethod: .deflate)

        let read = ComicInfo.load(from: book.url)
        #expect(read?.title == "The Book")
        #expect(read?.number == "7")
        #expect(LocalFileManager.shared.readEpubPages(from: book.url).count == 1)
    }
}
