//
//  LocalFileManager.swift
//  Aidoku
//
//  Created by Skitty on 6/6/25.
//

import AidokuRunner
import CoreData
import Foundation
import ZIPFoundation

#if os(macOS)
import AppKit
#endif

/// Manages local files stored in the documents directory for the local files source.
actor LocalFileManager {
    static let shared = LocalFileManager()

    private var lastScanTime = Date.distantPast
    private var scanTask: Task<Void, Never>?

    static let allowedFileExtensions = Set(["cbz", "zip", "epub"])
    static let allowedImageExtensions = Set(["jpg", "jpeg", "png", "webp", "gif", "heic", "avif"])
    static let allowedTextExtensions = Set(["txt", "md"])
    static let allowedPageExtensions = allowedImageExtensions.union(allowedTextExtensions)

    private var localFolderFileDescriptor: CInt?
    private var localFolderSource: DispatchSourceFileSystemObject?

    private var suppressFileEvents = false

    private init() {
        Task {
            await startFileSystemListener()
        }
    }

    deinit {
        localFolderSource?.cancel()
        localFolderSource = nil
    }
}

extension LocalFileManager {
    // get info about a file to be imported
    func loadImportFileInfo(url: URL) -> ImportFileInfo? {
        // if the given url comes from an imported file that isn't copied, we need to do this
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { url.stopAccessingSecurityScopedResource() }
        }

        // ensure the file is one we can parse
        let pathExtension = url.pathExtension.lowercased()
        guard Self.allowedFileExtensions.contains(pathExtension) else {
            return nil
        }

        if pathExtension == "epub" {
            guard let book = EpubParser.parse(url: url), !book.chapters.isEmpty else {
                return nil
            }
            // carry epub metadata through the existing ComicInfo import path
            var comicInfo = ComicInfo()
            comicInfo.series = book.title
            comicInfo.summary = book.description
            comicInfo.writer = book.author
            return ImportFileInfo(
                url: url,
                previewImages: book.coverData.flatMap { PlatformImage(data: $0) }.map { [$0] } ?? [],
                name: url.lastPathComponent,
                pageCount: book.chapters.count,
                fileType: .epub,
                comicInfo: comicInfo
            )
        }

        // read zip file
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return nil
        }

        // find image entries (pages)
        let pageEntries = archive
            .filter { entry in
                let lastPathComponent = entry.path.lastPathComponent()
                guard !lastPathComponent.hasPrefix(".") else {
                    return false
                }
                let ext = entry.path.pathExtension().lowercased()
                if ext == "txt" {
                    return !entry.path.hasSuffix("desc.txt")
                }
                return Self.allowedPageExtensions.contains(ext)
            }
            .sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }

        guard !pageEntries.isEmpty else {
            return nil
        }

        // extract the first three images for preview
        let previewImages = pageEntries
            .filter { LocalFileManager.allowedImageExtensions.contains($0.path.lowercased()) }
            .prefix(3)
            .compactMap { entry -> PlatformImage? in
                var imageData = Data()
                do {
                    _ = try archive.extract(
                        entry,
                        consumer: { data in
                            imageData.append(data)
                        }
                    )
                    return PlatformImage(data: imageData)
                } catch {
                    return nil
                }
            }

        let fileType = switch pathExtension {
            case "cbz": LocalFileType.cbz
            case "zip": LocalFileType.zip
            default: LocalFileType.zip
        }

        return ImportFileInfo(
            url: url,
            previewImages: previewImages,
            name: url.lastPathComponent,
            pageCount: pageEntries.count,
            fileType: fileType,
            comicInfo: ComicInfo.load(from: url)
        )
    }
}

extension LocalFileManager {
    // fetch pages for a chapter from file system
    func fetchPages(mangaId: String, chapterId: String) async -> [AidokuRunner.Page] {
        guard let cbzPath = await LocalFileDataManager.shared.fetchChapterArchivePath(mangaId: mangaId, chapterId: chapterId)
        else { return [] }

        let documentsDir = FileManager.default.documentDirectory
        let archiveURL = documentsDir.appendingPathComponent(cbzPath)
        if archiveURL.pathExtension.lowercased() == "epub" {
            return readEpubPages(from: archiveURL, chapterId: chapterId)
        }
        return readPages(from: archiveURL)
    }

    // read the pages for an epub chapter
    // the chapter id has the format "<epub file name>/<content file path>"
    nonisolated func readEpubPages(from archiveURL: URL, chapterId: String) -> [AidokuRunner.Page] {
        let prefix = archiveURL.lastPathComponent + "/"
        let href = chapterId.hasPrefix(prefix) ? String(chapterId.dropFirst(prefix.count)) : chapterId
        let segments = EpubParser.chapterSegments(url: archiveURL, href: href)
        guard !segments.isEmpty else {
            LogManager.logger.error("Failed to read epub chapter \(chapterId) from \(archiveURL.lastPathComponent)")
            return []
        }

        let hasText = segments.contains {
            if case .text = $0 { return true }
            return false
        }

        if hasText {
            // build a single markdown page with inline image references so the
            // whole chapter stays in the text reader
            let parts: [String] = segments.compactMap { segment in
                switch segment {
                    case .text(let text):
                        return text
                    case .image(let path):
                        guard let cachedURL = Self.cacheEpubImage(archiveURL: archiveURL, path: path) else {
                            return nil
                        }
                        return "![image](\(cachedURL.absoluteString))"
                }
            }
            return [AidokuRunner.Page(content: .text(parts.joined(separator: "\n\n")))]
        }

        // image-only chapter (cover, illustration pages)
        return segments.compactMap { segment in
            guard case let .image(path) = segment else { return nil }
            return AidokuRunner.Page(content: .zipFile(url: archiveURL, filePath: path))
        }
    }

    // cache directory for extracted images of a given epub archive
    nonisolated static func epubImageCacheDirectory(for archiveURL: URL) -> URL? {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }

        // stable per-book folder name (fnv-1a hash)
        func hash(_ string: String) -> String {
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in string.utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
            return String(hash, radix: 16)
        }

        return cachesDir
            .appendingPathComponent("EpubImages", isDirectory: true)
            .appendingPathComponent(hash(archiveURL.path), isDirectory: true)
    }

    // extract an image from an epub archive into the cache directory so it can
    // be referenced with a file url from markdown text
    nonisolated static func cacheEpubImage(archiveURL: URL, path: String) -> URL? {
        guard let bookDir = epubImageCacheDirectory(for: archiveURL) else { return nil }
        let fileURL = bookDir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))

        if fileURL.exists {
            return fileURL
        }

        bookDir.createDirectory()
        do {
            let archive = try Archive(url: archiveURL, accessMode: .read)
            guard let entry = EpubParser.entry(in: archive, path: path) else { return nil }
            _ = try archive.extract(entry, to: fileURL)
            return fileURL
        } catch {
            LogManager.logger.error("Failed to extract epub image \(path): \(error)")
            return nil
        }
    }

    // read pages from an archive file
    nonisolated func readPages(from archiveURL: URL) -> [AidokuRunner.Page] {
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            LogManager.logger.error("Failed to read archive: \(error)")
            return []
        }

        var descriptionFiles: [Entry] = []

        var pages = archive
            .filter { entry in
                // ignore hidden files
                let lastPathComponent = entry.path.lastPathComponent()
                guard !lastPathComponent.hasPrefix(".") else {
                    return false
                }
                // ensure extension is allowed
                let ext = entry.path.pathExtension().lowercased()
                if ext == "txt" {
                    if entry.path.hasSuffix("desc.txt") {
                        descriptionFiles.append(entry)
                        return false
                    }
                    return true
                }
                return Self.allowedPageExtensions.contains(ext)
            }
            // sort by file name
            .sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            .map { entry in
                AidokuRunner.Page(content: .zipFile(url: archiveURL, filePath: entry.path))
            }

        for entry in descriptionFiles {
            guard
                let index = entry.path
                    .lastPathComponent()
                    .split(separator: ".", maxSplits: 1)
                    .first
                    .flatMap({ Int($0) }),
                index > 0,
                index <= pages.count
            else { break }

            do {
                var descriptionData = Data()
                _ = try archive.extract(
                    entry,
                    consumer: { data in
                        descriptionData.append(data)
                    }
                )
                pages[index - 1].hasDescription = true
                pages[index - 1].description = String(data: descriptionData, encoding: .utf8)
            } catch {
                LogManager.logger.error("Failed to extract page description text from archive: \(error)")
                continue
            }
        }

        return pages
    }
}

extension LocalFileManager {
    // add a new file to the local files source
    // swiftlint:disable:next cyclomatic_complexity
    func uploadFile(
        from url: URL,
        // if the file already exists, skip uploading it to avoid duplicates
        skipUpload: Bool = false,
        // the (optional) manga id to add to
        mangaId: String? = nil,
        // optional metadata for new db objects:
        mangaCoverImage: PlatformImage? = nil,
        mangaName: String? = nil,
        mangaDescription: String? = nil,
        chapterName: String? = nil,
        volume: Float? = nil,
        chapter: Float? = nil
    ) async throws(LocalFileManagerError) {
        // disable file listener while we make changes to the disk
        self.suppressFileEvents = true
        defer { self.suppressFileEvents = false }

        let documentsDirectory = FileManager.default.documentDirectory

        // ensure the file is one we can parse
        guard Self.allowedFileExtensions.contains(url.pathExtension.lowercased()) else {
            throw LocalFileManagerError.invalidFileType
        }

        // if the url isn't in the documents directory, we need to copy it there
        var url = url
        var shouldRemoveUrl = false
        if !url.path.contains(documentsDirectory.path) {
            // if the given url comes from an imported file that isn't copied, we need to do this
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { url.stopAccessingSecurityScopedResource() }
            }

            // create a temporary url to copy file to
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            // copy url to temp folder
            do {
                try FileManager.default.copyItem(at: url, to: tempUrl)
            } catch {
                throw LocalFileManagerError.fileCopyFailed
            }
            // remove the temporary file when done
            shouldRemoveUrl = true
            url = tempUrl
        }
        defer {
            if shouldRemoveUrl {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // epub files create a chapter per spine item instead of image pages
        if url.pathExtension.lowercased() == "epub" {
            try await uploadEpub(
                from: url,
                skipUpload: skipUpload,
                mangaId: mangaId,
                mangaCoverImage: mangaCoverImage,
                mangaName: mangaName,
                mangaDescription: mangaDescription
            )
            return
        }

        // read zip file
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            LogManager.logger.error("Failed to read archive at \(url.path): \(error)")
            throw LocalFileManagerError.cannotReadArchive
        }

        // find image entries (pages)
        let pageEntries = archive
            .filter { entry in
                let lastPathComponent = entry.path.lastPathComponent()
                guard !lastPathComponent.hasPrefix(".") else {
                    return false
                }
                let ext = entry.path.pathExtension().lowercased()
                if ext == "txt" {
                    return !entry.path.hasSuffix("desc.txt")
                }
                return Self.allowedPageExtensions.contains(ext)
            }
            .sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }

        guard !pageEntries.isEmpty else {
            throw LocalFileManagerError.noImagesFound
        }

        let comicInfo = ComicInfo.load(from: archive)

        let resolvedMangaId = (mangaId ?? mangaName ?? url.deletingPathExtension().lastPathComponent).normalized
        let mangaTitle = mangaName ?? comicInfo?.series ?? resolvedMangaId

        // create new folder for the manga
        let fileManager = FileManager.default
        let localFolder = fileManager.documentDirectory.appendingPathComponent("Local", isDirectory: true)
        localFolder.createDirectory()
        let mangaFolder = localFolder.appendingPathComponent(resolvedMangaId, isDirectory: true)
        mangaFolder.createDirectory()

        // get chapter number
        let chapter = if volume == nil && chapter == nil {
            if let comicInfo, let number = comicInfo.number, let chapter = Float(number) {
                chapter
            } else if let chapter = LocalFileNameParser.getMangaChapterNumber(from: url.lastPathComponent) {
                chapter
            } else if let mangaId {
                await LocalFileDataManager.shared.getNextChapterNumber(series: mangaId)
            } else {
                Float(1)
            }
        } else {
            chapter
        }

        let destURL: URL

        if skipUpload {
            destURL = url
        } else {
            // get new name for file if necessary
            let newFile = if let chapterName {
                if chapterName.isEmpty {
                    if let volume, let chapter {
                        "volume_\(volume)_chapter_\(chapter).\(url.pathExtension)"
                    } else if let volume {
                        "volume_\(volume).\(url.pathExtension)"
                    } else if let chapter {
                        "chapter_\(chapter).\(url.pathExtension)"
                    } else {
                        "\(resolvedMangaId).\(url.pathExtension)"
                    }
                } else {
                    "\(chapterName).\(url.pathExtension)"
                }
            } else {
                url.lastPathComponent
            }

            // copy file to Documents/Local/<mangaId>/<cbzfile>
            var newDestURL = mangaFolder.appendingPathComponent(newFile)
            var counter = 1
            while newDestURL.exists {
                // if the file already exists, append a number to the name
                let name = newFile.removingExtension() + " (\(counter)).\(url.pathExtension)"
                newDestURL = mangaFolder.appendingPathComponent(name)
                counter += 1
            }
            destURL = newDestURL
            do {
                try fileManager.copyItem(at: url, to: destURL)
            } catch {
                throw LocalFileManagerError.fileCopyFailed
            }
        }

        let coverURL: URL?
        if let mangaCoverImage {
            // save provided cover image to manga folder
            let coverFileName = "cover.png"
            let newCoverURL = mangaFolder.appendingPathComponent(coverFileName)
            do {
                if newCoverURL.exists {
                    try fileManager.removeItem(at: newCoverURL)
                }
                try mangaCoverImage.pngData()?.write(to: newCoverURL)
                coverURL = newCoverURL
            } catch {
                throw LocalFileManagerError.fileCopyFailed
            }
        } else if mangaId == nil {
            // copy first page image to use as cover image
            let firstImageEntry = pageEntries.first(where: { LocalFileManager.allowedImageExtensions.contains($0.path.lowercased()) })
            if let firstImageEntry {
                let coverExt = (firstImageEntry.path as NSString).pathExtension
                let coverFileName = "cover.\(coverExt)"
                let newCoverURL = mangaFolder.appendingPathComponent(coverFileName)
                do {
                    if newCoverURL.exists {
                        try? fileManager.removeItem(at: newCoverURL)
                    }
                    _ = try archive.extract(firstImageEntry, to: newCoverURL)
                    coverURL = newCoverURL
                } catch {
                    throw LocalFileManagerError.fileCopyFailed
                }
            } else {
                coverURL = nil
            }
        } else {
            coverURL = nil
        }

        // create the objects in db
        let hasMangaObject = if let mangaId {
            await LocalFileDataManager.shared.hasSeries(id: mangaId)
        } else {
            false
        }
        if !hasMangaObject {
            let cover = coverURL?.toAidokuImageUrl()?.absoluteString ?? {
                // if no cover url, try finding one in the directory
                for ext in Self.allowedImageExtensions {
                    let coverPath = mangaFolder.appendingPathComponent("cover.\(ext)")
                    if coverPath.exists {
                        return coverPath.toAidokuImageUrl()?.absoluteString
                    }
                }
                return nil
            }()
            await LocalFileDataManager.shared.createManga(
                url: mangaFolder,
                id: resolvedMangaId,
                title: mangaTitle,
                cover: cover,
                description: mangaDescription,
                comicInfo: comicInfo
            )
        }

        let title = if let chapterName {
            chapterName.isEmpty ? nil : chapterName
        } else {
            url.deletingPathExtension().lastPathComponent
        }

        await LocalFileDataManager.shared.createChapter(
            mangaId: resolvedMangaId,
            url: destURL,
            id: UUID().uuidString,
            title: title,
            volume: volume,
            chapter: chapter,
            comicInfo: comicInfo
        )
    }

    // add an epub file to the local files source, creating a chapter per spine item
    // swiftlint:disable:next function_parameter_count
    private func uploadEpub(
        from url: URL,
        skipUpload: Bool,
        mangaId: String?,
        mangaCoverImage: PlatformImage?,
        mangaName: String?,
        mangaDescription: String?
    ) async throws(LocalFileManagerError) {
        guard let book = EpubParser.parse(url: url) else {
            throw LocalFileManagerError.cannotReadArchive
        }
        guard !book.chapters.isEmpty else {
            throw LocalFileManagerError.noImagesFound
        }

        let resolvedMangaId = (mangaId ?? mangaName ?? book.title ?? url.deletingPathExtension().lastPathComponent).normalized
        let mangaTitle = mangaName ?? book.title ?? resolvedMangaId

        // create new folder for the manga
        let fileManager = FileManager.default
        let localFolder = fileManager.documentDirectory.appendingPathComponent("Local", isDirectory: true)
        localFolder.createDirectory()
        let mangaFolder = localFolder.appendingPathComponent(resolvedMangaId, isDirectory: true)
        mangaFolder.createDirectory()

        // copy file to Documents/Local/<mangaId>/<epubfile>
        let destURL: URL
        if skipUpload {
            destURL = url
        } else {
            var newDestURL = mangaFolder.appendingPathComponent(url.lastPathComponent)
            var counter = 1
            while newDestURL.exists {
                let name = url.lastPathComponent.removingExtension() + " (\(counter)).\(url.pathExtension)"
                newDestURL = mangaFolder.appendingPathComponent(name)
                counter += 1
            }
            destURL = newDestURL
            do {
                try fileManager.copyItem(at: url, to: destURL)
            } catch {
                throw LocalFileManagerError.fileCopyFailed
            }
        }

        // save provided cover image, or fall back to the embedded epub cover
        var coverURL: URL?
        let coverImage = mangaCoverImage ?? book.coverData.flatMap { PlatformImage(data: $0) }
        if mangaCoverImage != nil || mangaId == nil, let coverImage {
            let newCoverURL = mangaFolder.appendingPathComponent("cover.png")
            do {
                if newCoverURL.exists {
                    try fileManager.removeItem(at: newCoverURL)
                }
                try coverImage.pngData()?.write(to: newCoverURL)
                coverURL = newCoverURL
            } catch {
                throw LocalFileManagerError.fileCopyFailed
            }
        }

        // create the manga object in db if it doesn't exist yet
        let hasMangaObject = if let mangaId {
            await LocalFileDataManager.shared.hasSeries(id: mangaId)
        } else {
            false
        }
        if !hasMangaObject {
            // carry epub metadata (author) through the ComicInfo path
            var comicInfo = ComicInfo()
            comicInfo.writer = book.author
            await LocalFileDataManager.shared.createManga(
                url: mangaFolder,
                id: resolvedMangaId,
                title: mangaTitle,
                cover: coverURL?.toAidokuImageUrl()?.absoluteString,
                description: mangaDescription ?? book.description,
                // books read left to right, unlike the rtl manga default
                viewer: .leftToRight,
                comicInfo: comicInfo
            )
        }

        // create a chapter for each spine item
        // the chapter id encodes the content file path so pages can be fetched later
        let fileName = destURL.lastPathComponent
        for (index, chapter) in book.chapters.enumerated() {
            await LocalFileDataManager.shared.createChapter(
                mangaId: resolvedMangaId,
                url: destURL,
                id: "\(fileName)/\(chapter.href)",
                title: chapter.title,
                chapter: Float(index + 1)
            )
        }
    }
}

extension LocalFileManager {
    func setCover(for mangaId: String, image: PlatformImage) async -> String? {
        let mangaData = await LocalFileDataManager.shared.fetchLocalSeries(id: mangaId)

        // remove the cover image file if it exists
        if let cover = mangaData?.cover, let url = URL(string: cover) {
            let fileURL = url.toAidokuFileUrl() ?? url
            if fileURL.isFileURL {
                fileURL.removeItem()
            }
        }

        // upload the new cover
        let fileManager = FileManager.default
        let localFolder = fileManager.documentDirectory.appendingPathComponent("Local", isDirectory: true)
        let mangaFolder = localFolder.appendingPathComponent(mangaId, isDirectory: true)
        let coverFileName = "cover.png"
        let newCoverURL = mangaFolder.appendingPathComponent(coverFileName)
        do {
            try image.pngData()?.write(to: newCoverURL)
        } catch {
            LogManager.logger.error("Failed to write cover image for manga \(mangaId): \(error)")
            return nil
        }

        // set cover image in coredata
        return await CoreDataManager.shared.setCover(
            sourceId: LocalSourceRunner.sourceKey,
            mangaId: mangaId,
            coverUrl: newCoverURL.toAidokuImageUrl()?.absoluteString
        )
    }
}

// MARK: Removing
extension LocalFileManager {
    // remove all db objects and local files associated with a given mangaId
    func removeManga(with mangaId: String) async {
        // remove from db
        let filePath = await LocalFileDataManager.shared.removeManga(with: mangaId)
        guard let filePath else { return }

        // disable file listener while we make changes to the disk
        self.suppressFileEvents = true
        defer { self.suppressFileEvents = false }

        let documentsDir = FileManager.default.documentDirectory
        let fileURL = documentsDir.appendingPathComponent(filePath)
        if fileURL.exists {
            try? FileManager.default.removeItem(at: fileURL)
        }
        Self.removeEpubImageCache(for: fileURL)
    }

    // remove a chapter from a given local manga
    func removeChapter(mangaId: String, chapterId: String) async {
        // remove from db
        let filePath = await LocalFileDataManager.shared.removeChapter(mangaId: mangaId, chapterId: chapterId)

        if let filePath {
            // disable file listener while we make changes to the disk
            self.suppressFileEvents = true
            defer { self.suppressFileEvents = false }

            let documentsDir = FileManager.default.documentDirectory
            let fileURL = documentsDir.append(path: filePath)
            if fileURL.exists {
                try? FileManager.default.removeItem(at: fileURL)
            }
            Self.removeEpubImageCache(for: fileURL)
        }

        // remove the manga entry once no chapters remain
        if await LocalFileDataManager.shared.fetchChapters(mangaId: mangaId).isEmpty {
            await removeManga(with: mangaId)
        }
    }

    // remove cached extracted images for a given epub archive
    nonisolated static func removeEpubImageCache(for archiveURL: URL) {
        guard archiveURL.pathExtension.lowercased() == "epub",
              let bookDir = epubImageCacheDirectory(for: archiveURL)
        else { return }
        try? FileManager.default.removeItem(at: bookDir)
    }

    // remove all local source files and db objects
    func removeAllLocalFiles() async {
        // disable file listener while we make changes to the disk
        self.suppressFileEvents = true

        let fileManager = FileManager.default
        let documentsDir = fileManager.documentDirectory
        let localFolder = documentsDir.appendingPathComponent("Local", isDirectory: true)
        do {
            try fileManager.removeItem(at: localFolder)
        } catch {
            LogManager.logger.error("Failed to remove Local folder: \(error)")
        }

        // clear extracted epub images
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: cachesDir.appendingPathComponent("EpubImages", isDirectory: true))
        }

        // update database
        self.suppressFileEvents = false
        await scanLocalFiles()
    }
}

// MARK: Scanning
extension LocalFileManager {
    // performs a scan if the last one was over an hour ago (or if one hasn't been run this app launch)
//    func scanIfNecessary() async {
//        if lastScanTime < Date().addingTimeInterval(-60 * 60) {
//            await scanLocalFiles()
//            lastScanTime = Date()
//        }
//    }

    // scan the local files folder and synchronize the db to match the file system
    func scanLocalFiles() async {
        // don't scan while suppressing file events
        guard !suppressFileEvents else { return }

        // ensure only one scan is running at a time
        guard scanTask == nil else {
            await scanTask?.value
            return
        }

        scanTask = Task {
            let fileManager = FileManager.default
            let documentsDir = fileManager.documentDirectory
            let localFolder = documentsDir.appendingPathComponent("Local", isDirectory: true)
            localFolder.createDirectory()

            // get all manga folders
            let mangaFolders = localFolder.contents.filter { $0.isDirectory }

            let (toRemove, toAdd) = await LocalFileDataManager.shared.findMangaDiskChanges(mangaFolders: mangaFolders)

            // remove manga from db that no longer exist on disk
            for mangaId in toRemove {
                await removeManga(with: mangaId)
            }

            // for each manga folder, ensure chapters in db match local files
            for folder in mangaFolders {
                let mangaId = folder.lastPathComponent.normalized

                // find cbz files in this folder
                let cbzFiles = folder.contents
                    .filter {
                        Self.allowedFileExtensions.contains($0.pathExtension.lowercased())
                    }
                    .sorted {
                        $0.path.localizedStandardCompare($1.path) == .orderedAscending
                    }

                // add manga to db that exist on disk but not in db yet
                if toAdd.contains(mangaId) {
                    // add cbz files as chapters
                    for cbzFile in cbzFiles {
                        do {
                            try await uploadFile(from: cbzFile, skipUpload: true, mangaId: mangaId)
                        } catch {
                            LogManager.logger.error("Failed to process file \(cbzFile.lastPathComponent) for new manga \(mangaId): \(error)")
                        }
                    }
                } else {
                    // add missing chapters
                    let cbzFileNames = Set(cbzFiles.map { $0.lastPathComponent })

                    let dbChapterFileNames = await LocalFileDataManager.shared.removeMissingChapters(
                        mangaId: mangaId,
                        availableChapters: cbzFileNames
                    )

                    // add chapters for new cbz files
                    let chaptersToAdd = cbzFiles.filter { !dbChapterFileNames.contains($0.lastPathComponent) }
                    for cbzFile in chaptersToAdd {
                        do {
                            try await uploadFile(from: cbzFile, skipUpload: true, mangaId: mangaId)
                        } catch {
                            LogManager.logger.error("Failed to process file \(cbzFile.lastPathComponent) for manga \(mangaId): \(error)")
                        }
                    }
                }
            }

            // clear running task (complete)
            scanTask = nil
        }
        await scanTask?.value
    }
}

// MARK: File Listener
extension LocalFileManager {
    // start listening for file system changes in the local folder
    func startFileSystemListener() {
        let localFolder = FileManager.default.documentDirectory
            .appendingPathComponent("Local", isDirectory: true)
        localFolder.createDirectory()

        let fd = open(localFolder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        localFolderFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .background)
        )
        source.setEventHandler {
            // run a scan when a file is changed
            Task { await LocalFileManager.shared.scanLocalFiles() }
        }
        source.setCancelHandler {
            Task { await LocalFileManager.shared.closeLocalFolderFileDescriptor() }
        }
        localFolderSource = source
        source.resume()
    }

    // stop file system listener
//    func stopFileSystemListener() {
//        localFolderSource?.cancel()
//        localFolderSource = nil
//    }

    private func closeLocalFolderFileDescriptor() {
        if let fd = self.localFolderFileDescriptor {
            close(fd)
            self.localFolderFileDescriptor = nil
        }
    }
}
