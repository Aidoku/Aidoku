//
//  FileManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation

extension URL {
    fileprivate static let invalidDirectoryCharacters: CharacterSet = {
        var invalidCharacters = CharacterSet(charactersIn: ":/")
        invalidCharacters.formUnion(.newlines)
        invalidCharacters.formUnion(.illegalCharacters)
        invalidCharacters.formUnion(.controlCharacters)
        return invalidCharacters
    }()

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var contents: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    }

    /// Directory contents with hidden entries included.
    ///
    /// A download stages itself into a directory whose name begins with a dot, so `contents` never
    /// reports one and every filter written against that prefix has nothing to match.
    var contentsIncludingHidden: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil)) ?? []
    }

    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    var contentsByDateModified: [URL] {
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: self,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            return urls.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
                >
                ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
            }
        }
        return self.contents
    }

    func createDirectory() {
        try? FileManager.default.createDirectory(at: self, withIntermediateDirectories: true, attributes: nil)
    }

    func removeItem() {
        try? FileManager.default.removeItem(at: self)
    }

    func appendingSafePathComponent(_ pathComponent: String) -> URL {
        self.appendingPathComponent(pathComponent.components(separatedBy: Self.invalidDirectoryCharacters).joined())
    }

    func append(path: String) -> URL {
        if #available(iOS 16.0, macOS 13.0, *) {
            return appending(path: path)
        } else {
            var url = self
            for component in path.split(separator: "/") {
                url = url.appendingPathComponent(String(component))
            }
            return url
        }
    }
}

extension FileManager {
    var documentDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var applicationSupportDirectory: URL {
        urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func moveFiles(in sourceDirectory: URL, to destinationDirectory: URL) {
        if !destinationDirectory.exists {
            destinationDirectory.createDirectory()
        }

        let oldFileURLs = try? contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil, options: [])

        for fileURL in oldFileURLs ?? [] {
            let destinationURL = destinationDirectory.appendingPathComponent(fileURL.lastPathComponent)
            try? moveItem(at: fileURL, to: destinationURL)
        }
    }

    func folderSize(at url: URL) -> Int64 {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .totalFileSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }

        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            size += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.totalFileSize
                    ?? values.fileSize
                    ?? 0
            )
        }
        return size
    }

    func createTemporaryDirectory() -> URL? {
        let temporaryDirectory = self.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            return temporaryDirectory
        } catch {
            LogManager.logger.error("Failed to create temporary source directory: \(error)")
            return nil
        }
    }
}

extension String {
    var directoryName: String {
        self.components(separatedBy: URL.invalidDirectoryCharacters).joined()
    }
}
