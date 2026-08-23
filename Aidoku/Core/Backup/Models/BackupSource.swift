//
//  BackupSource.swift
//  Aidoku
//
//  Created by skitty on 5/1/26.
//

import CoreData

struct BackupSource {
    let id: String
    let apiVersion: String?
    let config: Data?

    init(_ object: SourceObject) {
        self.id = object.id! // property is non-optional
        self.apiVersion = object.apiVersion
        self.config = object.customSource as? Data
    }

    func toObject(context: NSManagedObjectContext? = nil) -> SourceObject? {
        guard let config, let apiVersion else { return nil }
        let obj: SourceObject
        if let context {
            obj = SourceObject(context: context)
        } else {
            obj = SourceObject()
        }
        obj.id = id
        obj.apiVersion = apiVersion
        obj.customSource = config as NSObject
        return obj
    }
}

extension BackupSource: Codable {
    init(from decoder: any Decoder) throws {
        // try decoding just as a string
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) {
            self.id = id
            self.apiVersion = nil
            self.config = nil
            return
        }
        // otherwise, assume object
        let objectContainer = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try objectContainer.decode(String.self, forKey: .id)
        self.apiVersion = try? objectContainer.decodeIfPresent(String.self, forKey: .apiVersion)
        self.config = try? objectContainer.decodeIfPresent(Data.self, forKey: .config)
    }

    func encode(to encoder: any Encoder) throws {
        if let config {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(apiVersion, forKey: .apiVersion)
            try container.encode(config, forKey: .config)
        } else {
            var container = encoder.singleValueContainer()
            try container.encode(id)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case apiVersion
        case config
    }
}

extension BackupSource: Hashable {}
