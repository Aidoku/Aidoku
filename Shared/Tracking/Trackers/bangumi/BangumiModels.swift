//
//  BangumiModels.swift
//  Aidoku
//
//  Created by dyphire on 22/9/2025.
//

import Foundation

// MARK: - Search Response
struct BangumiSearchResponse: Codable {
    var data: [BangumiSubject]?
    var total: Int?
    var limit: Int?
    var offset: Int?

    // For backward compatibility with old API
    var results: Int?
    var list: [BangumiSubject]?

    var subjects: [BangumiSubject]? {
        data ?? list
    }
}

// MARK: - Subject
struct BangumiSubject: Codable {
    var id: Int
    var type: Int // 1: Book, 2: Anime, 3: Music, 4: Game, 6: Real
    var name: String?
    var name_cn: String?
    var summary: String?
    var nsfw: Bool?
    var date: String?
    var air_date: String?
    var air_weekday: String?
    var platform: String?
    var series: Bool?
    var images: BangumiImages?
    var volumes: Int?
    var eps: Int?
    var total_episodes: Int?
    var rating: BangumiRating?
}

struct BangumiImages: Codable {
    var large: String?
    var common: String?
    var medium: String?
    var small: String?
    var grid: String?
}

struct BangumiRating: Codable {
    var rank: Int
    var total: Int
    var count: BangumiRatingCount?
    var score: Float
}

struct BangumiRatingCount: Codable {
    var `1`: Int
    var `2`: Int
    var `3`: Int
    var `4`: Int
    var `5`: Int
    var `6`: Int
    var `7`: Int
    var `8`: Int
    var `9`: Int
    var `10`: Int
}

// MARK: - Collection
struct BangumiCollection: Codable {
    var subject_id: Int
    var subject_type: Int
    var type: Int // 1: wish, 2: collect, 3: do, 4: on_hold, 5: dropped
    var rate: Int?
    var ep_status: Int?
    var vol_status: Int?
    var updated_at: String?
    var `private`: Bool?
    var comment: String?
    var tags: [String]?

    // Computed properties for easier access
    var collect: String? {
        switch type {
        case 1: return "wish"
        case 2: return "collect"
        case 3: return "do"
        case 4: return "on_hold"
        case 5: return "dropped"
        default: return nil
        }
    }

    var rating: Int? {
        rate
    }
}

enum BangumiCollectionStatus: Int, Codable {
    case wish = 1
    case collect = 2
    case doing = 3
    case on_hold = 4
    case dropped = 5
}

// MARK: - User
struct BangumiUser: Codable {
    var id: Int
    var username: String
    var nickname: String?
    var sign: String?
    var avatar: BangumiImages?
}

// MARK: - Collection Update
struct BangumiCollectionUpdate: Codable {
    var type: BangumiCollectionStatus?
    var rate: Int?
    var comment: String?
    var tags: [String]?
    var vol_status: Int?
    var ep_status: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case rate
        case comment
        case tags
        case vol_status
        case ep_status
    }
}
