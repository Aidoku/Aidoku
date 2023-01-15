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
        title = source.manifest.info.name
        lang = source.manifest.info.lang
        version = Int16(source.manifest.info.version)
        nsfw = Int16(source.manifest.info.nsfw ?? 0)
        path = source.url.pathComponents[source.url.pathComponents.count - 2..<source.url.pathComponents.count].joined(separator: "/")
    }

    func toSource() -> Source? {
        if let path = path {
            return SourceManager.shared.source(from: FileManager.default.documentDirectory.appendingPathComponent(path))
        }
        return nil
    }
}
