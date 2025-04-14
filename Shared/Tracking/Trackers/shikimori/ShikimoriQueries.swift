//
//  ShikimoriQueries.swift
//  Aidoku
//
//  Created by Vova Lapskiy on 02.11.2024.
//

import Foundation

// https://shikimori.one/api/doc

struct ShikimoriQueries {
    static let searchQuery = """
    query($search: String, $censored: Boolean) {
      mangas(search: $search, limit: 25, censored: $censored) {
        id
        name
        russian
        status
        kind
        poster {
          mini2xUrl
        }
      }
    }
    """
}

struct ShikimoriSearchVars: Codable {
    var search: String
    var censored: Bool
}

struct ShikimoriUser: Codable {
    var userId: Int

    enum CodingKeys: String, CodingKey {
        case userId = "id"
    }
}

struct ShikimoriPoster: Codable {
    var mini2xUrl: String
}

struct ShikimoriMangas: Codable {
    var mangas: [ShikimoriManga]
}

struct ShikimoriManga: Codable {
    var id: String
    var name: String
    var russian: String?
    var status: String
    var kind: String
    var poster: ShikimoriPoster
}

struct ShikimoriUserRate: Codable {
    var id: Int
    var targetId: Int
    var targetType: String
    var status: String
    var chapters: Int
    var volumes: Int
    var score: Int
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, status, chapters, volumes, score
        case targetId = "target_id"
        case targetType = "target_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
