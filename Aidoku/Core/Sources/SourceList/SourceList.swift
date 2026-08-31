//
//  SourceList.swift
//  Aidoku
//
//  Created by Skitty on 6/11/25.
//

import Foundation

struct SourceList: Equatable {
    let url: URL
    let name: String
    var feedbackURL: URL?
    let sources: [ExternalSourceInfo]
    var legacy: Bool = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url
    }
}

struct CodableSourceList: Codable {
    let name: String
    let feedbackURL: String?
    let sources: [ExternalSourceInfo]

    func into(url: URL) -> SourceList {
        .init(
            url: url,
            name: name,
            feedbackURL: feedbackURL.flatMap { URL(string: $0) },
            sources: sources.map {
                $0.with(sourceUrl: url)
            }
        )
    }
}
