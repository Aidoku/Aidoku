//
//  Backup.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import Foundation

struct Backup: Codable, Hashable, Identifiable {
    var id: Int { hashValue }

    var library: [BackupLibraryManga]?
    var history: [BackupHistory]?
    var manga: [BackupManga]?
    var chapters: [BackupChapter]?
    var trackItems: [BackupTrackItem]?
    var categories: [String]?
    var sources: [String]?
    var sourceLists: [String]?
    var settings: [String: JsonAnyValue]?
    var date: Date
    var name: String?
    var version: String?

    static func load(from url: URL) -> Backup? {
        guard let json = try? Data(contentsOf: url) else { return nil }

        if let backup = try? PropertyListDecoder().decode(Backup.self, from: json) {
            return backup
        } else {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try? decoder.decode(Backup.self, from: json)
        }
    }
}
