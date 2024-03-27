//
//  BackupManager.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import Foundation

class BackupManager {

    static let shared = BackupManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Backups", isDirectory: true)

    static var backupUrls: [URL] {
        Self.directory.contentsByDateModified
    }

    static var backups: [Backup] {
        Self.backupUrls.compactMap { Backup.load(from: $0) }
    }

    func save(backup: Backup, url: URL? = nil) {
        Self.directory.createDirectory()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let plist = try? encoder.encode(backup) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            if let url = url {
                try? plist.write(to: url)
            } else {
                let path = Self.directory.appendingPathComponent("aidoku_\(dateFormatter.string(from: backup.date)).aib")
                try? plist.write(to: path)
            }
            NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
        }
    }

    func saveNewBackup() {
        Task {
            save(backup: await createBackup())
        }
    }

    func importBackup(from url: URL) -> Bool {
        Self.directory.createDirectory()
        var targetLocation = Self.directory.appendingPathComponent(url.lastPathComponent)
        while targetLocation.exists {
            targetLocation = targetLocation.deletingLastPathComponent().appendingPathComponent(
                targetLocation.deletingPathExtension().lastPathComponent.appending("_1")
            ).appendingPathExtension(url.pathExtension)
        }
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try FileManager.default.copyItem(at: url, to: targetLocation)
            try? FileManager.default.removeItem(at: url)
            NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
            return true
        } catch {
            return false
        }
    }

    func createBackup() async -> Backup {
        // no
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let library = CoreDataManager.shared.getLibraryManga(context: context).map {
                BackupLibraryManga(libraryObject: $0)
            }
            let history = CoreDataManager.shared.getHistory(context: context).map {
                BackupHistory(historyObject: $0)
            }
            let manga = CoreDataManager.shared.getManga(context: context).map {
                BackupManga(mangaObject: $0)
            }
            let chapters = CoreDataManager.shared.getChapters(context: context).map {
                BackupChapter(chapterObject: $0)
            }
            let trackItems = CoreDataManager.shared.getTracks(context: context).compactMap {
                BackupTrackItem(trackObject: $0)
            }
            let categories = CoreDataManager.shared.getCategoryTitles(context: context)
            let sources = CoreDataManager.shared.getSources(context: context).compactMap {
                $0.id
            }

            return Backup(
                library: library,
                history: history,
                manga: manga,
                chapters: chapters,
                trackItems: trackItems,
                categories: categories,
                sources: sources,
                date: Date(),
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            )
        }
    }

    func renameBackup(url: URL, name: String?) {
        guard var backup = Backup.load(from: url) else { return }
        backup.name = name?.isEmpty ?? true ? nil : name
        save(backup: backup, url: url)
    }

    func removeBackup(url: URL) {
        try? FileManager.default.removeItem(at: url)
        NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
    }

    enum BackupError: Error {
        case manga
        case categories
        case library
        case history
        case chapters
        case track

        var stringValue: String {
            switch self {
            case .manga: NSLocalizedString("MANGA", comment: "")
            case .categories: NSLocalizedString("CATEGORIES", comment: "")
            case .library: NSLocalizedString("LIBRARY", comment: "")
            case .history: NSLocalizedString("HISTORY", comment: "")
            case .chapters: NSLocalizedString("CHAPTERS", comment: "")
            case .track: NSLocalizedString("TRACKERS", comment: "")
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func restore(from backup: Backup) async throws {
        let mangaTask = Task {
            if let backupManga = backup.manga {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearManga(context: context)
                    for item in backupManga {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.manga
                }
            }
        }
        let categoriesTask = Task {
            if let backupCategories = backup.categories {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearCategories(context: context)
                    for category in backupCategories {
                        CoreDataManager.shared.createCategory(title: category, context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.categories
                }
            }
        }
        let libraryTask = Task {
            try await mangaTask.value
            try await categoriesTask.value
            if let backupLibrary = backup.library {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    let manga = CoreDataManager.shared.getManga(context: context)
                    for libraryBackupItem in backupLibrary {
                        let libraryObject = libraryBackupItem.toObject(context: context)
                        if let manga = manga.first(where: {
                            $0.id == libraryBackupItem.mangaId && $0.sourceId == libraryBackupItem.sourceId
                        }) {
                            libraryObject.manga = manga
                            if !libraryBackupItem.categories.isEmpty {
                                CoreDataManager.shared.addCategoriesToManga(
                                    sourceId: libraryBackupItem.sourceId,
                                    mangaId: libraryBackupItem.mangaId,
                                    categories: libraryBackupItem.categories,
                                    context: context
                                )
                            }
                        }
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.library
                }
            }
        }
        let historyTask = Task {
            if let backupHistory = backup.history {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearHistory(context: context)
                    for item in backupHistory {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.history
                }
            }
        }
        let chaptersTask = Task {
            try await historyTask.value // need to link chapters with history
            try await libraryTask.value // need to make sure manga objects aren't being modified
            if let backupChapters = backup.chapters {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearChapters(context: context)
                    let manga = CoreDataManager.shared.getManga(context: context)
                    let history = CoreDataManager.shared.getHistory(context: context)
                    for backupChapter in backupChapters {
                        let chapter = backupChapter.toObject(context: context)
                        chapter.manga = manga.first {
                            $0.id == backupChapter.mangaId && $0.sourceId == backupChapter.sourceId
                        }
                        chapter.history = history.first {
                            $0.chapterId == backupChapter.id
                                && $0.mangaId == backupChapter.mangaId
                                && $0.sourceId == backupChapter.sourceId
                        }
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.chapters
                }
            }
        }
        let trackTask = Task {
            if let backupTrackItems = backup.trackItems {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearTracks(context: context)
                    for item in backupTrackItems {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.track
                }
            }
        }

        // wait for db changes to finish
        try await chaptersTask.value
        try await trackTask.value

        NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("updateTrackers"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("updateCategories"), object: nil)

        await MangaManager.shared.refreshLibrary(forceAll: true)

        NotificationCenter.default.post(name: NSNotification.Name("updateLibrary"), object: nil)
    }
}
