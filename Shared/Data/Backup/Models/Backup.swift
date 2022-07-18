//
//  Backup.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import Foundation

struct Backup: Codable {
    var library: [BackupLibraryManga]?
    var history: [BackupHistory]?
    var manga: [BackupManga]?
    var chapters: [BackupChapter]?
    var categories: [String]?
    var sources: [String]?
    var date: Date
    var name: String?
    var version: String?

    static func load(from url: URL) -> Backup? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .secondsSince1970

        if let backup = try? PropertyListDecoder().decode(Backup.self, from: data) {
            return backup
        } else {
            return try? jsonDecoder.decode(Backup.self, from: data)
        }
    }
}
