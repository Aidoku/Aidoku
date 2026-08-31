//
//  AniListQueries.swift
//  Aidoku
//
//  Created by Koding Dev on 20/7/2022.
//

import Foundation

enum AniListQueries {
    static let searchQuery = """
    query ($search: String) {
      Page(perPage: 20) {
        media(search: $search, type: MANGA, isAdult: false) {
          id
          title {
            userPreferred
          }
          description
          status
          format
          coverImage {
            medium
          }
          mediaListEntry {
            id
          }
        }
      }
    }
    """

    static let searchQueryNsfw = """
    query ($search: String) {
      Page(perPage: 20) {
        media(search: $search, type: MANGA) {
          id
          title {
            userPreferred
          }
          description
          status
          format
          coverImage {
            medium
          }
          mediaListEntry {
            id
          }
        }
      }
    }
    """

    static let mediaQuery = """
    query ($id: Int) {
      Media(id: $id) {
        id
        title {
          userPreferred
        }
        description
        status
        format
        coverImage {
          medium
        }
      }
    }
    """

    static let mediaStatusQuery = """
    query ($id: Int) {
      Media(id: $id) {
        chapters
        volumes
        mediaListEntry {
          status
          score(format: POINT_100)
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

    static let updateMediaQuery = """
    mutation (
     $id: Int,
     $status: MediaListStatus,
     $progress: Int,
     $volumes: Int,
     $score: Int,
     $startedAt: FuzzyDateInput,
     $completedAt: FuzzyDateInput
    ) {
     SaveMediaListEntry(
       mediaId: $id,
       status: $status,
       progress: $progress,
       progressVolumes: $volumes,
       scoreRaw: $score,
       startedAt: $startedAt,
       completedAt: $completedAt
     ) {
       id
     }
    }
    """

    static let viewerQuery = """
    query {
      Viewer {
        mediaListOptions {
          scoreFormat
        }
      }
    }
    """
}

struct GraphQLQuery: Codable, Sendable {
    var query: String
}

struct GraphQLVariableQuery<T: Codable>: Codable {
    var query: String
    var variables: T?
}

struct GraphQLResponse<T: Codable & Sendable>: Codable, Sendable {
    var data: T?
    var errors: [GraphQLError]?
}

struct GraphQLError: Codable, Sendable {
    var message: String?
    var status: Int
}

struct AniListSearchVars: Codable, Sendable {
    var search: String
}

struct AniListUpdateMediaVars: Codable, Sendable {
    var id: Int
    var status: String?
    var progress: Int?
    var volumes: Int?
    var score: Int?
    var startedAt: AniListDate?
    var completedAt: AniListDate?
}

struct AniListSearchResponse: Codable, Sendable {
    var Page: ALPage?
}

struct AniListMediaStatusVars: Codable, Sendable {
    var id: Int
}

struct AniListMediaStatusResponse: Codable, Sendable {
    var Media: Media?
}

struct AniListUpdateResponse: Codable, Sendable {
    var SaveMediaListEntry: SaveMediaListEntry
}

struct AniListViewerResponse: Codable, Sendable {
    var Viewer: User?
}

struct SaveMediaListEntry: Codable, Sendable {
    var id: Int
}

struct ALPage: Codable, Sendable {
    var media: [Media]
}

struct Media: Codable, Sendable {
    var id: Int?
    var title: MediaTitle?
    var description: String?
    var status: String?
    var format: String?
    var coverImage: MediaImage?

    var mediaListEntry: MediaListEntry?
    var chapters: Int?
    var volumes: Int?
}

struct MediaTitle: Codable, Sendable {
    var userPreferred: String?
}

struct MediaImage: Codable, Sendable {
    var large: String?
    var medium: String?
}

struct MediaListEntry: Codable, Sendable {
    var status: String?
    var score: Float?
    var progress: Int?
    var progressVolumes: Int?
    var startedAt: AniListDate?
    var completedAt: AniListDate?
}

struct AniListDate: Codable, Sendable {
    var year: Int?
    var month: Int?
    var day: Int?
}

struct User: Codable, Sendable {
    var mediaListOptions: MediaListOptions?
}

struct MediaListOptions: Codable, Sendable {
    var scoreFormat: String?
}
