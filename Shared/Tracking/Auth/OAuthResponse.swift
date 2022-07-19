//
//  OAuthResponse.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation

struct OAuthResponse: Codable {
    var tokenType: String?
    var refreshToken: String?
    var accessToken: String?
    var expiresIn: Int?
    var createdAt: Date = Date()

    init(tokenType: String? = nil, refreshToken: String? = nil, accessToken: String? = nil, expiresIn: Int? = nil, createdAt: Date = Date()) {
        self.tokenType = tokenType
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.createdAt = createdAt
    }

    var expired: Bool {
        Date() > createdAt + TimeInterval(expiresIn ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}
