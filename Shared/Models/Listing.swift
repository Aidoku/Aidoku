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

    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "name": return self.name
        case "flags": return flags
        default: return nil
        }
    }
}
