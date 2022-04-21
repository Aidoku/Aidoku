//
//  ExternalSourceInfo.swift
//  Aidoku
//
//  Created by Skitty on 1/16/22.
//

import Foundation

struct ExternalSourceInfo: Codable, Hashable {
    let id: String
    let name: String
    let file: String
    let icon: String
    let lang: String
    let version: Int
    let nsfw: Int?
    let minAppVersion: String?
    let maxAppVersion: String?

    var sourceUrl: URL?
}
