//
//  KomgaModels.swift
//  Aidoku
//
//  Created by Skitty on 5/23/25.
//

import AidokuRunner
import Foundation

struct KomgaError: Codable, Sendable {
    let error: String
    let message: String?
}

struct KomgaPageResponse<T: Codable & Sendable>: Codable, Sendable {
    let content: T
    let totalPages: Int
}

struct KomgaLibrary: Codable, Sendable {
    let id: String
    let name: String
}

struct KomgaPage: Codable, Sendable {
    let number: Int
    let mediaType: String
}

// https://github.com/gotson/komga/blob/master/komga/src/main/kotlin/org/gotson/komga/domain/model/ReadStatus.kt
enum KomgaReadStatus: String {
    case unread = "UNREAD"
    case read = "READ"
    case inProgress = "IN_PROGRESS"
}

// MARK: Searching

struct KomgaSearchBody: Encodable {
    var condition: KomgaSearchCondition?
    var fullTextSearch: String?
}

// https://github.com/gotson/komga/blob/master/komga/src/main/kotlin/org/gotson/komga/domain/model/SearchCondition.kt
enum KomgaSearchCondition {
    case allOf([KomgaSearchCondition])
    case anyOf([KomgaSearchCondition])
    case ageRating(Int?, exclude: Bool = false)
    case author(name: String? = nil, role: String? = nil, exclude: Bool = false)
//    case collectionId
//    case complete
    case deleted(Bool)
    case genre(String, exclude: Bool = false)
    case language(String, exclude: Bool = false)
    case libraryId(String, exclude: Bool = false)
//    case mediaProfile
//    case mediaStatus
//    case numberSort
//    case oneShot
    case publisher(String, exclude: Bool = false)
//    case poster
//    case readListId
    case readStatus(KomgaReadStatus, exclude: Bool = false)
    case releaseDate(Int?, exclude: Bool = false)
    case seriesId(String, exclude: Bool = false)
    case seriesStatus(KomgaSeries.Metadata.Status, exclude: Bool = false)
    case sharingLabel(String, exclude: Bool = false)
    case tag(String, exclude: Bool = false)
//    case title
//    case titleSort
}

extension KomgaSearchCondition: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .allOf(let array):
                try container.encode(array, forKey: .allOf)
            case .anyOf(let array):
                try container.encode(array, forKey: .anyOf)
            case .ageRating(let rating, let exclude):
                if let rating {
                    try container.encode(ConditionValue(operator: exclude ? "isNot" : "is", value: rating), forKey: .ageRating)
                } else {
                    try container.encode(ConditionValue<Int>(operator: exclude ? "isNotNull" : "isNull"), forKey: .ageRating)
                }
            case .author(let name, let role, let exclude):
                try container.encode(ConditionValue(operator: exclude ? "isNot" : "is", value: AuthorValue(name: name, role: role)), forKey: .author)
            case .deleted(let bool):
                try container.encode(ConditionValue<String>(operator: bool ? "isTrue" : "isFalse"), forKey: .deleted)
            case .genre(let genre, let exclude):
                if genre.isEmpty {
                    try container.encode(ConditionValue<String>(operator: exclude ? "isNull" : "isNotNull"), forKey: .genre)
                } else {
                    try container.encode(ConditionValue(operator: exclude ? "isNot" : "is", value: genre), forKey: .genre)
                }
            case .language(let id, let exclude):
                try container.encode(ConditionValue(operator: (id.isEmpty ? !exclude : exclude) ? "isNot" : "is", value: id), forKey: .language)
            case .libraryId(let id, let exclude):
                try container.encode(ConditionValue(operator: (id.isEmpty ? !exclude : exclude) ? "isNot" : "is", value: id), forKey: .libraryId)
            case .publisher(let id, let exclude):
                try container.encode(ConditionValue(operator: (id.isEmpty ? !exclude : exclude) ? "isNot" : "is", value: id), forKey: .publisher)
            case .readStatus(let readStatus, let exclude):
                try container.encode(ConditionValue(operator: exclude ? "isNot" : "is", value: readStatus.rawValue), forKey: .readStatus)
            case .releaseDate(let year, let exclude):
                if let year {
                    struct ReleaseDate: Encodable {
                        struct Inner: Encodable {
                            var `operator`: String
                            var dateTime: Date?
                        }
                        var releaseDate: Inner

                        init(operator: String, value: Date? = nil) {
                            self.releaseDate = .init(operator: `operator`, dateTime: value)
                        }
                    }
                    if exclude {
                        // any date outside of the given year (either nil, after end of year, or before start)
                        guard
                            let firstOfYear = Date.firstOf(year: year),
                            let lastOfYear = Date.lastOf(year: year)
                        else { break }
                        try container.encode([
                            ReleaseDate(operator: "after", value: lastOfYear),
                            ReleaseDate(operator: "before", value: firstOfYear),
                            ReleaseDate(operator: "isNull")
                        ], forKey: .anyOf)
                    } else {
                        // any date that is within the given year (both after end of prev year and before first of next year)
                        guard
                            let firstOfNextYear = Date.firstOf(year: year + 1),
                            let lastOfPrevYear = Date.lastOf(year: year - 1)
                        else { break }
                        try container.encode([
                            ReleaseDate(operator: "after", value: lastOfPrevYear),
                            ReleaseDate(operator: "before", value: firstOfNextYear)
                        ], forKey: .allOf)
                    }
                } else {
                    try container.encode(ConditionValue<Date>(operator: exclude ? "isNull" : "isNotNull"), forKey: .releaseDate)
                }
            case .seriesId(let id, let exclude):
                try container.encode(ConditionValue(operator: exclude ? "isNot" : "is", value: id), forKey: .seriesId)
            case .seriesStatus(let status, let exclude):
                try container.encode(ConditionValue(operator: exclude ? "isNot" : "is", value: status.rawValue), forKey: .seriesStatus)
            case .sharingLabel(let genre, let exclude):
                if genre.isEmpty {
                    try container.encode(ConditionValue<String>(operator: exclude ? "isNull" : "isNotNull"), forKey: .genre)
                } else {
                    try container.encode(ConditionValue(operator: exclude ? "isNot" : "is", value: genre), forKey: .genre)
                }
            case .tag(let tag, let exclude):
                if tag.isEmpty {
                    try container.encode(ConditionValue<String>(operator: exclude ? "isNull" : "isNotNull"), forKey: .tag)
                } else {
                    try container.encode(ConditionValue(operator: exclude ? "isNot" : "is", value: tag), forKey: .tag)
                }
        }
    }

    struct ConditionValue<T: Encodable>: Encodable {
        let `operator`: String
        var value: T?
    }

    struct AuthorValue: Encodable {
        let name: String?
        let role: String?
    }

    enum CodingKeys: CodingKey {
        case allOf
        case anyOf
        case ageRating // series only
        case author
        case collectionId // series only
        case complete // series only
        case deleted
        case genre // series only
        case language // series only
        case libraryId
        case mediaProfile // books only
        case mediaStatus // books only
        case numberSort // books only
        case oneShot
        case publisher // series only
        case poster // books only
        case readListId // books only
        case readStatus
        case releaseDate
        case seriesId // books only
        case seriesStatus // series only
        case sharingLabel // series only
        case tag
        case title
        case titleSort // series only
    }
}

// MARK: Books

struct KomgaBook: Codable, Sendable {
    struct Media: Codable, Sendable {
        let mediaProfile: String
        let epubDivinaCompatible: Bool
        let pagesCount: Int
    }

    struct Metadata: Codable, Sendable {
        struct Author: Codable, Sendable {
            let name: String
            let role: String?
        }

        let title: String
        let number: String
        let numberSort: Float
        let authors: [Author]
        let tags: [String]
        let created: Date
        let releaseDate: Date?
    }

    let id: String
    let seriesId: String
    let libraryId: String
    let name: String
    let media: Media
    let metadata: Metadata
    let readProgress: KomgaBookReadProgress?
}

struct KomgaBookReadProgress: Codable {
    let page: Int
    let completed: Bool
    let lastModified: Date?
}

extension KomgaBook {
    func intoManga(sourceKey: String, baseUrl: String) -> AidokuRunner.Manga {
        .init(
            sourceKey: sourceKey,
            key: seriesId,
            title: metadata.title,
            cover: "\(baseUrl)/api/v1/books/\(id)/thumbnail",
            authors: metadata.authors.map { $0.name },
            url: URL(string: "\(baseUrl)/series/\(seriesId)"),
            tags: metadata.tags,
        )
    }

    func intoChapter(baseUrl: String, useChapters: Bool) -> AidokuRunner.Chapter {
        .init(
            key: id,
            title: metadata.title,
            chapterNumber: useChapters ? metadata.numberSort : nil,
            volumeNumber: useChapters ? nil : metadata.numberSort,
            dateUploaded: metadata.releaseDate ?? metadata.created,
            scanlators: metadata.authors.compactMap {
                if $0.role == "translator" {
                    $0.name
                } else {
                    nil
                }
            },
            url: URL(string: "\(baseUrl)/book/\(id)"),
            language: "en",
            thumbnail: "\(baseUrl)/api/v1/books/\(id)/thumbnail",
        )
    }
}

// MARK: Series

struct KomgaSeries: Codable, Sendable {
    struct Metadata: Codable, Sendable {
        enum Status: String, Codable {
            case ended = "ENDED"
            case ongoing = "ONGOING"
            case abandoned = "ABANDONED"
            case hiatus = "HIATUS"
        }

        enum ReadingDirection: String, Codable {
            case leftToRight = "LEFT_TO_RIGHT"
            case rightToLeft = "RIGHT_TO_LEFT"
            case vertical = "VERTICAL"
            case scroll = "SCROLL"
            case webtoon = "WEBTOON"
            case unknown = ""
        }

        let ageRating: Int?
        let status: Status
        let title: String
        let summary: String
        let readingDirection: ReadingDirection
        let genres: [String]
        let tags: [String]
    }

    struct BooksMetadata: Codable, Sendable {
        let authors: [KomgaBook.Metadata.Author]
        let summary: String?
    }

    let id: String
    let libraryId: String
    let name: String
    let metadata: Metadata
    let booksMetadata: BooksMetadata
    let booksCount: Int
}

extension KomgaSeries {
    func intoManga(sourceKey: String, baseUrl: String) -> AidokuRunner.Manga {
        let status: AidokuRunner.PublishingStatus = switch metadata.status {
            case .ended: .completed
            case .ongoing: .ongoing
            case .abandoned: .cancelled
            case .hiatus: .hiatus
        }
        let contentRating: AidokuRunner.ContentRating = metadata.ageRating.flatMap {
            if $0 >= 18 {
                .nsfw
            } else if $0 >= 16 {
                .suggestive
            } else {
                .safe
            }
        } ?? .safe
        let viewer: AidokuRunner.Viewer = switch metadata.readingDirection {
            case .leftToRight: .leftToRight
            case .rightToLeft: .rightToLeft
            case .vertical: .vertical
            case .scroll, .webtoon: .webtoon
            case .unknown: .unknown
        }

        return .init(
            sourceKey: sourceKey,
            key: id,
            title: metadata.title,
            cover: "\(baseUrl)/api/v1/series/\(id)/thumbnail",
            artists: booksMetadata.authors.compactMap {
                if $0.role == "penciller" {
                    $0.name
                } else {
                    nil
                }
            },
            authors: booksMetadata.authors.compactMap {
                if $0.role == "writer" {
                    $0.name
                } else {
                    nil
                }
            },
            description: (metadata.summary.isEmpty ? booksMetadata.summary : metadata.summary)?
                .replacingOccurrences(of: "\n", with: "  \n"),
            url: URL(string: "\(baseUrl)/series/\(id)"),
            tags: (metadata.genres + metadata.tags).sorted(),
            status: status,
            contentRating: contentRating,
            viewer: viewer,
        )
    }
}
