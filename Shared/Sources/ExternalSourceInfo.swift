//
//  ExternalSourceInfo.swift
//  Aidoku
//
//  Created by Skitty on 1/16/22.
//

import AidokuRunner
import Foundation

struct ExternalSourceInfo: Codable, Hashable {
    let id: String
    let name: String
    let version: Int
    let iconURL: String?
    let downloadURL: String?
    let languages: [String]?
    let contentRating: AidokuRunner.SourceContentRating?
    let altNames: [String]?
    let baseURL: String?
    let minAppVersion: String?
    let maxAppVersion: String?

    // deprecated
    let lang: String?
    let nsfw: Int?
    let file: String?
    let icon: String?

    var sourceUrl: URL?

    var fileURL: URL? {
        sourceUrl.flatMap { sourceUrl in
            if let downloadURL {
                URL(string: downloadURL, relativeTo: sourceUrl)
            } else if let file {
                sourceUrl
                    .appendingPathComponent("sources")
                    .appendingPathComponent(file)
            } else {
                nil
            }
        }
    }
}

extension ExternalSourceInfo {
    func with(sourceUrl: URL) -> ExternalSourceInfo {
        var copy = self
        copy.sourceUrl = sourceUrl
        return copy
    }

    func toInfo() -> SourceInfo2 {
        let iconUrl: URL? = sourceUrl.flatMap { sourceUrl in
            if let iconURL {
                URL(string: iconURL, relativeTo: sourceUrl)
            } else if let icon {
                sourceUrl
                    .appendingPathComponent("icons")
                    .appendingPathComponent(icon)
            } else {
                nil
            }
        }
        return .init(
            sourceId: id,
            iconUrl: iconUrl,
            name: name,
            altNames: altNames ?? [],
            languages: languages ?? lang.flatMap { [$0] } ?? [],
            version: version,
            contentRating: .init(rawValue: nsfw ?? 0) ?? .safe,
            externalInfo: self
        )
    }
}
