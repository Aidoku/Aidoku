//
//  Backup.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import Foundation

struct Backup: Codable {
    var library: [BackupLibraryManga]
    var history: [BackupHistory]
    var manga: [BackupManga]
    var chapters: [BackupChapter]
    var date: Date
    var version: String

    static func load(from url: URL) -> Backup? {
        guard let json = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Backup.self, from: json)
    }
}
