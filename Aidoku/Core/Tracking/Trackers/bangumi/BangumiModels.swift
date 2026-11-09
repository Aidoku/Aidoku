//
//  BangumiModels.swift
//  Aidoku
//
//  Created by dyphire on 22/9/2025.
//

import Foundation

// MARK: - Search Request
struct BangumiSearchRequest: Encodable {
    struct Filter: Encodable {
        var type: [Int]
        var nsfw: Bool
    }
    var keyword: String
    var sort: String
    var filter: Filter
}

// MARK: - Search Response
struct BangumiSearchResponse: Decodable {
    var data: [BangumiSubject]?
    var total: Int?
    var limit: Int?
    var offset: Int?
}

// MARK: - Subject
struct BangumiSubject: Decodable {
    var id: Int
    var type: Int? // 1: Book, 2: Anime, 3: Music, 4: Game, 6: Real
    var name: String?
    var nameCN: String?
    var summary: String?
    var info: String?
    var nsfw: Bool?
    var date: String?
    var platform: BangumiPlatform?
    var series: Bool?
    var images: BangumiImages?
    var volumes: Int?
    var eps: Int?
    /// The current user's collection state, embedded in search and detail responses.
    var interest: BangumiInterest?
}

struct BangumiPlatform: Decodable {
    /// Carrier label for book subjects: "漫画"/"小说"/"轻小说"/"画集"...
    var typeCN: String?
}

struct BangumiImages: Codable {
    var large: String?
    var common: String?
    var medium: String?
    var small: String?
    var grid: String?
}

// MARK: - Interest (embedded collection state)
struct BangumiInterest: Decodable {
    var type: Int? // 1: wish, 2: collect, 3: do, 4: on_hold, 5: dropped
    var rate: Int?
    var epStatus: Int?
    var volStatus: Int?
}

enum BangumiCollectionStatus: Int, Codable {
    case wish = 1
    case collect = 2
    case doing = 3
    case onHold = 4
    case dropped = 5
}

// MARK: - Update bodies
/// PUT body: status and score, which must always be sent together.
struct BangumiCollectionPut: Encodable {
    var type: Int
    var rate: Int
}

/// PATCH body: reading progress.
struct BangumiProgressPatch: Encodable {
    var epStatus: Int?
    var volStatus: Int?
}
