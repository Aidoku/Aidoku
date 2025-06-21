//
//  SourceObject.swift
//  Aidoku
//
//  Created by Skitty on 2/14/22.
//

import AidokuRunner
import CoreData

extension SourceObject {
    func load(from source: Source) {
        id = source.id
        apiVersion = source.apiVersion
        path = source.url.pathComponents[source.url.pathComponents.count - 2..<source.url.pathComponents.count]
            .joined(separator: "/")
    }

    func load(from source: AidokuRunner.Source) {
        id = source.id
        apiVersion = source.apiVersion
        if let url = source.url {
            path = url.pathComponents[url.pathComponents.count - 2..<url.pathComponents.count]
                .joined(separator: "/")
        }
    }

    func toData() -> SourceObjectData {
        .init(
            objectID: objectID,
            id: id ?? "",
            apiVersion: apiVersion,
            path: path,
            listing: listing,
            customSource: customSource
        )
    }
}

struct SourceObjectData {
    let objectID: NSManagedObjectID
    let id: String
    let apiVersion: String?
    let path: String?
    let listing: Int16
    let customSource: NSObject?
}

extension SourceObjectData {
    func toSource() -> Source? {
        if apiVersion == "0.6", let path {
            return try? Source(from: FileManager.default.documentDirectory.appendingPathComponent(path))
        }
        return nil
    }

    func toNewSource() async -> AidokuRunner.Source? {
        if apiVersion == "0.6" {
            let source = toSource()
            return source.flatMap({ .legacy(source: $0) })
        } else if
            let data = customSource as? Data,
            let config = try? CustomSourceConfig(from: data)
        {
            return config.toSource()
        } else if let path {
            let url = FileManager.default.documentDirectory.appendingPathComponent(path)
            return try? await AidokuRunner.Source(id: id, url: url)
        }
        return nil
    }
}
