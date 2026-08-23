//
//  MangaBakaModels.swift
//  Aidoku
//
//  Created by Skitty on 2/24/26.
//

import Foundation

struct MangaBakaResponse<T: Decodable>: Decodable {
    let status: Int
    let message: String?
    let data: T?
    let issues: [MangaBakaIssue]?
}

struct MangaBakaIssue: Decodable {
    let code: String
    let message: String?
}

enum MangaBakaStatus: String, Decodable {
    case cancelled
    case completed
    case hiatus
    case releasing
    case unknown
    case upcoming

    func into() -> PublishingStatus {
        switch self {
            case .cancelled: .cancelled
            case .completed: .completed
            case .hiatus: .hiatus
            case .releasing: .ongoing
            case .unknown: .unknown
            case .upcoming: .notPublished
        }
    }
}

enum MangaBakaType: String, Decodable {
    case manga
    case novel
    case manhwa
    case manhua
    case oel
    case other

    func into() -> MediaType {
        switch self {
            case .manga: .manga
            case .novel: .novel
            case .manhwa: .manhwa
            case .manhua: .manhua
            case .oel: .oel
            case .other: .unknown
        }
    }
}

enum MangaBakaContentRating: String, Decodable {
    case safe
    case suggestive
    case erotica
    case pornographic
}

struct MangaBakaSeries: Decodable {
    let id: Int
    let title: String
    let cover: Cover
    let description: String?
    let status: MangaBakaStatus
    let type: MangaBakaType

    let totalChapters: String?
    let finalVolume: String?

    struct Cover: Decodable {
        struct Raw: Decodable {
            let url: String?
        }
        let raw: Raw
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case cover
        case description
        case status
        case type
        case totalChapters = "total_chapters"
        case finalVolume = "final_volume"
    }
}

enum MangaBakaLibraryState: String, Codable {
    case considering
    case planToRead = "plan_to_read"
    case reading
    case completed
    case rereading
    case paused
    case dropped

    init(_ status: TrackStatus) {
        switch status {
            case .planning: self = .planToRead
            case .reading: self = .reading
            case .completed: self = .completed
            case .rereading: self = .rereading
            case .paused: self = .paused
            case .dropped: self = .dropped
            default: self = .reading
        }
    }

    func into() -> TrackStatus {
        switch self {
            case .considering: .planning
            case .planToRead: .planning
            case .reading: .reading
            case .completed: .completed
            case .rereading: .rereading
            case .paused: .paused
            case .dropped: .dropped
        }
    }
}

struct MangaBakaLibraryEntry: Codable {
    var id: Int?
    var seriesId: Int?
    var state: MangaBakaLibraryState?
    var rating: Int?
    var progressChapter: Int?
    var progressVolume: Int?
    var startDate: String?
    var finishDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case seriesId = "series_id"
        case state
        case rating
        case progressChapter = "progress_chapter"
        case progressVolume = "progress_volume"
        case startDate = "start_date"
        case finishDate = "finish_date"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.id, forKey: .id)
        try container.encodeIfPresent(self.seriesId, forKey: .seriesId)
        try container.encodeIfPresent(self.state, forKey: .state)
        try container.encodeIfPresent(self.rating, forKey: .rating)
        try container.encodeIfPresent(self.progressChapter, forKey: .progressChapter)
        try container.encodeIfPresent(self.progressVolume, forKey: .progressVolume)
        if let startDate {
            if startDate.hasPrefix("1969-12-31") || startDate.hasPrefix("1970-01-01") {
                try container.encodeNil(forKey: .startDate)
            } else {
                try container.encode(startDate, forKey: .startDate)
            }
        }
        if let finishDate {
            if finishDate.hasPrefix("1969-12-31") || finishDate.hasPrefix("1970-01-01") {
                try container.encodeNil(forKey: .startDate)
            } else {
                try container.encode(finishDate, forKey: .startDate)
            }
        }
    }
}
