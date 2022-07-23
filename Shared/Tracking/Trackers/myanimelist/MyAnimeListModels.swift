//
//  MyAnimeListModels.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation

// https://myanimelist.net/apiconfig/references/api/v2/

struct MyAnimeListSearchResponse: Codable {
    var data: [MyAnimeListMangaNode]
}

struct MyAnimeListMangaNode: Codable {
    var node: MyAnimeListManga
}

struct MyAnimeListMangaPicture: Codable {
    var medium: String?
    var large: String?
}

struct MyAnimeListMangaStatus: Codable {
    var isRereading: Bool?
    var numVolumesRead: Int?
    var numChaptersRead: Int?
    var startDate: String?
    var finishDate: String?
    var updatedAt: String?
    var status: String?
    var score: Int?
    var comments: String?

    enum CodingKeys: String, CodingKey {
        case isRereading = "is_rereading"
        case numVolumesRead = "num_volumes_read"
        case numChaptersRead = "num_chapters_read"
        case startDate = "start_date"
        case finishDate = "finish_date"
        case updatedAt = "updated_at"
        case status
        case score
        case comments
    }

    func percentEncoded() -> Data? {
        var params: [String] = []
        if let isRereading = isRereading { params.append("is_rereading=\(isRereading)") }
        if let numVolumesRead = numVolumesRead { params.append("num_volumes_read=\(numVolumesRead)") }
        if let numChaptersRead = numChaptersRead { params.append("num_chapters_read=\(numChaptersRead)") }
        if let startDate = startDate {
            if startDate == Date(timeIntervalSince1970: 0).ISO8601Format() {
                params.append("start_date=null")
            } else {
                params.append("start_date=\(startDate)")
            }
        }
        if let finishDate = finishDate {
            if finishDate == Date(timeIntervalSince1970: 0).ISO8601Format() {
                params.append("finish_date=null")
            } else {
                params.append("finish_date=\(finishDate)")
            }
        }
        if let score = finishDate { params.append("score=\(score)") }
        return params
            .joined(separator: "&")
            .data(using: .utf8)
    }
}

struct MyAnimeListManga: Codable {
    var id: Int
    var title: String?
    var synopsis: String?
    var mainPicture: MyAnimeListMangaPicture?
    var numVolumes: Int?
    var numChapters: Int?
    var status: String?
    var mediaType: String?
    var startDate: String?
    var myListStatus: MyAnimeListMangaStatus?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case synopsis
        case mainPicture = "main_picture"
        case numVolumes = "num_volumes"
        case numChapters = "num_chapters"
        case status
        case mediaType = "media_type"
        case startDate = "start_date"
        case myListStatus = "my_list_status"
    }
}
