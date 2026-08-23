//
//  OAuthClient.swift
//  Aidoku
//
//  Created by Koding Dev on 19/7/2022.
//

import Foundation
import CryptoKit

#if canImport(UIKit)
import UIKit
#endif

actor OAuthClient {
    let id: String
    let clientId: String
    let clientSecret: String?
    let baseUrl: String
    let challengeMethod: OAuthCodeChallengeMethod

    enum OAuthCodeChallengeMethod: String {
        case none
        case plain
        case s256 = "S256"
    }

    var codeVerifier = ""
    var tokens: OAuthResponse?

    init(
        id: String,
        clientId: String,
        clientSecret: String? = nil,
        baseUrl: String,
        challengeMethod: OAuthCodeChallengeMethod = .plain
    ) {
        self.id = id
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.baseUrl = baseUrl
        self.challengeMethod = challengeMethod
    }

    func getAuthenticationUrl(
        responseType: String = "code",
        path: String = "/authorize",
        redirectUri: String? = nil,
        extraQueryItems: [String: String]? = nil
    ) -> URL? {
        guard let url = URL(string: baseUrl + path) else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: responseType)
        ]
        if let redirectUri {
            queryItems.append(URLQueryItem(name: "redirect_uri", value: redirectUri))
        }
        if challengeMethod != .none {
            queryItems.append(URLQueryItem(name: "code_challenge", value: generatePkceChallenge(method: challengeMethod)))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: challengeMethod.rawValue))
        }
        if let extraQueryItems {
            for (key, value) in extraQueryItems {
                queryItems.append(URLQueryItem(name: key, value: value))
            }
        }
        components?.queryItems = queryItems
        return components?.url
    }
}

// MARK: - Tokens
extension OAuthClient {
    func getAccessToken(authCode: String, redirectUri: String? = nil) async -> OAuthResponse? {
        guard let url = URL(string: baseUrl + "/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        var body = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": authCode
        ]
        if challengeMethod != .none {
            body["code_verifier"] = codeVerifier
        }
        if let redirectUri {
            body["redirect_uri"] = redirectUri
        }
        request.httpBody = body.percentEncoded()
        tokens = try? await URLSession.shared.object(from: request)
        return tokens
    }

//    func refreshAccessToken(refreshToken: String) async -> OAuthResponse? {
//        guard let url = URL(string: baseUrl + "/token") else { return nil }
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.httpBody = [
//            "grant_type": "refresh_token",
//            "refresh_token": refreshToken
//        ].percentEncoded()
//        tokens = try? await URLSession.shared.object(from: request)
//        return tokens
//    }

    func loadTokens() {
        if let data = UserDefaults.standard.data(forKey: "Tracker.\(id).oauth") {
            tokens = (try? JSONDecoder().decode(OAuthResponse.self, from: data)) ?? OAuthResponse()
        } else {
            tokens = OAuthResponse()
        }
    }

    func saveTokens() {
        UserDefaults.standard.set(try? JSONEncoder().encode(tokens), forKey: "Tracker.\(id).oauth")
    }

    func setTokens(_ response: OAuthResponse?) {
        tokens = response
        saveTokens()
    }

    func authorizedRequest(for url: URL, additionalHeaders: [String: String]? = nil) -> URLRequest {
        if tokens == nil { loadTokens() }

        var request = URLRequest(url: url)
        request.addValue(
            "\(tokens?.tokenType ?? "Bearer") \(tokens?.accessToken ?? "")",
            forHTTPHeaderField: "Authorization"
        )

        // Add any additional headers
        if let additionalHeaders {
            for (key, value) in additionalHeaders {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }
}

// MARK: - PKCE
extension OAuthClient {
    func generatePkceVerifier() -> String {
        var octets = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, octets.count, &octets) == errSecSuccess else {
            return ""
        }
        codeVerifier = base64(octets)
        return codeVerifier
    }

    func generatePkceChallenge(method: OAuthCodeChallengeMethod) -> String {
        switch method {
            case .plain:
                return generatePkceVerifier()
            case .s256:
                return generatePkceVerifier()
                   .data(using: .ascii)
                   .map { SHA256.hash(data: $0) }
                   .map { base64($0) } ?? ""
            case .none:
                return ""
        }
    }

    private func base64<S>(_ octets: S) -> String where S: Sequence, UInt8 == S.Element {
        let data = Data(octets)
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespaces)
    }
}

extension OAuthClient {
    func checkIfReloginNeeded(trackerName: String) async -> Bool {
        if tokens == nil {
            loadTokens()
        }
        guard tokens?.refreshToken != nil else {
            await showReloginAlert(trackerName: trackerName)
            return true
        }
        return false
    }

    func showReloginAlert(trackerName: String) async {
        if tokens == nil {
            loadTokens()
        }
        guard var tokens else { return }
        if !tokens.askedForRefresh {
            tokens.askedForRefresh = true
            setTokens(tokens)
#if !os(macOS)
            await MainActor.run {
                (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
                    title: String(format: NSLocalizedString("%@_TRACKER_LOGIN_NEEDED"), trackerName),
                    message: String(format: NSLocalizedString("%@_TRACKER_LOGIN_NEEDED_TEXT"), trackerName)
                )
            }
#endif
        }
    }
}
