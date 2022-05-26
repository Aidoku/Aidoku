//
//  Logger.swift
//  Aidoku
//
//  Created by Skitty on 5/24/22.
//

import Foundation

enum LogType {
    case `default`
    case info
    case debug
    case warning
    case error

    func toString() -> String {
        switch self {
        case .default:
            return ""
        case .info:
            return "INFO"
        case .debug:
            return "DEBUG"
        case .warning:
            return "WARN"
        case .error:
            return "ERROR"
        }
    }
}

class Logger {

    let store: LogStore

    var printLogs = true

    private var streamObserverId: UUID?
    var streamUrl: URL? {
        didSet {
            updateStreamUrl()
        }
    }

    deinit {
        if let streamObserverId = streamObserverId {
            store.removeObserver(id: streamObserverId)
        }
    }

    init(store: LogStore = LogStore(), streamUrl: URL? = nil) {
        self.store = store
        self.streamUrl = streamUrl
        updateStreamUrl()
    }

    private func updateStreamUrl() {
        if let oldId = streamObserverId { store.removeObserver(id: oldId) }
        if let newUrl = streamUrl {
            streamObserverId = store.addObserver { entry in
                Task {
                    var request = URLRequest(url: newUrl)
                    request.httpBody = entry.formatted().data(using: .utf8)
                    request.httpMethod = "POST"
                    _ = try? await URLSession.shared.data(for: request)
                }
            }
        } else {
            streamObserverId = nil
        }
    }

    func log(level: LogType = .default, _ message: String) {
        if printLogs {
            print("\(level != .default ? "[\(level.toString())] " : "")\(message)")
        }
        store.addEntry(level: level, message: message)
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
