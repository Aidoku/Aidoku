//
//  LogStore.swift
//  Aidoku
//
//  Created by Skitty on 5/24/22.
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

class LogStore {

    var entries: [LogEntry] = []

    var observers: [UUID: (LogEntry) -> Void] = [:]

    func addEntry(level: LogType, message: String) {
        let entry = LogEntry(date: Date(), type: level, message: message)
        entries.append(entry)
        for observer in observers {
            observer.value(entry)
        }
    }

    func clear() {
        entries = []
    }

    func export(to fileUrl: URL) {
        let string = entries
            .map { $0.formatted() }
            .joined(separator: "\n")
        do {
            try string.write(to: fileUrl, atomically: true, encoding: .utf8)
        } catch {
            LogManager.logger.error("Failed to export log store \(error.localizedDescription)")
        }
    }

    @discardableResult
    func addObserver(_ block: @escaping (LogEntry) -> Void) -> UUID {
        let id = UUID()
        observers[id] = block
        return id
    }

    func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }
}
