//
//  LogManager.swift
//  Aidoku
//
//  Created by Skitty on 5/24/22.
//

import Foundation

class LogManager {

    static let logger = Logger(streamUrl: URL(string: UserDefaults.standard.string(forKey: "Logs.logServer") ?? ""))

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Logs", isDirectory: true)

    static func export(to fileUrl: URL? = nil) -> URL {
        Self.directory.createDirectory()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = fileUrl ?? Self.directory.appendingPathComponent("log_\(dateFormatter.string(from: Date())).txt")
        Self.logger.store.export(to: url)
        return url
    }
}

func log(_ items: Any...) {
    LogManager.logger.log(items.map { String(describing: $0) }.joined(separator: " "))
}
