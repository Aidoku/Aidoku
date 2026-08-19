//
//  BackupInfo.swift
//  Aidoku
//
//  Created by Amqx on 8/14/26.
//

import Foundation

/// The summary of a backup shown in the backups list and info sheet.
///
/// The goal is not to load the full backup contents for binary plist formatted backups.
struct BackupInfo: Hashable, Identifiable, Sendable {
    var id: URL { url }

    struct Counts: Hashable, Sendable {
        var library = 0
        var history = 0
        var manga = 0
        var chapters = 0
        var trackItems = 0
        var readingSessions = 0
        var vocabulary = 0
        var updates = 0
        var categories = 0
        var sources = 0
        var sourceLists = 0
        var settings = 0
    }

    let url: URL
    var name: String?
    var date: Date
    var automatic: Bool
    var version: String?
    /// The size of the backup file on disk, in bytes.
    var size: Int64?
    var counts: Counts

    static func load(from url: URL) -> BackupInfo? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        if let info = loadFromBinaryPlist(url: url, size: size) {
            return info
        }
        // xml/ json don't have any way to get counts like plist, so resort to full decode
        guard let backup = Backup.load(from: url) else { return nil }
        return BackupInfo(url: url, size: size, backup: backup)
    }

    init(url: URL, size: Int64?, backup: Backup) {
        self.url = url
        self.name = backup.name
        self.date = backup.date
        self.automatic = backup.automatic ?? false
        self.version = backup.version
        self.size = size
        self.counts = Counts(
            library: backup.library?.count ?? 0,
            history: backup.history?.count ?? 0,
            manga: backup.manga?.count ?? 0,
            chapters: backup.chapters?.count ?? 0,
            trackItems: backup.trackItems?.count ?? 0,
            readingSessions: backup.readingSessions?.count ?? 0,
            vocabulary: backup.vocabulary?.count ?? 0,
            updates: backup.updates?.count ?? 0,
            categories: backup.categories?.count ?? 0,
            sources: backup.sources?.count ?? 0,
            sourceLists: backup.sourceLists?.count ?? 0,
            settings: backup.settings?.count ?? 0
        )
    }

    private init(url: URL, name: String?, date: Date, automatic: Bool, version: String?, size: Int64?, counts: Counts) {
        self.url = url
        self.name = name
        self.date = date
        self.automatic = automatic
        self.version = version
        self.size = size
        self.counts = counts
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func loadFromBinaryPlist(url: URL, size: Int64?) -> BackupInfo? {
        guard
            // mapped so that the pages holding the backup items themselves are never faulted in
            let data = try? Data(contentsOf: url, options: .mappedIfSafe),
            let scanner = BinaryPlistScanner(data: data),
            let entries = scanner.dictionary(for: scanner.rootRef)
        else {
            return nil
        }

        var name: String?
        var date: Date?
        var automatic = false
        var version: String?
        var counts = Counts()

        for (key, ref) in entries {
            // a top-level value that can't be read means the file is malformed, so report it as unreadable
            // rather than displaying a partial or nonsensical summary
            guard let value = scanner.value(for: ref) else { return nil }
            switch key {
                case "name": if case let .string(value) = value { name = value }
                case "date": if case let .date(value) = value { date = value }
                case "automatic": if case let .bool(value) = value { automatic = value }
                case "version": if case let .string(value) = value { version = value }
                case "library": if case let .container(count) = value { counts.library = count }
                case "history": if case let .container(count) = value { counts.history = count }
                case "manga": if case let .container(count) = value { counts.manga = count }
                case "chapters": if case let .container(count) = value { counts.chapters = count }
                case "trackItems": if case let .container(count) = value { counts.trackItems = count }
                case "readingSessions": if case let .container(count) = value { counts.readingSessions = count }
                case "vocabulary": if case let .container(count) = value { counts.vocabulary = count }
                case "updates": if case let .container(count) = value { counts.updates = count }
                case "categories": if case let .container(count) = value { counts.categories = count }
                case "sources": if case let .container(count) = value { counts.sources = count }
                case "sourceLists": if case let .container(count) = value { counts.sourceLists = count }
                case "settings": if case let .container(count) = value { counts.settings = count }
                default: continue
            }
        }

        // the date is the only required key, so treat a backup without one as unreadable
        guard let date else { return nil }

        return BackupInfo(
            url: url,
            name: name,
            date: date,
            automatic: automatic,
            version: version,
            size: size,
            counts: counts
        )
    }
}
