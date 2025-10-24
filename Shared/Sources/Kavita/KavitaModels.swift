//
//  KavitaModels.swift
//  Aidoku
//
//  Created by Skitty on 10/19/25.
//

import AidokuRunner
import Foundation

struct KavitaErrorResponse: Codable, Sendable {
    let title: String
    let status: Int
}

struct KavitaLibrary: Codable, Sendable {
    let id: Int
    let name: String
}

struct KavitaGenre: Codable, Sendable {
    let id: Int
    let title: String
}

// https://github.com/Kareadita/Kavita/blob/develop/API/DTOs/Filtering/v2/FilterField.cs
enum KavitaFilterField: Int, Codable {
    case none = -1
    case summary = 0
    case seriesName = 1
    case publicationStatus = 2
    case languages = 3
    case ageRating = 4
    case userRating = 5
    case tags = 6
    case collectionTags = 7
    case translators = 8
    case characters = 9
    case publisher = 10
    case editor = 11
    case coverArtist = 12
    case letterer = 13
    case colorist = 14
    case inker = 15
    case penciller = 16
    case writers = 17
    case genres = 18
    case libraries = 19
    case readProgress = 20
    case formats = 21
    case releaseYear = 22
    case readTime = 23
    case path = 24
    case filePath = 25
    case wantToRead = 26
    case readingDate = 27
    case averageRating = 28
    case imprint = 29
    case team = 30
    case location = 31
    case readLast = 32
    case fileSize = 33
}

// https://github.com/Kareadita/Kavita/blob/develop/API/DTOs/Filtering/SortField.cs
enum KavitaSortField: Int, Codable {
    case sortName = 1
    case createdDate = 2
    case lastModifiedDate = 3
    case lastChapterAdded = 4
    case timeToRead = 5
    case releaseYear = 6
    case readProgress = 7
    case averageRating = 8
    case random = 9
}

struct KavitaFilterV2: Codable, Sendable {
    enum Comparison: Int, Codable {
        case equal = 0
        case greaterThan = 1
        case greaterThanEqual = 2
        case lessThan = 3
        case lessThanEqual = 4
        case contains = 5
        case mustContains = 6
        case matches = 7
        case notContains = 8
        case notEqual = 9
        case beginsWith = 10
        case endsWith = 11
        case isBefore = 12
        case isAfter = 13
        case isInLast = 14
        case isNotInLast = 15
        case isEmpty = 16
    }
    enum Combination: Int, Codable {
        case or = 0
        case and = 1
    }
    struct Statement: Codable, Sendable {
        let comparison: Comparison
        let field: KavitaFilterField
        let value: String
    }
    struct SortOptions: Codable, Sendable {
        let sortField: KavitaSortField
        let isAscending: Bool
    }

    var name: String?
    var statements: [Statement] = []
    var combination: Combination = .and
    var sortOptions: SortOptions?
    var limitTo: Int = 0 // 0 is no limit
}

struct KavitaDashComponent: Codable, Sendable {
    enum StreamType: Int, Codable {
        case onDeck = 1
        case recentlyUpdated = 2
        case newlyAdded = 3
        case smartFilter = 4
        case moreInGenre = 5
    }

    let id: Int
    let name: String
    let streamType: StreamType
    let smartFilterEncoded: String?
}

struct KavitaSeriesGroup: Codable, Sendable {
    let seriesId: Int
    let libraryId: Int
    let seriesName: String
}

extension KavitaSeriesGroup {
    func into() -> KavitaSeries {
        .init(id: seriesId, libraryId: libraryId, name: seriesName)
    }
}

struct KavitaSeries: Codable, Sendable {
    let id: Int
    let libraryId: Int
    let name: String
}

struct KavitaSeriesMetadata: Codable, Sendable {
    enum Status: Int, Codable {
        case ongoing = 0
        case hiatus = 1
        case completed = 2
        case cancelled = 3
        case ended = 4
    }

    struct Person: Codable, Sendable {
        let name: String
    }

    struct Tag: Codable, Sendable {
        let title: String
    }

    let summary: String
    let publicationStatus: Status
    let pencillers: [Person]
    let writers: [Person]
    let genres: [Tag]
    let tags: [Tag]
    let ageRating: Int
}

extension KavitaSeries {
    func intoManga(
        sourceKey: String,
        baseUrl: String,
        apiKey: String,
        metadata: KavitaSeriesMetadata? = nil
    ) -> AidokuRunner.Manga {
        let status: AidokuRunner.PublishingStatus = switch metadata?.publicationStatus {
            case .ongoing: .ongoing
            case .hiatus: .hiatus
            case .completed, .ended: .completed
            case .cancelled: .cancelled
            default: .unknown
        }
        let contentRating: AidokuRunner.ContentRating = if let ageRating = metadata?.ageRating {
            if ageRating >= 10 {
                // mature 17+ or r18
                .nsfw
            } else if ageRating >= 8 {
                // teen or ma15+
                .suggestive
            } else if ageRating <= 1 {
                // unknown or pending
                .unknown
            } else {
                .safe
            }
        } else {
            .unknown
        }

        return .init(
            sourceKey: sourceKey,
            key: "\(id)",
            title: name,
            cover: "\(baseUrl)/api/image/series-cover?seriesId=\(id)&apiKey=\(apiKey)",
            artists: metadata?.pencillers.map { $0.name },
            authors: metadata?.writers.map { $0.name },
            description: metadata?.summary,
            url: URL(string: "\(baseUrl)/library/\(libraryId)/series/\(id)"),
            tags: (metadata?.genres.map { $0.title } ?? []) + (metadata?.tags.map { $0.title } ?? []),
            status: status,
            contentRating: contentRating,
        )
    }
}

struct KavitaVolume: Codable, Sendable {
    struct File: Codable, Sendable {
        let format: Int
    }
    struct Chapter: Codable, Sendable {
        let id: Int
        let number: String
        let title: String
        let createdUtc: Date
        let language: String?
        let pages: Int
        let pagesRead: Int
        let lastReadingProgressUtc: Date
        let files: [File]
    }

    let id: Int
    let name: String
    let number: Int
    let seriesId: Int
    let chapters: [Chapter]
}

extension KavitaVolume {
    func intoChapters(baseUrl: String, apiKey: String) -> [AidokuRunner.Chapter] {
        chapters.compactMap { chapter -> AidokuRunner.Chapter? in
            let isEpub = chapter.files.contains(where: { $0.format == 3 })
            guard !isEpub else { return nil }
            let chapterNumber = Float(chapter.number) ?? 0
            let noVolume = number < 0 || number >= 100000
            let noChapter = chapterNumber < 0 || chapterNumber >= 100000
            return .init(
                key: "\(chapter.id)",
                title: noChapter && noVolume ? chapter.title : nil,
                chapterNumber: noChapter ? nil : chapterNumber,
                volumeNumber: noVolume ? nil : Float(number),
                dateUploaded: chapter.createdUtc,
                url: URL(string: "\(baseUrl)/library/1/series/\(seriesId)/chapter/\(chapter.id)"),
                language: chapter.language,
                thumbnail: "\(baseUrl)/api/image/chapter-cover?chapterId=\(chapter.id)&apiKey=\(apiKey)"
            )
        }
    }
}
