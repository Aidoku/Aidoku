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
        Self.directory.contentsByDateAdded
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
        save(backup: createBackup())
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

    func createBackup() -> Backup {
        let library = (try? DataManager.shared.getLibraryObjects())?.map {
            BackupLibraryManga(libraryObject: $0)
        } ?? []
        let history = (try? DataManager.shared.getReadHistory())?.map {
            BackupHistory(historyObject: $0)
        } ?? []
        let manga = (try? DataManager.shared.getMangaObjects())?.map {
            BackupManga(mangaObject: $0)
        } ?? []
        let chapters = (try? DataManager.shared.getChapterObjects())?.map {
            BackupChapter(chapterObject: $0)
        } ?? []
        let trackItems = (try? DataManager.shared.getTrackObjects())?.compactMap {
            BackupTrackItem(trackObject: $0)
        } ?? []
        let categories = DataManager.shared.getCategories()
        let sources = (try? DataManager.shared.getSourceObjects())?.compactMap {
            $0.id
        } ?? []

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

    func renameBackup(url: URL, name: String?) {
        guard var backup = Backup.load(from: url) else { return }
        backup.name = name?.isEmpty ?? true ? nil : name
        save(backup: backup, url: url)
    }

    func removeBackup(url: URL) {
        try? FileManager.default.removeItem(at: url)
        NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
    }

    func restore(from backup: Backup) async {
        // this should probably do some more checks before running, idk

        if backup.history != nil {
            DataManager.shared.clearHistory()
            backup.history?.forEach {
                _ = $0.toObject(context: DataManager.shared.container.viewContext)
            }
        }

        if backup.manga != nil {
            DataManager.shared.clearManga()
            backup.manga?.forEach {
                _ = $0.toObject(context: DataManager.shared.container.viewContext)
            }
        }

        if backup.categories != nil {
            DataManager.shared.clearCategories()
            backup.categories?.forEach {
                DataManager.shared.addCategory(title: $0)
            }
        }

        if backup.library != nil {
            DataManager.shared.clearLibrary()
            backup.library?.forEach {
                let libraryObject = $0.toObject(context: DataManager.shared.container.viewContext)
                if let manga = DataManager.shared.getMangaObject(withId: $0.mangaId, sourceId: $0.sourceId) {
                    libraryObject.manga = manga
                    if !$0.categories.isEmpty {
                        DataManager.shared.addMangaToCategories(manga: Manga(sourceId: $0.sourceId, id: $0.mangaId), categories: $0.categories)
                    }
                }
            }
        }

        if backup.chapters != nil {
            DataManager.shared.clearChapters()
            backup.chapters?.forEach {
                let chapter = $0.toObject(context: DataManager.shared.container.viewContext)
                chapter.manga = DataManager.shared.getMangaObject(withId: $0.mangaId, sourceId: $0.sourceId)
                chapter.history = DataManager.shared.getHistoryObject(
                    for: chapter.toChapter()
                )
            }
        }

        if backup.trackItems != nil {
            DataManager.shared.clearTrackItems()
            backup.trackItems?.forEach {
                _ = $0.toObject(context: DataManager.shared.container.viewContext)
            }
        }

        DataManager.shared.save()

        DataManager.shared.loadLibrary(checkUpdate: false)

        NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("updateTrackers"), object: nil)

        await DataManager.shared.updateLibrary(forceAll: true)
    }
}
