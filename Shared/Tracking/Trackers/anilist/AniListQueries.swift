//
//  AniListQueries.swift
//  Aidoku
//
//  Created by Koding Dev on 20/7/2022.
//

import Foundation

struct GraphQLQuery<T: Codable>: Codable {
    var query: String
    var variables: T
}

struct GraphQLResponse<T: Codable>: Codable {
    var data: T
}

// MARK: - Media search
let searchQuery = """
query ($search: String) {
  Media(search: $search, type: MANGA) {
    id
    idMal
    title {
      english
      romaji
    }
    description
    status
    format
    coverImage {
      large
    }
  }
}
"""

struct AniListSearchVars: Codable {
    var search: String
}

struct AniListSearchResponse: Codable {
    var media: Media

    enum CodingKeys: String, CodingKey {
        case media = "Media"
    }
}

// MARK: - Media status
let mediaStatusQuery = """
query ($id: Int) {
  Media(id: $id) {
    chapters
    volumes

    mediaListEntry {
      status
      score
      progress
      progressVolumes

      startedAt {
        year
        month
        day
      }

      completedAt {
        year
        month
        day
      }
    }
  }
}
"""

struct AniListMediaStatusVars: Codable {
    var id: Int
}

// MARK: - Media Results
struct Media: Codable {
    var id: Int?
    var title: MediaTitle?
    var description: String?
    var status: String?
    var coverImage: MediaImage?

    var mediaListEntry: MediaListEntry?
    var chapters: Int?
    var volumes: Int?
}

struct MediaTitle: Codable {
    var english: String
    var romaji: String
}

struct MediaImage: Codable {
    var large: String?
}

struct MediaListEntry: Codable {
    var status: String?
    var score: Int?
    var progress: Int?
    var progressVolumes: Int?
    var startedAt: AniListDate?
    var completedAt: AniListDate?
}

struct AniListDate: Codable {
    var year: Int?
    var month: Int?
    var day: Int?
}
