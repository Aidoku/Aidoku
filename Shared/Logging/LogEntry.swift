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

    func formatted() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd HH:mm:ss.SSS"
        return "[\(dateFormatter.string(from: date))] \(type != .default ? "[\(type.toString())] " : "")\(message)"
    }
}
