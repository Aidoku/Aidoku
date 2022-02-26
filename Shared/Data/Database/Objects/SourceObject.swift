//
//  SourceObject.swift
//  Aidoku
//
//  Created by Skitty on 2/14/22.
//

import CoreData

extension SourceObject {

    func load(from source: Source) {
        id = source.id
        title = source.info.name
        lang = source.info.lang
        version = Int16(source.info.version)
        nsfw = Int16(source.info.nsfw ?? 0)
        path = source.url.pathComponents[source.url.pathComponents.count - 2..<source.url.pathComponents.count].joined(separator: "/")
    }

    func toSource() -> Source? {
        if let path = path {
            return try? Source(from: FileManager.default.documentDirectory.appendingPathComponent(path))
        }
        return nil
    }
}
