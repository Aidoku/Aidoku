//
//  Source.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation

class Source: Identifiable {
    let id = UUID()
    var url: URL
    var info: SourceInfo
    
    struct SourceInfo: Codable {
        let id: String
        let lang: String
        let name: String
        let version: Int
    }
    
    init(from url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url.appendingPathComponent("Info.plist"))
        self.info = try PropertyListDecoder().decode(SourceInfo.self, from: data)
    }
}
