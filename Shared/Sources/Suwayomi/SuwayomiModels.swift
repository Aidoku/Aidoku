//
//  SuwayomiModels.swift
//  Aidoku
//
//  Created by skitty on 7/7/26.
//

import AidokuRunner
import Foundation

enum SuwayomiMangaOrderBy: String, Encodable, Sendable {
    case id = "ID"
    case title = "TITLE"
    case inLibraryAt = "IN_LIBRARY_AT"
    case lastFetchedAt = "LAST_FETCHED_AT"
}

enum SuwayomiSortOrder: String, Encodable, Sendable {
    case asc = "ASC"
    case desc = "DESC"
}

enum SuwayomiMangaStatus: String, Encodable, Sendable, CaseIterable {
    case unknown = "UNKNOWN"
    case ongoing = "ONGOING"
    case completed = "COMPLETED"
    case licensed = "LICENSED"
    case publishingFinished = "PUBLISHING_FINISHED"
    case cancelled = "CANCELLED"
    case onHiatus = "ON_HIATUS"

    var title: String {
        switch self {
            case .unknown: NSLocalizedString("UNKNOWN")
            case .ongoing: NSLocalizedString("ONGOING")
            case .completed: NSLocalizedString("COMPLETED")
            case .licensed: NSLocalizedString("STATUS_LICENSED")
            case .publishingFinished: NSLocalizedString("STATUS_PUBLISHING_FINISHED")
            case .cancelled: NSLocalizedString("CANCELLED")
            case .onHiatus: NSLocalizedString("HIATUS")
        }
    }
}

struct SuwayomiMangaFilterInput: Encodable, Sendable {
    var and: [SuwayomiMangaFilterInput]?
    var or: [SuwayomiMangaFilterInput]?
    var categoryId: SuwayomiIntFilterInput?
    var title: SuwayomiStringFilterInput?
    var url: SuwayomiStringFilterInput?
    var artist: SuwayomiStringFilterInput?
    var author: SuwayomiStringFilterInput?
    var description: SuwayomiStringFilterInput?
    var genre: SuwayomiStringFilterInput?
    var status: SuwayomiMangaStatusFilterInput?
}

struct SuwayomiIntFilterInput: Encodable, Sendable {
    var equalTo: Int?
    var isNull: Bool?

    static func equalTo(_ value: Int) -> Self {
        .init(equalTo: value)
    }

    static func isNull(_ value: Bool) -> Self {
        .init(isNull: value)
    }
}

struct SuwayomiStringFilterInput: Encodable, Sendable {
    var includesInsensitive: String?
    var notIncludesInsensitive: String?

    static func includesInsensitive(_ value: String) -> Self {
        .init(includesInsensitive: value)
    }

    static func notIncludesInsensitive(_ value: String) -> Self {
        .init(notIncludesInsensitive: value)
    }
}

struct SuwayomiMangaStatusFilterInput: Encodable, Sendable {
    var `in`: [SuwayomiMangaStatus]?
    var notEqualToAny: [SuwayomiMangaStatus]?

    static func `in`(_ value: [SuwayomiMangaStatus]) -> Self {
        .init(in: value)
    }

    static func notEqualToAny(_ value: [SuwayomiMangaStatus]) -> Self {
        .init(notEqualToAny: value)
    }
}

struct SuwayomiGraphQLErrorResponse: Decodable, Sendable {
    let errors: [GraphQLError]

    struct GraphQLError: Decodable, Sendable {
        let message: String
    }
}

struct SuwayomiRefreshResponse: Decodable, Sendable {
    let data: DataContainer?

    struct DataContainer: Decodable, Sendable {
        let refreshToken: Token
    }

    struct Token: Decodable, Sendable {
        let accessToken: String?
    }
}

struct SuwayomiCategoryResponse: Decodable, Sendable {
    let data: DataContainer

    struct DataContainer: Decodable, Sendable {
        let categories: CategoryConnection
    }

    struct CategoryConnection: Decodable, Sendable {
        let nodes: [SuwayomiCategoryNode]
    }
}

struct SuwayomiCategoryNode: Decodable, Sendable {
    let id: Int
    let name: String
}

struct SuwayomiMangaUpdateResponse: Decodable, Sendable {
    let data: DataContainer

    struct DataContainer: Decodable, Sendable {
        let manga: SuwayomiMangaNode
        let chapters: ChapterConnection
    }

    struct ChapterConnection: Decodable, Sendable {
        let nodes: [SuwayomiChapterNode]
    }
}

struct SuwayomiPagesResponse: Decodable, Sendable {
    let data: DataContainer

    struct DataContainer: Decodable, Sendable {
        let fetchChapterPages: Pages
    }

    struct Pages: Decodable, Sendable {
        let pages: [String]
    }
}

struct SuwayomiMangaResponse: Decodable, Sendable {
    let data: DataContainer

    struct DataContainer: Decodable, Sendable {
        let mangas: MangaConnection
    }

    struct MangaConnection: Decodable, Sendable {
        let nodes: [SuwayomiMangaNode]
    }
}

struct SuwayomiChapterNode: Decodable, Sendable {
    let id: Int
    let url: String?
    let chapterNumber: Float?
    let name: String?
    let uploadDate: String?
    let scanlator: String?
    let sourceOrder: Int?
    let mangaId: Int

    func intoChapter(baseUrl: URL) -> AidokuRunner.Chapter {
        .init(
            key: "\(id)",
            title: name?.isEmpty == false ? name : nil,
            chapterNumber: chapterNumber,
            dateUploaded: uploadDate.flatMap { Date(suwayomiTimestamp: $0) },
            scanlators: scanlator.flatMap { $0.isEmpty ? nil : [$0] },
            url: url.flatMap { URL(string: $0, relativeTo: baseUrl) }
        )
    }
}

struct SuwayomiMangaNode: Decodable, Sendable {
    let artist: String?
    let author: String?
    let description: String?
    let id: Int?
    let inLibraryAt: String?
    let lastFetchedAt: String?
    let status: String?
    let thumbnailUrl: String?
    let title: String?
    let url: String?
    let genre: [String]?
    let chapters: ChapterConnection?
    let latestUploadedChapter: UploadedChapter?
    let latestFetchedChapter: FetchedChapter?
    let lastReadChapter: ReadChapter?
    let unreadCount: Int?
    let downloadCount: Int?
    let source: Source?
    let realUrl: String?

    struct ChapterConnection: Decodable, Sendable {
        let totalCount: Int
    }

    struct UploadedChapter: Decodable, Sendable {
        let uploadDate: String?
    }

    struct FetchedChapter: Decodable, Sendable {
        let fetchedAt: String?
    }

    struct ReadChapter: Decodable, Sendable {
        let lastReadAt: String?
    }

    struct Source: Decodable, Sendable {
        let displayName: String?
    }

    func intoManga(sourceKey: String, baseUrl: URL) -> AidokuRunner.Manga? {
        guard let id, let title else { return nil }

        let status: AidokuRunner.PublishingStatus = switch status {
            case "ONGOING": .ongoing
            case "COMPLETED", "PUBLISHING_FINISHED": .completed
            case "CANCELLED": .cancelled
            case "HIATUS": .hiatus
            default: .unknown
        }
        let urlString = realUrl ?? url

        return .init(
            sourceKey: sourceKey,
            key: "\(id)",
            title: title,
            cover: thumbnailUrl.flatMap { URL(string: $0, relativeTo: baseUrl)?.absoluteString },
            artists: artist.map { [$0] },
            authors: author.map { [$0] },
            description: description,
            url: urlString.flatMap { URL(string: $0, relativeTo: baseUrl) },
            tags: genre ?? [],
            status: status
        )
    }
}

extension Date {
    init?(suwayomiTimestamp: String) {
        guard let value = Double(suwayomiTimestamp) else { return nil }
        self.init(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
    }
}

// MARK: Tracking

struct SuwayomiTrackStateResponse: Decodable, Sendable {
    let data: DataContainer

    struct DataContainer: Decodable, Sendable {
        let manga: Manga
    }

    struct Manga: Decodable, Sendable {
        let chapters: ChapterConnection
        let latestReadChapter: Chapter?
        let highestNumberedChapter: Chapter?
    }

    struct ChapterConnection: Decodable, Sendable {
        let totalCount: Int?
    }

    struct Chapter: Decodable, Sendable {
        let chapterNumber: Float?
    }
}

struct SuwayomiTrackChaptersResponse: Decodable, Sendable {
    let data: DataContainer

    struct DataContainer: Decodable, Sendable {
        let chapters: ChapterConnection
    }

    struct ChapterConnection: Decodable, Sendable {
        let nodes: [Chapter]
    }

    struct Chapter: Decodable, Sendable {
        let id: Int
        let chapterNumber: Float?
    }
}

struct SuwayomiReadProgressResponse: Decodable, Sendable {
    let data: DataContainer

    struct DataContainer: Decodable, Sendable {
        let chapters: ChapterConnection
    }

    struct ChapterConnection: Decodable, Sendable {
        let nodes: [Chapter]
    }

    struct Chapter: Decodable, Sendable {
        let id: Int
        let isRead: Bool
        let lastPageRead: Int
        let lastReadAt: String
        let pageCount: Int
    }
}

struct SuwayomiChapterProgressPatch: Encodable, Sendable {
    var isRead: Bool?
    var lastPageRead: Int?
}

struct SuwayomiUpdateChapterResponse: Decodable, Sendable {
    let data: DataContainer?

    struct DataContainer: Decodable, Sendable {
        let updateChapter: Payload?
    }

    struct Payload: Decodable, Sendable {
        let chapter: Chapter?
    }

    struct Chapter: Decodable, Sendable {
        let id: Int
    }
}

struct SuwayomiUpdateChaptersResponse: Decodable, Sendable {
    let data: DataContainer?

    struct DataContainer: Decodable, Sendable {
        let updateChapters: Payload?
    }

    struct Payload: Decodable, Sendable {
        let chapters: [Chapter]
    }

    struct Chapter: Decodable, Sendable {
        let id: Int
    }
}
