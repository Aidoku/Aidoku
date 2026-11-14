//
//  LogEntry.swift
//  Aidoku
//
//  Created by Skitty on 11/17/25.
//

import Foundation

struct LogEntry {
    let date: Date
    let type: LogType
    let message: String

    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd HH:mm:ss.SSS"
        return dateFormatter
    }()

    func formatted() -> String {
        "[\(Self.dateFormatter.string(from: date))] \(type != .default ? "[\(type.toString())] " : "")\(message)"
    }
}
