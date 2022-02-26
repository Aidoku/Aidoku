//
//  FileManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation

extension URL {
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var contents: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil)) ?? []
    }

    var contentsByDateAdded: [URL] {
        if let urls = try? FileManager.default.contentsOfDirectory(at: self,
                                                                   includingPropertiesForKeys: [.contentModificationDateKey]) {
            return urls.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
                >
                ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
            }
        }
        return self.contents
    }

    func createDirctory() {
        try? FileManager.default.createDirectory(at: self, withIntermediateDirectories: true, attributes: nil)
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
