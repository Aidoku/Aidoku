//
//  Manga.swift
//  Aidoku
//
//  Created by Skitty on 12/20/21.
//

import Foundation

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
}

enum MangaViewer: Int, Codable {
    case defaultViewer = 0
    case rtl = 1
    case ltr = 2
    case vertical = 3
    case scroll = 4
}

struct CodableColor {
    var color: UIColor
}

extension CodableColor: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        guard let newColor = try NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid color"
            )
        }
        color = newColor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let data = try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
        try container.encode(data)
    }
}

struct MangaPageResult {
    let manga: [Manga]
    let hasNextPage: Bool
}
