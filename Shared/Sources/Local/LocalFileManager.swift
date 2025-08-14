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

    static let allowedFileExtensions = Set(["cbz", "zip"])
    static let allowedImageExtensions = Set(["jpg", "jpeg", "png", "webp"])

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

        // read zip file
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return nil
        }

        // find image entries (pages)
        let imageEntries = archive
            .filter { entry in
                let ext = String(entry.path.lowercased().split(separator: ".").last ?? "")
                return Self.allowedImageExtensions.contains(ext)
            }
            .sorted { $0.path < $1.path }

        guard !imageEntries.isEmpty else {
            return nil
        }

        // extract the first three images for preview
        let previewImages = imageEntries.prefix(3).compactMap { entry -> PlatformImage? in
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
            pageCount: imageEntries.count,
            fileType: fileType
        )
    }
}

extension LocalFileManager {
    // fetch pages for a chapter from file system
    func fetchPages(mangaId: String, chapterId: String) async -> [AidokuRunner.Page] {
        guard let cbzPath = await LocalFileDataManager.shared.fetchChapterArchivePath(mangaId: mangaId, chapterId: chapterId)
        else { return [] }

        // read zip file
        let documentsDir = FileManager.default.documentDirectory
        let archiveUrl = documentsDir.appendingPathComponent(cbzPath)
        let archive: Archive
        do {
            archive = try Archive(url: archiveUrl, accessMode: .read)
        } catch {
            return []
        }

        // find image entries (pages)
        let imageEntries = archive
            .filter { entry in
                let ext = String(entry.path.lowercased().split(separator: ".").last ?? "")
                return Self.allowedImageExtensions.contains(ext)
            }
            // sort by file name
            .sorted { $0.path < $1.path }

        return imageEntries.map { entry in
            AidokuRunner.Page(content: .zipFile(url: archiveUrl, filePath: entry.path))
        }
    }
}

extension LocalFileManager {
    // add a new file to the local files source
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
            guard let tempUrl = FileManager.default.temporaryDirectory?.appendingPathComponent(url.lastPathComponent) else {
                throw LocalFileManagerError.tempDirectoryUnavailable
            }
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

        // read zip file
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            LogManager.logger.error("Failed to read archive at \(url.path): \(error)")
            throw LocalFileManagerError.cannotReadArchive
        }

        // find image entries (pages)
        let imageEntries = archive
            .filter { entry in
                let ext = String(entry.path.lowercased().split(separator: ".").last ?? "")
                return Self.allowedImageExtensions.contains(ext)
            }
            .sorted { $0.path < $1.path }

        guard !imageEntries.isEmpty else {
            throw LocalFileManagerError.noImagesFound
        }

        let resolvedMangaId = mangaId ?? mangaName ?? url.deletingPathExtension().lastPathComponent
        let mangaTitle = mangaName ?? resolvedMangaId

        // create new folder for the manga
        let fileManager = FileManager.default
        let localFolder = fileManager.documentDirectory.appendingPathComponent("Local", isDirectory: true)
        localFolder.createDirectory()
        let mangaFolder = localFolder.appendingPathComponent(resolvedMangaId, isDirectory: true)
        mangaFolder.createDirectory()

        // get chapter number
        let chapter = if volume == nil && chapter == nil {
            if let mangaId {
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
            let firstImageEntry = imageEntries.first!
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

        // create the objects in db
        let hasMangaObject = if let mangaId {
            await LocalFileDataManager.shared.hasSeries(name: mangaId)
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
                description: mangaDescription
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
            chapter: chapter
        )
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
    }

    // remove a chapter from a given local manga
    func removeChapter(mangaId: String, chapterId: String) async {
        // remove from db
        let filePath = await LocalFileDataManager.shared.removeChapter(mangaId: mangaId, chapterId: chapterId)
        guard let filePath else { return }

        // disable file listener while we make changes to the disk
        self.suppressFileEvents = true
        defer { self.suppressFileEvents = false }

        let documentsDir = FileManager.default.documentDirectory
        let fileURL = documentsDir.append(path: filePath)
        if fileURL.exists {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // remove all local source files and db objects
    func removeAllLocalFiles() {
        // disable file listener while we make changes to the disk
        self.suppressFileEvents = true
        defer { self.suppressFileEvents = false }

        let fileManager = FileManager.default
        let documentsDir = fileManager.documentDirectory
        let localFolder = documentsDir.appendingPathComponent("Local", isDirectory: true)
        do {
            try fileManager.removeItem(at: localFolder)
        } catch {
            LogManager.logger.error("Failed to remove Local folder: \(error)")
        }
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

        let fileManager = FileManager.default
        let documentsDir = fileManager.documentDirectory
        let localFolder = documentsDir.appendingPathComponent("Local", isDirectory: true)
        localFolder.createDirectory()

        // get all manga folders
        let mangaFolders = (try? fileManager.contentsOfDirectory(
            at: localFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ))?.filter { $0.isDirectory } ?? []

        let (toRemove, toAdd) = await LocalFileDataManager.shared.findMangaDiskChanges(mangaFolders: mangaFolders)

        // remove manga from db that no longer exist on disk
        for mangaId in toRemove {
            await removeManga(with: mangaId)
        }

        // add manga to db that exist on disk but not in db yet
        for folder in mangaFolders where toAdd.contains(folder.lastPathComponent) {
            // find cbz files in this folder
            let cbzFiles = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ))?.filter { Self.allowedFileExtensions.contains($0.pathExtension.lowercased()) } ?? []
            let mangaId = folder.lastPathComponent
            // add cbz files as chapters
            for cbzFile in cbzFiles {
                do {
                    try await uploadFile(from: cbzFile, skipUpload: true, mangaId: mangaId)
                } catch {
                    LogManager.logger.error("Failed to process file \(cbzFile.lastPathComponent) for new manga \(mangaId): \(error)")
                }
            }
        }

        // for each manga folder, ensure chapters in db match local files
        for folder in mangaFolders {
            let mangaId = folder.lastPathComponent
            // find cbz files in this folder
            let cbzFiles = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ))?.filter { Self.allowedFileExtensions.contains($0.pathExtension.lowercased()) } ?? []
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
