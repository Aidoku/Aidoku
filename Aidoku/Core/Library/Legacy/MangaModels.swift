//
//  Manga.swift
//  Aidoku
//
//  Created by Skitty on 12/20/21.
//

import AidokuRunner
import Foundation

enum PublishingStatus: Int, Codable {
    case unknown = 0
    case ongoing = 1
    case completed = 2
    case cancelled = 3
    case hiatus = 4
    case notPublished = 5

    func toString() -> String {
        switch self {
            case .unknown: return NSLocalizedString("UNKNOWN")
            case .ongoing: return NSLocalizedString("STATUS_ONGOING")
            case .completed: return NSLocalizedString("STATUS_COMPLETED")
            case .cancelled: return NSLocalizedString("STATUS_CANCELLED")
            case .hiatus: return NSLocalizedString("STATUS_HIATUS")
            case .notPublished: return NSLocalizedString("STATUS_NOT_PUBLISHED")
        }
    }

    func toNew() -> AidokuRunner.PublishingStatus {
        switch self {
            case .unknown: .unknown
            case .ongoing: .ongoing
            case .completed: .completed
            case .cancelled: .cancelled
            case .hiatus: .hiatus
            case .notPublished: .unknown
        }
    }
}

enum MediaType: Int, Codable {
    case unknown = 0
    case manga = 1
    case manhwa = 2
    case manhua = 3
    case novel = 4
    case oneShot = 5
    case oel = 6
    case comic = 7
    case book = 8

    func toString() -> String {
        switch self {
            case .unknown: return NSLocalizedString("UNKNOWN")
            case .manga: return NSLocalizedString("MANGA")
            case .manhwa: return NSLocalizedString("MANHWA")
            case .manhua: return NSLocalizedString("MANHUA")
            case .novel: return NSLocalizedString("LIGHT_NOVEL")
            case .oneShot: return NSLocalizedString("ONESHOT")
            case .oel: return NSLocalizedString("OEL")
            case .comic: return NSLocalizedString("COMIC")
            case .book: return NSLocalizedString("BOOK") // not really handled yet
        }
    }
}

enum MangaContentRating: Int, Codable, CaseIterable {
    case safe = 0
    case suggestive = 1
    case nsfw = 2

    init?(stringValue: String) {
        switch stringValue {
            case "safe": self = .safe
            case "suggestive": self = .suggestive
            case "nsfw": self = .nsfw
            default: return nil
        }
    }

    func toNew() -> AidokuRunner.ContentRating {
        switch self {
            case .safe: .safe
            case .suggestive: .suggestive
            case .nsfw: .nsfw
        }
    }

    var title: String {
        toNew().title
    }

    var stringValue: String {
        switch self {
            case .safe: "safe"
            case .suggestive: "suggestive"
            case .nsfw: "nsfw"
        }
    }
}

enum MangaViewer: Int, Codable {
    case defaultViewer = 0
    case rtl = 1
    case ltr = 2
    case vertical = 3
    case scroll = 4

    func toNew() -> AidokuRunner.Viewer {
        switch self {
            case .defaultViewer: .unknown
            case .ltr: .leftToRight
            case .rtl: .rightToLeft
            case .vertical: .vertical
            case .scroll: .webtoon
        }
    }
}

struct MangaPageResult {
    let manga: [Manga]
    let hasNextPage: Bool

    func toNew() -> AidokuRunner.MangaPageResult {
        AidokuRunner.MangaPageResult(entries: manga.map { $0.toNew() }, hasNextPage: hasNextPage)
    }
}
