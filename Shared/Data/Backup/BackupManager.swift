//
//  BackupManager.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import BackgroundTasks
import Foundation

#if canImport(UIKit)
import UIKit
#endif

actor BackupManager {
    static let shared = BackupManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Backups", isDirectory: true)

    static var backupUrls: [URL] {
        Self.directory.contentsByDateModified
    }

    private static let backupTaskIdentifier = (Bundle.main.bundleIdentifier ?? "") + ".backup"
    private static let maxAutoBackups = 4

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

    func saveNewBackup(options: BackupOptions) async {
        save(backup: await createBackup(options: options))
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
            NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
            return true
        } catch {
            return false
        }
    }

    struct BackupOptions {
        var automatic: Bool = false
        let libraryEntries: Bool
        let history: Bool
        let chapters: Bool
        let tracking: Bool
        let readingSessions: Bool
        let updates: Bool
        let categories: Bool
        let settings: Bool
        let sourceLists: Bool
        let sensitiveSettings: Bool
    }

    func createBackup(options: BackupOptions) async -> Backup {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let library: [BackupLibraryManga] = if options.libraryEntries {
                CoreDataManager.shared.getLibraryManga(context: context).map {
                    BackupLibraryManga(libraryObject: $0, skipCategories: !options.categories)
                }
            } else {
                []
            }
            let history: [BackupHistory] = if options.history {
                CoreDataManager.shared.getHistory(context: context).map {
                    BackupHistory(historyObject: $0)
                }
            } else {
                []
            }
            let manga: [BackupManga] = if options.libraryEntries {
                CoreDataManager.shared.getManga(context: context).map {
                    BackupManga(mangaObject: $0)
                }
            } else {
                []
            }
            let chapters: [BackupChapter] = if options.chapters {
                CoreDataManager.shared.getChapters(context: context).map {
                    BackupChapter(chapterObject: $0)
                }
            } else {
                []
            }
            let trackItems: [BackupTrackItem] = if options.tracking {
                CoreDataManager.shared.getTracks(context: context).compactMap {
                    BackupTrackItem(trackObject: $0)
                }
            } else {
                []
            }
            let sessionItems: [BackupReadingSession] = if options.readingSessions {
                CoreDataManager.shared.getSessions(context: context).compactMap(BackupReadingSession.init)
            } else {
                []
            }
            let updateItems: [BackupUpdate] = if options.updates {
                CoreDataManager.shared.getUpdates(context: context).compactMap(BackupUpdate.init)
            } else {
                []
            }
            let categories: [String] = if options.categories {
                CoreDataManager.shared.getCategoryTitles(context: context)
            } else {
                []
            }
            let sources = CoreDataManager.shared.getSources(context: context).compactMap {
                $0.id
            }
            let sourceLists = options.sourceLists ? SourceManager.shared.sourceListsStrings : []

            let settings: [String: JsonAnyValue]? = if options.settings {
                self.exportSettings(includeSensitive: options.sensitiveSettings)
            } else {
                nil
            }

            return Backup(
                library: library,
                history: history,
                manga: manga,
                chapters: chapters,
                trackItems: trackItems,
                readingSessions: sessionItems,
                updates: updateItems,
                categories: categories,
                sources: sources,
                sourceLists: sourceLists,
                settings: settings,
                date: Date.now,
                automatic: options.automatic,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            )
        }
    }

    private func exportSettings(includeSensitive: Bool) -> [String: JsonAnyValue] {
        var allSettings = UserDefaults.standard.dictionaryRepresentation()

        // filter out potentially sensitive info
        if !includeSensitive {
            let sensitiveKeywords = ["login", "password", "token", "auth", "cookie"]
            for key in allSettings.keys where sensitiveKeywords.contains(where: key.lowercased().contains) {
                allSettings.removeValue(forKey: key)
            }
        }

        var convertedSettings: [String: JsonAnyValue] = [:]

        // convert to export compatible types
        for (key, value) in allSettings {
            if key == "Browse.sourceLists" {
                continue // skip source lists, as these are stored separately
            }
            if let value = value as? String {
                convertedSettings[key] = .string(value)
            } else if let value = value as? Int {
                convertedSettings[key] = .int(value)
            } else if let value = value as? Double {
                convertedSettings[key] = .double(value)
            } else if let value = value as? Bool {
                convertedSettings[key] = .bool(value)
            } else if let value = value as? [String] {
                convertedSettings[key] = .array(value)
            }
        }

        return convertedSettings
    }

    func renameBackup(url: URL, name: String?) {
        guard var backup = Backup.load(from: url) else { return }
        backup.name = name?.isEmpty ?? true ? nil : name
        save(backup: backup, url: url)
    }

    func removeBackup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    enum BackupError: Error {
        case manga
        case categories
        case library
        case history
        case chapters
        case sessions
        case updates
        case track

        var stringValue: String {
            switch self {
                case .manga: NSLocalizedString("CONTENT")
                case .categories: NSLocalizedString("CATEGORIES")
                case .library: NSLocalizedString("LIBRARY")
                case .history: NSLocalizedString("HISTORY")
                case .chapters: NSLocalizedString("CHAPTERS")
                case .sessions: NSLocalizedString("READING_SESSIONS")
                case .updates: NSLocalizedString("UPDATES")
                case .track: NSLocalizedString("TRACKERS")
            }
        }
    }

    func restore(from backup: Backup) async {
        await doRestore(from: backup)
    }

    @discardableResult
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func doRestore(from backup: Backup) async -> Bool {
#if !os(macOS)
        await MainActor.run {
            (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
            UIApplication.shared.isIdleTimerDisabled = true
        }
#endif

        Task {
            // restore settings
            if let settings = backup.settings {
                for (key, value) in settings {
                    UserDefaults.standard.set(value.toRaw(), forKey: key)
                }
            }

            // restore source lists
            SourceManager.shared.clearSourceLists()
            guard let sourceLists = backup.sourceLists else { return }
            for sourceList in sourceLists {
                guard let sourceListURL = URL(string: sourceList) else { continue }
                _ = await SourceManager.shared.addSourceList(url: sourceListURL)
            }
        }

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
                            if let categories = libraryBackupItem.categories, !categories.isEmpty {
                                CoreDataManager.shared.addCategoriesToManga(
                                    sourceId: libraryBackupItem.sourceId,
                                    mangaId: libraryBackupItem.mangaId,
                                    categories: categories,
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
        let updatesTask = Task {
            try await chaptersTask.value // need to link updates with
            if let backupUpdates = backup.updates {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearUpdates(context: context)
                    let chapters = CoreDataManager.shared.getChapters(context: context)
                    for backupUpdate in backupUpdates {
                        let update = backupUpdate.toObject(context: context)
                        update.chapter = chapters.first {
                            $0.id == backupUpdate.chapterId
                                && $0.mangaId == backupUpdate.mangaId
                                && $0.sourceId == backupUpdate.sourceId
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
                    throw BackupError.updates
                }
            }
        }
        let sessionsTask = Task {
            try await historyTask.value // need to link sessions with history
            if let backupSessions = backup.readingSessions {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearSessions(context: context)
                    let history = CoreDataManager.shared.getHistory(context: context)
                    for backupSession in backupSessions {
                        // ensure data is valid
                        guard backupSession.endDate > backupSession.startDate && backupSession.pagesRead > 0 else {
                            continue
                        }
                        let session = backupSession.toObject(context: context)
                        session.history = history.first {
                            $0.chapterId == backupSession.chapterId
                                && $0.mangaId == backupSession.mangaId
                                && $0.sourceId == backupSession.sourceId
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
                    throw BackupError.updates
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

        var backupError: Error?

        // wait for db changes to finish
        do {
            try await updatesTask.value
            try await sessionsTask.value
            try await trackTask.value
        } catch {
            backupError = error
        }

        NotificationCenter.default.post(name: .updateHistory, object: nil)
        NotificationCenter.default.post(name: .updateTrackers, object: nil)
        NotificationCenter.default.post(name: .updateCategories, object: nil)
        NotificationCenter.default.post(name: .updateLibrary, object: nil)

#if !os(macOS)
        let delegate = await UIApplication.shared.delegate as? AppDelegate
        await delegate?.hideLoadingIndicator()

        await MainActor.run { [backupError] in
            UIApplication.shared.isIdleTimerDisabled = false

            if let backupError {
                Task {
                    // show error alert
                    delegate?.presentAlert(
                        title: NSLocalizedString("BACKUP_ERROR"),
                        message: String(
                            format: NSLocalizedString("BACKUP_ERROR_TEXT"),
                            (backupError as? BackupError)?.stringValue ?? NSLocalizedString("UNKNOWN")
                        )
                    )
                }
            } else {
                // show missing sources alert if there are any
                let missingSources = (backup.sources ?? []).filter {
                    !CoreDataManager.shared.hasSource(id: $0)
                }
                if !missingSources.isEmpty {
                    delegate?.presentAlert(
                        title: NSLocalizedString("MISSING_SOURCES"),
                        message: NSLocalizedString("MISSING_SOURCES_TEXT") + missingSources.map { "\n- \($0)" }.joined()
                    )
                }
            }
        }
#endif

        return backupError == nil
    }
}

extension BackupManager {
    nonisolated func register() {
#if !os(macOS) && !targetEnvironment(simulator)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backupTaskIdentifier, using: nil) { @Sendable [weak self] task in
            guard let self, let task = task as? BGProcessingTask else { return }

            Task { @Sendable in
                await self.createAutoBackup()

                task.setTaskCompleted(success: true)
            }
        }
#endif
    }
}

extension BackupManager {
    func scheduleAutoBackup() {
        guard UserDefaults.standard.bool(forKey: "AutomaticBackups.enabled") else {
#if !os(macOS) && !targetEnvironment(simulator)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backupTaskIdentifier)
#endif
            return
        }

        let lastUpdated = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "AutomaticBackups.lastBackup"))
        let interval: Double = switch UserDefaults.standard.string(forKey: "AutomaticBackups.interval") {
            case "6hours": 21600
            case "12hours": 43200
            case "daily": 86400
            case "2days": 172800
            case "weekly": 604800
            default: 0
        }
        let nextUpdateTime = lastUpdated + interval

        if nextUpdateTime < Date.now {
            // interval time has passed, create auto backup now
            Task {
                await createAutoBackup()
            }
        } else {
#if !os(macOS) && !targetEnvironment(simulator)
            // schedule task for the future
            let request = BGProcessingTaskRequest(identifier: Self.backupTaskIdentifier)
            request.earliestBeginDate = nextUpdateTime
            request.requiresExternalPower = false
            request.requiresNetworkConnectivity = false

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                LogManager.logger.error("Could not schedule automatic backup: \(error)")
            }
#endif
        }
    }

    private func createAutoBackup() async {
        guard UserDefaults.standard.bool(forKey: "AutomaticBackups.enabled") else { return }

        let libraryEntries = UserDefaults.standard.bool(forKey: "AutomaticBackups.libraryEntries")
        let history = UserDefaults.standard.bool(forKey: "AutomaticBackups.history")
        let chapters = UserDefaults.standard.bool(forKey: "AutomaticBackups.chapters")
        let tracking = UserDefaults.standard.bool(forKey: "AutomaticBackups.tracking")
        let readingSessions = UserDefaults.standard.bool(forKey: "AutomaticBackups.readingSessions")
        let updates = UserDefaults.standard.bool(forKey: "AutomaticBackups.updates")
        let categories = UserDefaults.standard.bool(forKey: "AutomaticBackups.categories")
        let settings = UserDefaults.standard.bool(forKey: "AutomaticBackups.settings")
        let sourceLists = UserDefaults.standard.bool(forKey: "AutomaticBackups.sourceLists")
        let sensitiveSettings = UserDefaults.standard.bool(forKey: "AutomaticBackups.sensitiveSettings")

        await self.saveNewBackup(
            options: .init(
                automatic: true,
                libraryEntries: libraryEntries,
                history: history,
                chapters: chapters,
                tracking: tracking,
                readingSessions: readingSessions,
                updates: updates,
                categories: categories,
                settings: settings,
                sourceLists: sourceLists,
                sensitiveSettings: sensitiveSettings
            )
        )

        // update last auto backup time
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "AutomaticBackups.lastBackup")

        cleanUpAutoBackups()
        scheduleAutoBackup() // schedule the next one
    }

    // ensure we keep only the latest maxAutoBackups automatic backups
    private func cleanUpAutoBackups() {
        var autoBackups: [(URL, Backup)] = []
        for backupUrl in Self.backupUrls {
            let backup = Backup.load(from: backupUrl)
            if let backup, backup.automatic ?? false {
                autoBackups.append((backupUrl, backup))
            }
        }
        while autoBackups.count > Self.maxAutoBackups {
            let oldestBackup = autoBackups
                .min { $0.1.date < $1.1.date }
            if let oldestBackup {
                removeBackup(url: oldestBackup.0)
                autoBackups.removeAll { $0.0 == oldestBackup.0 }
            } else {
                break
            }
        }
    }
}
