//
//  CoreDataManager+Indexes.swift
//  Aidoku
//
//  Created by Amqx on 8/7/26.
//

import CoreData
import SQLite3

extension CoreDataManager {

    /// Bumped whenever ``fetchIndexStatements`` changes, so that existing stores pick up the
    /// new indexes on the next launch.
    private static let fetchIndexVersion = 1
    private static let fetchIndexVersionKey = "Flag.fetchIndexVersion"

    /// The fetch indexes declared on the data model, as raw SQL.
    ///
    /// The names and column lists match exactly what Core Data generates for the corresponding
    /// `fetchIndex` entries in the model, so these statements do nothing on a store that already
    /// has them. These must be kept in sync, otherwise a new index won't reach an existing store.
    private static let fetchIndexStatements = [
        """
        CREATE INDEX IF NOT EXISTS Z_Chapter_byChapterIdentity
        ON ZCHAPTER (ZSOURCEID COLLATE BINARY ASC, ZMANGAID COLLATE BINARY ASC, ZID COLLATE BINARY ASC)
        """,
        """
        CREATE INDEX IF NOT EXISTS Z_History_byDateRead
        ON ZHISTORY (ZDATEREAD COLLATE BINARY ASC)
        """,
        """
        CREATE INDEX IF NOT EXISTS Z_History_byChapterIdentity
        ON ZHISTORY (ZSOURCEID COLLATE BINARY ASC, ZMANGAID COLLATE BINARY ASC, ZCHAPTERID COLLATE BINARY ASC)
        """,
        """
        CREATE INDEX IF NOT EXISTS Z_Manga_byMangaIdentity
        ON ZMANGA (ZSOURCEID COLLATE BINARY ASC, ZID COLLATE BINARY ASC)
        """
    ]

    /// Creates the data model's fetch indexes on an already-existing store.
    ///
    /// Fetch indexes are only applied when Core Data creates a store's schema. Adding one doesn't
    /// change the model's version hash, so an existing store is considered up to date and never
    /// migrates. Creating them directly covers everyone else.
    ///
    /// Must be called before the store is loaded, so that nothing else holds a connection to it.
    static func createFetchIndexes(at url: URL) {
        guard UserDefaults.standard.integer(forKey: fetchIndexVersionKey) < fetchIndexVersion else { return }

        // without a store, core data is about to create one with the indexes already applied
        guard FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.set(fetchIndexVersion, forKey: fetchIndexVersionKey)
            return
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            // e.g. launched in the background before the device has been unlocked since boot, where
            // file protection keeps the store unreadable
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            LogManager.logger.error("CoreDataManager.createFetchIndexes: unable to open store (\(message))")
            sqlite3_close(database)
            return
        }
        defer { sqlite3_close(database) }

        var succeeded = execute("BEGIN TRANSACTION", on: database)
        for statement in fetchIndexStatements {
            succeeded = execute(statement, on: database) && succeeded
        }
        succeeded = execute("COMMIT", on: database) && succeeded

        // if something went wrong, leave the flag alone so it's retried on the next launch
        if succeeded {
            UserDefaults.standard.set(fetchIndexVersion, forKey: fetchIndexVersionKey)
        }
    }

    private static func execute(_ statement: String, on database: OpaquePointer?) -> Bool {
        var message: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(message) }
        guard sqlite3_exec(database, statement, nil, nil, &message) != SQLITE_OK else { return true }
        let description = message.map { String(cString: $0) } ?? "unknown error"
        LogManager.logger.error("CoreDataManager.createFetchIndexes: \(description)")
        return false
    }
}
