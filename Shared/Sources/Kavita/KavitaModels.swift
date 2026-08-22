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
        baseUrl: URL,
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
            cover: URL(string: "api/image/series-cover?seriesId=\(id)&apiKey=\(apiKey)", relativeTo: baseUrl)?.absoluteString,
            artists: metadata?.pencillers.map { $0.name },
            authors: metadata?.writers.map { $0.name },
            description: metadata?.summary,
            url: URL(string: "library/\(libraryId)/series/\(id)", relativeTo: baseUrl),
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
        let titleName: String?
        let createdUtc: Date
        let language: String?
        let pages: Int
        let pagesRead: Int
        let lastReadingProgressUtc: Date
        let files: [File]

        var isEpub: Bool {
            files.contains { $0.format == 3 }
        }
    }

    let id: Int
    let name: String
    let number: Int
    let minNumber: Float?
    let seriesId: Int
    let chapters: [Chapter]

    /// The volume number; the legacy `number` field truncates fractional
    /// volumes (e.g. 9.5 -> 9), so prefer `minNumber` where available.
    var resolvedNumber: Float {
        minNumber ?? Float(number)
    }
}

/// An entry of an epub's table of contents, from `api/book/{chapterId}/chapters`.
struct KavitaBookChapterItem: Codable, Sendable {
    let title: String
    let page: Int
    let children: [KavitaBookChapterItem]?
}

extension KavitaVolume {
    /// `epubTocs` maps epub chapter ids to their table of contents; epub
    /// chapters without an entry are dropped (their toc failed to load).
    func intoChapters(baseUrl: URL, apiKey: String, epubTocs: [Int: [KavitaBookChapterItem]] = [:]) -> [AidokuRunner.Chapter] {
        chapters.flatMap { chapter -> [AidokuRunner.Chapter] in
            if chapter.isEpub {
                guard let toc = epubTocs[chapter.id] else { return [] }
                return chapter.intoEpubChapters(volume: self, toc: toc, baseUrl: baseUrl, apiKey: apiKey)
            }
            let chapterNumber = Float(chapter.number) ?? 0
            let noVolume = resolvedNumber < 0 || resolvedNumber >= 100000
            let noChapter = chapterNumber < 0 || chapterNumber >= 100000
            return [.init(
                key: "\(chapter.id)",
                title: (chapter.titleName?.isEmpty ?? true) ? nil : chapter.titleName,
                chapterNumber: noChapter ? nil : chapterNumber,
                volumeNumber: noVolume ? nil : resolvedNumber,
                dateUploaded: chapter.createdUtc,
                url: URL(string: "library/1/series/\(seriesId)/chapter/\(chapter.id)", relativeTo: baseUrl),
                language: chapter.language,
                thumbnail: URL(
                    string: "api/image/chapter-cover?chapterId=\(chapter.id)&apiKey=\(apiKey)",
                    relativeTo: baseUrl
                )?.absoluteString
            )]
        }
    }
}

extension KavitaVolume.Chapter {
    /// Chapters for an epub, one per logical epub chapter, grouping the spine
    /// pages by their toc titles like local epubs. The chapter key has the
    /// format "<kavita chapter id>/<first spine page>-<end spine page>".
    func intoEpubChapters(
        volume: KavitaVolume,
        toc: [KavitaBookChapterItem],
        baseUrl: URL,
        apiKey: String
    ) -> [AidokuRunner.Chapter] {
        // first toc title per spine page
        var titles: [Int: String] = [:]
        var items = toc
        var index = 0
        while index < items.count {
            let item = items[index]
            if titles[item.page] == nil, !item.title.isEmpty {
                titles[item.page] = item.title
            }
            items.append(contentsOf: item.children ?? [])
            index += 1
        }

        // spine pages with a toc title start a new chapter, untitled pages are
        // grouped into the preceding one; without a toc, every page is its own chapter
        var groups: [(start: Int, title: String?)] = []
        for page in 0..<pages {
            let title = titles[page]
            if titles.isEmpty || title != nil || groups.isEmpty {
                groups.append((page, title))
            }
        }

        let noVolume = volume.resolvedNumber < 0 || volume.resolvedNumber >= 100000
        return groups.enumerated().map { index, group in
            let end = index + 1 < groups.count ? groups[index + 1].start : pages
            return .init(
                key: "\(id)/\(group.start)-\(end)",
                title: group.title,
                chapterNumber: Float(index + 1),
                volumeNumber: noVolume ? nil : volume.resolvedNumber,
                dateUploaded: createdUtc,
                url: URL(string: "library/1/series/\(volume.seriesId)/chapter/\(id)", relativeTo: baseUrl),
                language: language,
                thumbnail: URL(
                    string: "api/image/chapter-cover?chapterId=\(id)&apiKey=\(apiKey)",
                    relativeTo: baseUrl
                )?.absoluteString
            )
        }
    }
}
