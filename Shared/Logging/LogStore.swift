//
//  LogStore.swift
//  Aidoku
//
//  Created by Skitty on 5/24/22.
//

import Foundation

actor LogStore {
    var entries: [LogEntry] = []
    private var continuations: [UUID: AsyncStream<LogEntry>.Continuation] = [:]
    private var streamUrl: URL?

    func addEntry(level: LogType, message: String) {
        let entry = LogEntry(date: Date(), type: level, message: message)
        entries.append(entry)
        if let streamUrl {
            Task {
                var request = URLRequest(url: streamUrl)
                request.httpBody = entry.formatted().data(using: .utf8)
                request.httpMethod = "POST"
                _ = try? await URLSession.shared.data(for: request)
            }
        }
        for continuation in continuations.values {
            continuation.yield(entry)
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

    func logStream() -> AsyncStream<LogEntry> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.removeContinuation(id: id)
                }
            }
        }
    }

    func setStreamUrl(_ url: URL?) {
        streamUrl = url
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
