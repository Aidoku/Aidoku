//
//  Listing.swift
//  Aidoku
//
//  Created by Skitty on 1/14/22.
//

import Foundation

struct Listing: KVCObject, Hashable, Codable {
    var name: String
    var flags: Int32 = 0 // currently unused

    init(name: String) {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        if let flags = try container.decodeIfPresent(Int32.self, forKey: .flags) {
            self.flags = flags
        }
    }

    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "name": return self.name
        case "flags": return flags
        default: return nil
        }
    }
}
