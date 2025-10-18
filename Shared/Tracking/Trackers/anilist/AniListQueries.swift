//
//  AniListQueries.swift
//  Aidoku
//
//  Created by Koding Dev on 20/7/2022.
//

import Foundation

struct AniListQueries {
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

struct GraphQLQuery: Codable {
    var query: String
}

struct GraphQLVariableQuery<T: Codable>: Codable {
    var query: String
    var variables: T?
}

struct GraphQLResponse<T: Codable>: Codable {
    var data: T
    var errors: [GraphQLError]?
}

struct GraphQLError: Codable {
    var message: String?
    var status: Int
}

struct AniListSearchVars: Codable {
    var search: String
}

struct AniListUpdateMediaVars: Codable {
    var id: Int
    var status: String?
    var progress: Int?
    var volumes: Int?
    var score: Int?
    var startedAt: AniListDate?
    var completedAt: AniListDate?
}

struct AniListSearchResponse: Codable {
    var Page: ALPage?
}

struct AniListMediaStatusVars: Codable {
    var id: Int
}

struct AniListMediaStatusResponse: Codable {
    var Media: Media?
}

struct AniListUpdateResponse: Codable {
    var SaveMediaListEntry: SaveMediaListEntry
}

struct AniListViewerResponse: Codable {
    var Viewer: User?
}

struct SaveMediaListEntry: Codable {
    var id: Int
}

struct ALPage: Codable {
    var media: [Media]
}

struct Media: Codable {
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

struct MediaTitle: Codable {
    var userPreferred: String?
}

struct MediaImage: Codable {
    var large: String?
    var medium: String?
}

struct MediaListEntry: Codable {
    var status: String?
    var score: Float?
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

struct User: Codable {
    var mediaListOptions: MediaListOptions?
}

struct MediaListOptions: Codable {
    var scoreFormat: String?
}
