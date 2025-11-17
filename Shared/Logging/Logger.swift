//
//  Logger.swift
//  Aidoku
//
//  Created by Skitty on 5/24/22.
//

import Foundation

final class Logger: Sendable {
    let store: LogStore
    let printLogs: Bool

    init(store: LogStore = LogStore(), printLogs: Bool = true, streamUrl: URL? = nil) {
        self.store = store
        self.printLogs = printLogs
        Task {
            await store.setStreamUrl(streamUrl)
        }
    }

    func log(level: LogType = .default, _ message: String) {
        if printLogs {
            let prefix = level != .default ? "[\(level.toString())] " : ""
            print("\(prefix)\(message)")
        }
        Task {
            await store.addEntry(level: level, message: message)
        }
    }

    func debug(_ message: String) {
        log(level: .debug, message)
    }

    func info(_ message: String) {
        log(level: .info, message)
    }

    func warn(_ message: String) {
        log(level: .warning, message)
    }

    func error(_ message: String) {
        log(level: .error, message)
    }
}
