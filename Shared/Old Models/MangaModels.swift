//
//  Manga.swift
//  Aidoku
//
//  Created by Skitty on 12/20/21.
//

import Foundation
import AidokuRunner

#if os(OSX)
    import AppKit
//    public typealias UIColor = NSColor
#else
    import UIKit
#endif

enum PublishingStatus: Int, Codable {
    case unknown = 0
    case ongoing = 1
    case completed = 2
    case cancelled = 3
    case hiatus = 4
    case notPublished = 5

    func toString() -> String {
        switch self {
        case .unknown: return NSLocalizedString("UNKNOWN", comment: "")
        case .ongoing: return NSLocalizedString("ONGOING", comment: "")
        case .completed: return NSLocalizedString("COMPLETED", comment: "")
        case .cancelled: return NSLocalizedString("CANCELLED", comment: "")
        case .hiatus: return NSLocalizedString("HIATUS", comment: "")
        case .notPublished: return NSLocalizedString("NOT_PUBLISHED", comment: "")
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
        case .unknown: return NSLocalizedString("UNKNOWN", comment: "")
        case .manga: return NSLocalizedString("MANGA", comment: "")
        case .manhwa: return NSLocalizedString("MANHWA", comment: "")
        case .manhua: return NSLocalizedString("MANHUA", comment: "")
        case .novel: return NSLocalizedString("LIGHT_NOVEL", comment: "")
        case .oneShot: return NSLocalizedString("ONESHOT", comment: "")
        case .oel: return NSLocalizedString("OEL", comment: "")
        case .comic: return NSLocalizedString("COMIC", comment: "")
        case .book: return NSLocalizedString("BOOK", comment: "") // not really handled yet
        }
    }
}

enum MangaContentRating: Int, Codable {
    case safe = 0
    case suggestive = 1
    case nsfw = 2

    func toNew() -> AidokuRunner.ContentRating {
        switch self {
            case .safe: .safe
            case .suggestive: .suggestive
            case .nsfw: .nsfw
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
