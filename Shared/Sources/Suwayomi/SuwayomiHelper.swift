//
//  SuwayomiHelper.swift
//  Aidoku
//
//  Created by skitty on 7/7/26.
//

import AidokuRunner
import Foundation

struct SuwayomiHelper: Sendable {
    let sourceKey: String

    func authorize(request: inout URLRequest) {
        if let cookie = UserDefaults.standard.string(forKey: "\(sourceKey).cookie") {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        } else if let token = UserDefaults.standard.string(forKey: "\(sourceKey).token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if
            let username = UserDefaults.standard.string(forKey: "\(sourceKey).login.username"),
            let password = UserDefaults.standard.string(forKey: "\(sourceKey).login.password")
        {
            let auth = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        }
    }

    func getConfiguredServer() throws(SourceError) -> URL {
        guard let server = UserDefaults.standard.string(forKey: "\(sourceKey).server")?.urlWithTrailingSlash() else {
            throw SourceError.message("NO_SERVER_CONFIGURED")
        }
        return server
    }

    func request<T: Decodable & Sendable, U: Encodable>(body: U) async throws -> T {
        let data = try await graphqlData(body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func graphqlData<U: Encodable>(body: U, retryOnUnauthorized: Bool = true) async throws -> Data {
        guard let url = URL(string: "api/graphql", relativeTo: try getConfiguredServer()) else {
            throw SourceError.message("INVALID_SERVER_URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(request: &request)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw SourceError.networkError
        }
        if Self.hasUnauthorizedError(data) {
            guard retryOnUnauthorized, await recoverAuthentication() else {
                throw SourceError.message("NOT_LOGGED_IN")
            }
            return try await graphqlData(body: body, retryOnUnauthorized: false)
        }
        return data
    }

    private static func hasUnauthorizedError(_ data: Data) -> Bool {
        guard let response = try? JSONDecoder().decode(SuwayomiGraphQLErrorResponse.self, from: data) else {
            return false
        }
        return response.errors.contains {
            $0.message.localizedCaseInsensitiveContains("Unauthorized")
        }
    }

    private func recoverAuthentication() async -> Bool {
        if
            UserDefaults.standard.string(forKey: "\(sourceKey).cookie") != nil,
            UserDefaults.standard.string(forKey: "\(sourceKey).refreshToken") == nil
        {
            return await refreshCookie()
        }
        return await refreshToken()
    }

    private func refreshCookie() async -> Bool {
        guard
            let serverUrl = try? getConfiguredServer(),
            let loginUrl = URL(string: "login.html", relativeTo: serverUrl),
            let username = UserDefaults.standard.string(forKey: "\(sourceKey).login.username"),
            let password = UserDefaults.standard.string(forKey: "\(sourceKey).login.password")
        else {
            return false
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "user", value: username),
            URLQueryItem(name: "pass", value: password)
        ]

        var request = URLRequest(url: loginUrl)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        guard
            let (_, response) = try? await URLSession(
                configuration: .ephemeral,
                delegate: NoRedirectDelegate(),
                delegateQueue: nil
            ).data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            (200..<400).contains(httpResponse.statusCode)
        else {
            return false
        }

        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: httpResponse.allHeaderFields as? [String: String] ?? [:],
            for: loginUrl
        )
        guard let cookie = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] else {
            return false
        }

        UserDefaults.standard.setValue(cookie, forKey: "\(sourceKey).cookie")
        return true
    }

    private func refreshToken() async -> Bool {
        guard let refreshToken = UserDefaults.standard.string(forKey: "\(sourceKey).refreshToken") else {
            return false
        }

        struct Payload: Encodable {
            let operationName = "USER_REFRESH"
            let variables: Variables
            let query = """
                mutation USER_REFRESH($refreshToken: String!) {
                  refreshToken(input: {refreshToken: $refreshToken}) {
                    accessToken
                    __typename
                  }
                }
                """

            struct Variables: Encodable {
                let refreshToken: String
            }
        }

        guard
            let data = try? await graphqlData(
                body: Payload(variables: .init(refreshToken: refreshToken)),
                retryOnUnauthorized: false
            ),
            let response = try? JSONDecoder().decode(SuwayomiRefreshResponse.self, from: data),
            let accessToken = response.data?.refreshToken.accessToken
        else {
            return false
        }

        UserDefaults.standard.setValue(accessToken, forKey: "\(sourceKey).token")
        return true
    }
}

// MARK: Login
extension SuwayomiHelper {
    enum LoginType {
        case none
        case basic
        case simple
        case ui
    }

    func getLoginType() async throws(SourceError) -> LoginType? {
        let server = try getConfiguredServer()
        return await Self.getLoginType(server: server)
    }

    static func getLoginType(server: URL) async -> LoginType? {
        var request = URLRequest(url: server)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let response = await send(request, followRedirects: false).response else {
            return nil
        }

        if (200..<300).contains(response.statusCode) {
            guard let graphqlUrl = URL(string: "api/graphql", relativeTo: server) else {
                return nil
            }
            struct Payload: Encodable {
                let operationName = "AUTH_MODE"
                let query = """
                    query AUTH_MODE {
                      settings {
                        authMode
                      }
                    }
                    """
            }

            struct Response: Decodable {
                let data: DataContainer?

                struct DataContainer: Decodable {
                    let settings: Settings?
                }

                struct Settings: Decodable {
                    let authMode: String?
                }
            }

            var request = URLRequest(url: graphqlUrl)
            request.httpMethod = "POST"
            request.httpBody = try? JSONEncoder().encode(Payload())
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            guard let data = await send(request).data else {
                return nil
            }

            if let authMode = try? JSONDecoder().decode(Response.self, from: data).data?.settings?.authMode, authMode == "NONE" {
                return LoginType.none
            } else if hasUnauthorizedError(data) {
                return .ui
            }
        }

        if response.statusCode == 401 {
            return .basic
        }

        if
            (300..<400).contains(response.statusCode),
            let location = response.value(forHTTPHeaderField: "Location"),
            location.contains("/login.html"
        ) {
            return .simple
        }

        return nil
    }

    struct LoginCheck {
        let cookie: String?
        let accessToken: String?
        let refreshToken: String?
    }

    static func checkLogin(server: URL, username: String, password: String) async -> LoginCheck? {
        guard let loginType = await SuwayomiHelper.getLoginType(server: server) else {
            return nil
        }

        switch loginType {
            case .none:
                return .init(cookie: nil, accessToken: nil, refreshToken: nil)
            case .basic:
                return await checkBasicLogin(server: server, username: username, password: password)
            case .simple:
                return await checkSimpleLogin(server: server, username: username, password: password)
            case .ui:
                return await checkUILogin(server: server, username: username, password: password)
        }
    }

    private static func checkBasicLogin(server: URL, username: String, password: String) async -> LoginCheck? {
        var request = URLRequest(url: server)
        let auth = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let response = await send(request).response, (200..<300).contains(response.statusCode) else {
            return nil
        }

        return .init(cookie: nil, accessToken: nil, refreshToken: nil)
    }

    private static func checkSimpleLogin(server: URL, username: String, password: String) async -> LoginCheck? {
        guard let loginUrl = URL(string: "login.html", relativeTo: server) else {
            return nil
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "user", value: username),
            URLQueryItem(name: "password", value: password)
        ]

        var request = URLRequest(url: loginUrl)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let result = await send(request, followRedirects: false)
        guard
            let response = result.response,
            (200..<400).contains(response.statusCode),
            let cookie = result.cookie
        else {
            return nil
        }

        return .init(cookie: cookie, accessToken: nil, refreshToken: nil)
    }

    private static func checkUILogin(server: URL, username: String, password: String) async -> LoginCheck? {
        guard let loginUrl = URL(string: "api/graphql", relativeTo: server) else {
            return nil
        }

        struct Payload: Encodable {
            let operationName = "USER_LOGIN"
            let variables: Variables
            let query = """
                mutation USER_LOGIN($password: String!, $username: String!) {
                  login(input: {password: $password, username: $username}) {
                    accessToken
                    refreshToken
                    __typename
                  }
                }
                """

            struct Variables: Encodable {
                let username: String
                let password: String
            }
        }

        struct Response: Decodable {
            let data: DataContainer?

            struct DataContainer: Decodable {
                let login: Login?
            }

            struct Login: Decodable {
                let accessToken: String?
                let refreshToken: String?
            }
        }

        var request = URLRequest(url: loginUrl)
        request.httpMethod = "POST"
        request.httpBody = try? JSONEncoder().encode(Payload(variables: .init(username: username, password: password)))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard
            let data = await send(request).data,
            let login = try? JSONDecoder().decode(Response.self, from: data).data?.login,
            let accessToken = login.accessToken,
            let refreshToken = login.refreshToken
        else {
            return nil
        }

        return .init(cookie: nil, accessToken: accessToken, refreshToken: refreshToken)
    }

    private struct SuwayomiResponse {
        var data: Data?
        var response: HTTPURLResponse?
        var cookie: String?
    }

    private static func send(_ request: URLRequest, followRedirects: Bool = true) async -> SuwayomiResponse {
        let session = if followRedirects {
            URLSession.shared
        } else {
            URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)
        }

        guard
            let (data, response) = try? await session.data(for: request),
            let httpResponse = response as? HTTPURLResponse
        else {
            return .init()
        }

        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: httpResponse.allHeaderFields as? [String: String] ?? [:],
            for: request.url ?? httpResponse.url ?? URL(fileURLWithPath: "/")
        )
        let cookie = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]

        return .init(data: data, response: httpResponse, cookie: cookie)
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
