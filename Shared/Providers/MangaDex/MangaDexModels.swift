//
//  MangaDexModels.swift
//  Aidoku
//
//  Created by Skitty on 12/24/21.
//

import Foundation

// TODO: use Locale
struct MangaLocalizedString: Codable {
    let translations: [String: String]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        var strings: [String: String] = [:]
        if let x = try? container.decode([String: String].self) {
            strings = x
        }

        translations = strings
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(translations)
    }
}

struct MDAuthor: Codable {
    let name: String?
    let imageUrl: String?
}

struct MDCover: Codable {
    let volume: String?
    let fileName: String
}

struct MDTag: Codable {
    let name: MangaLocalizedString
    let description: MangaLocalizedString?
    let version: Int
}

struct MDManga: Codable {
    let title: MangaLocalizedString
    let description: MangaLocalizedString?
    let status: String
    let contentRating: String
    let tags: [MDObject<MDTag>]
    let state: String
    let version: Int
}

struct MDChapter: Codable {
    let volume: String?
    let chapter: String?
    let title: String?
    let translatedLanguage: String?
    let hash: String
    let data: [String]
    let uploader: String?
    let externalUrl: String?
}

struct MDRelationship: Codable {
    let id: String
    let type: String
}

struct MDObject<T: Codable>: Codable {
    let id: String
    let type: String
    let attributes: T
    let relationships: [MDRelationship]
}

struct MDError: Codable {
    let id: String
    let status: Int
    let title: String
    let detail: String
}

struct MDResponse<T: Codable>: Codable {
    let result: String // ok or error
    let response: String // entity or collection
    let data: T?
    let errors: [MDError]?
}

struct MDLimitedResponse<T: Codable>: Codable {
    let result: String
    let response: String
    let data: [T]?
    let errors: [MDError]?
    let limit: Int
    let offset: Int
    let total: Int
}

struct MDAtHomeChapter: Codable {
    let hash: String
    let data: [String]
}

struct MDAtHomeResponse: Codable {
    let result: String
    let baseUrl: String?
    let errors: [MDError]?
    let chapter: MDAtHomeChapter?
}
