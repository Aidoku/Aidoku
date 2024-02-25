//
//  OAuthResponse.swift
//  Aidoku
//
//  Created by Skitty on 7/22/22.
//

import Foundation

struct OAuthResponse {
    var tokenType: String?
    var refreshToken: String?
    var accessToken: String?
    var expiresIn: Int?
    var createdAt: Date = Date()

    // indicates if we've alerted the user that they need to re-login
    var askedForRefresh = false

    var expired: Bool {
        Date() > createdAt + TimeInterval(expiresIn ?? 0)
    }
}

extension OAuthResponse: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        askedForRefresh = try container.decodeIfPresent(Bool.self, forKey: .askedForRefresh) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case accessToken = "access_token"
        case expiresIn = "expires_in"

        case askedForRefresh = "asked_for_refresh"
    }
}
