//
//  ReaderTemporaryPageStore.swift
//  Aidoku
//
//  Created by skitty on 8/23/26.
//

import AidokuRunner
import Foundation

actor ReaderTemporaryPageStore {
    private static let sessionsDirectory = FileManager.default.cachesDirectory
        .appendingPathComponent("ReaderSessions", isDirectory: true)

    private let directory: URL

    init() {
        directory = Self.sessionsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        directory.createDirectory()
    }

    func store(
        _ image: PlatformImage,
        chapterKey: String,
        pageIndex: Int
    ) -> URL? {
        guard let data = image.pngData() else {
            return nil
        }

        let fileExtension = "png"
        let filename = "\(chapterKey.hashValue)-\(pageIndex).\(fileExtension)"
        let url = directory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func removeAll() {
        directory.removeItem()
    }

    static func removeAllSessions() {
        sessionsDirectory.removeItem()
    }
}
