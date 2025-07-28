//
//  LocalFileDataManager.swift
//  Aidoku
//
//  Created by Skitty on 6/10/25.
//

import AidokuRunner
import CoreData
import ZIPFoundation

final actor LocalFileDataManager {
    static let shared = LocalFileDataManager()

    private let context: NSManagedObjectContext
    private let objectExecutor: ObjectActorSerialExecutor
    public nonisolated let unownedExecutor: UnownedSerialExecutor

    init() {
        context = CoreDataManager.shared.container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        self.objectExecutor = ObjectActorSerialExecutor(context: context)
        self.unownedExecutor = objectExecutor.asUnownedSerialExecutor()
    }
}

// MARK: Checking
extension LocalFileDataManager {
    // check if a series exists in the db with the given name (id)
    func hasSeries(name: String) -> Bool {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "fileInfo != nil AND id == %@", name)
        request.fetchLimit = 1
        return (try? context.count(for: request)) == 1
    }

    // check if a series has a chapter with the given volume and chapter numbers
    func hasChapter(series: String, volume: Float?, chapter: Float?) -> Bool {
        let request = ChapterObject.fetchRequest()
        var predicateString = "fileInfo != nil AND mangaId == %@"
        var args: [Any] = [series]
        if let volume {
            predicateString += " AND volume == %@"
            args.append(NSNumber(value: volume))
        } else {
            predicateString += " AND (volume = nil OR volume == -1)"
        }
        if let chapter {
            predicateString += " AND chapter == %@"
            args.append(NSNumber(value: chapter))
        } else {
            predicateString += " AND (chapter = nil OR chapter == -1)"
        }
        request.predicate = NSPredicate(format: predicateString, argumentArray: args)
        request.fetchLimit = 1
        return (try? context.count(for: request)) == 1
    }

    // get the next chapter number to assign a new chapter for a series
    func getNextChapterNumber(series: String) -> Float {
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(format: "fileInfo != nil AND mangaId == %@", series)
        guard let results = try? context.fetch(request) else { return 1}

        // get all chapter numbers
        let chapterNums = Set(results.compactMap { $0.chapter?.floatValue })

        // find lowest chapter number that doesn't exist
        var nextChapterGuess = 1
        while true {
            if chapterNums.contains(Float(nextChapterGuess)) {
                nextChapterGuess += 1
            } else {
                return Float(nextChapterGuess)
            }
        }
    }
}

// MARK: Fetching
extension LocalFileDataManager {
    // fetch list of series with some basic info from db
    func fetchLocalSeriesInfo(query: String? = nil) -> [LocalSeriesInfo] {
        let request = MangaObject.fetchRequest()
        request.predicate = if let query, !query.isEmpty {
            NSPredicate(format: "fileInfo != nil AND title CONTAINS[cd] %@", query)
        } else {
            NSPredicate(format: "fileInfo != nil")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "fileInfo.dateCreated", ascending: false)]
        do {
            let results = try context.fetch(request)
            return results.map {
                LocalSeriesInfo(
                    coverUrl: $0.cover ?? "",
                    name: $0.title,
                    chapterCount: $0.chapters?.count ?? 0
                )
            }
        } catch {
            LogManager.logger.error("Failed to fetch local manga: \(error)")
            return []
        }
    }

    // fetch all series from db that have associated local file information
    func fetchLocalSeries(query: String? = nil) -> [AidokuRunner.Manga] {
        let request = MangaObject.fetchRequest()
        request.predicate = if let query, !query.isEmpty {
            NSPredicate(format: "fileInfo != nil AND title CONTAINS[cd] %@", query)
        } else {
            NSPredicate(format: "fileInfo != nil")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "fileInfo.dateCreated", ascending: false)]
        do {
            let results = try context.fetch(request)
            return results.map { $0.toNewManga() }
        } catch {
            LogManager.logger.error("Failed to fetch local manga: \(error)")
            return []
        }
    }

    // fetch a series from db with specified id
    func fetchLocalSeries(id: String) -> AidokuRunner.Manga? {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND sourceId == %@", id, LocalSourceRunner.sourceKey)
        request.fetchLimit = 1
        do {
            let results = try context.fetch(request)
            return results.first?.toNewManga()
        } catch {
            LogManager.logger.error("Failed to fetch local manga: \(error)")
            return nil
        }
    }

    // fetch local chapters for a series from db
    func fetchChapters(mangaId: String) -> [AidokuRunner.Chapter] {
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(format: "mangaId == %@ AND sourceId == %@", mangaId, LocalSourceRunner.sourceKey)
        request.sortDescriptors = [NSSortDescriptor(key: "sourceOrder", ascending: true)]
        do {
            let results = try context.fetch(request)
            return results.map { $0.toNewChapter() }
        } catch {
            LogManager.logger.error("Failed to fetch local manga chapters: \(error)")
            return []
        }
    }

    // get the path to the zip archive for a chapter
    func fetchChapterArchivePath(mangaId: String, chapterId: String) -> String? {
        let chapterRequest = ChapterObject.fetchRequest()
        chapterRequest.predicate = NSPredicate(
            format: "mangaId == %@ AND id == %@ AND sourceId == %@",
            mangaId,
            chapterId,
            LocalSourceRunner.sourceKey
        )
        chapterRequest.fetchLimit = 1
        guard
            let chapter = (try? self.context.fetch(chapterRequest))?.first,
            let fileInfo = chapter.fileInfo,
            let cbzPath = fileInfo.path
        else {
            return nil
        }
        return cbzPath
    }
}

// MARK: Removing
extension LocalFileDataManager {
    // remove a manga object (and all associated chapters) from the db
    func removeManga(with mangaId: String) -> String? {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND sourceId == %@",
            mangaId,
            LocalSourceRunner.sourceKey
        )
        request.fetchLimit = 1
        guard let mangaObject = (try? self.context.fetch(request))?.first else {
            return nil // nothing to remove
        }

        guard mangaObject.libraryObject == nil else {
            // if the manga is in the library, we can't remove it from db (?)
            // todo: we should probably still remove it, just have a warning
            return nil
        }

        // remove associated chapter objects
        if let chapters = mangaObject.chapters as? Set<ChapterObject> {
            for chapter in chapters {
                // remove associated fileInfo
                if let fileInfo = chapter.fileInfo {
                    context.delete(fileInfo)
                }
                context.delete(chapter)
            }
        }

        let mangaPath = mangaObject.fileInfo?.path

        // remove file info
        if let fileInfo = mangaObject.fileInfo {
            context.delete(fileInfo)
        }

        // remove manga object
        context.delete(mangaObject)

        try? context.save()

        return mangaPath
    }

    // remove a chapter object from the db
    func removeChapter(mangaId: String, chapterId: String) -> String? {
        let request = ChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND mangaId == %@ AND sourceId == %@",
            chapterId,
            mangaId,
            LocalSourceRunner.sourceKey
        )
        request.fetchLimit = 1
        guard let object = (try? self.context.fetch(request))?.first else {
            return nil // nothing to remove
        }

        let filePath = object.fileInfo?.path

        // remove file info
        if let fileInfo = object.fileInfo {
            context.delete(fileInfo)
        }

        // remove chapter object
        context.delete(object)

        try? context.save()

        return filePath
    }

    // removes unavailable chapters for a manga and returns a list of file names of chapters remaining in the db
    func removeMissingChapters(
        mangaId: String,
        availableChapters: Set<String>
    ) -> Set<String> {
        // fetch db chapters for the manga
        let dbChapters: [ChapterObject] = {
            let request = ChapterObject.fetchRequest()
            request.predicate = NSPredicate(
                format: "mangaId == %@ AND sourceId == %@",
                mangaId,
                LocalSourceRunner.sourceKey
            )
            return (try? self.context.fetch(request)) ?? []
        }()

        // remove chapters from db that no longer exist on disk
        let chaptersToRemove = dbChapters.filter { chapter in
            guard let path = chapter.fileInfo?.path else { return false }
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            return !availableChapters.contains(fileName)
        }
        for chapter in chaptersToRemove {
            self.context.delete(chapter)
        }

        try? self.context.save()

        // get db chapters file names
        let dbChapterFileNames: Set<String> = Set(dbChapters.compactMap { chapter in
            guard !chaptersToRemove.contains(chapter) else { return nil }
            guard let path = chapter.fileInfo?.path else { return nil }
            return URL(fileURLWithPath: path).lastPathComponent
        })

        return dbChapterFileNames
    }
}

// MARK: Creating
extension LocalFileDataManager {
    func createManga(
        url: URL,
        id: String,
        title: String,
        cover: String? = nil,
        description: String? = nil
    ) {
        let fileInfo = LocalFileInfoObject(context: context)
        fileInfo.path = removeDocumentsDirPrefix(from: url)
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        fileInfo.dateCreated = values?.creationDate
        fileInfo.dateModified = values?.contentModificationDate

        let object = MangaObject(context: context)
        object.id = id
        object.sourceId = LocalSourceRunner.sourceKey
        object.title = title
        object.cover = cover
        object.desc = description
        object.fileInfo = fileInfo

        try? context.save()
    }

    func createChapter(
        mangaId: String,
        url: URL,
        id: String,
        title: String? = nil,
        volume: Float? = nil,
        chapter: Float? = nil
    ) {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "fileInfo != nil AND id == %@", mangaId)
        request.fetchLimit = 1
        guard let mangaObject = (try? context.fetch(request))?.first else { return }

        // create chapter in db
        let fileInfo = LocalFileInfoObject(context: self.context)
        fileInfo.path = removeDocumentsDirPrefix(from: url)
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        fileInfo.dateCreated = values?.creationDate
        fileInfo.dateModified = values?.contentModificationDate

        let chapterObject = ChapterObject(context: self.context)
        chapterObject.id = id
        chapterObject.mangaId = mangaId
        chapterObject.sourceId = LocalSourceRunner.sourceKey
        chapterObject.title = title
        chapterObject.volume = volume.map { NSNumber(value: $0) }
        chapterObject.chapter = chapter.map { NSNumber(value: $0) }
        chapterObject.manga = mangaObject
        chapterObject.dateUploaded = values?.contentModificationDate
        chapterObject.fileInfo = fileInfo
        // add to the top of the chapter list
        chapterObject.sourceOrder = -Int16((mangaObject.chapters?.count ?? 0) + 1)

        mangaObject.addToChapters(chapterObject)

        try? context.save()
    }
}

// MARK: Miscellaneous
extension LocalFileDataManager {
    // finds manga in db but not on disk and manga on disk but not in db, and fix broken manga covers
    func findMangaDiskChanges(mangaFolders: [URL]) -> (toRemove: Set<String>, toAdd: Set<String>) {
        let folderMangaIds = Set(mangaFolders.map { $0.lastPathComponent })

        // fetch all local manga objects from db
        let coreDataManga: [MangaObject] = {
            let request = MangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "sourceId == %@", LocalSourceRunner.sourceKey)
            return (try? self.context.fetch(request)) ?? []
        }()
        let dbMangaIds = Set(coreDataManga.map { $0.id })
        let toRemove = dbMangaIds.subtracting(folderMangaIds)

        // find manga with invalid covers
        let toFixCovers = coreDataManga
            .filter {
                // if we're removing it anyways, skip it
                guard !toRemove.contains($0.id) else { return false }
                // check if cover url is nil or doesn't exist on disk
                guard let coverUrl = $0.cover, let url = URL(string: coverUrl) else { return true }
                return !url.exists
            }
        for manga in toFixCovers {
            // try to find a cover image in the manga folder
            for ext in LocalFileManager.allowedImageExtensions {
                let coverPath = mangaFolders.first(where: { $0.lastPathComponent == manga.id })?
                    .appendingPathComponent("cover.\(ext)")
                if let coverPath, coverPath.exists {
                    manga.cover = coverPath.absoluteString
                    break
                }
            }
        }

        return (
            // manga that no longer exist on disk
            toRemove,
            // manga that exist on disk but not in db
            folderMangaIds.subtracting(dbMangaIds),
        )
    }
}

// MARK: Helpers
extension LocalFileDataManager {
    private func removeDocumentsDirPrefix(from url: URL) -> String {
        let documentsDirPath = FileManager.default.documentDirectory.path + "/"
        let path = url.path.replacingOccurrences(of: documentsDirPath, with: "")
        let privatePrefix = "/private"
        if path.hasPrefix(privatePrefix) {
            return String(path.dropFirst(privatePrefix.count))
        }
        return path
    }
}
