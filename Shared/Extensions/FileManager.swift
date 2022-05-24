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
        (try? FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil)) ?? []
    }

    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    var contentsByDateAdded: [URL] {
        if let urls = try? FileManager.default.contentsOfDirectory(at: self,
                                                                   includingPropertiesForKeys: [.contentModificationDateKey]) {
            return urls.sorted {
                ((try? $0.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date.distantPast)
                >
                ((try? $1.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date.distantPast)
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
}

extension FileManager {

    var documentDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var temporaryDirectory: URL? {
        try? url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: documentDirectory, create: true)
    }
}

extension String {
    var directoryName: String {
        self.components(separatedBy: URL.invalidDirectoryCharacters).joined()
    }
}
