//
//  KavitaHelper.swift
//  Aidoku
//
//  Created by Skitty on 10/19/25.
//

import AidokuRunner
import Foundation

struct KavitaHelper: Sendable {
    let sourceKey: String

    func getApiKey() -> String {
        UserDefaults.standard.string(forKey: "\(sourceKey).apiKey") ?? ""
    }

    func authorize(request: inout URLRequest) -> Bool {
        if let token = UserDefaults.standard.string(forKey: "\(sourceKey).token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return true
        } else if let cookie = UserDefaults.standard.string(forKey: "\(sourceKey).cookie") {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            return true
        } else {
            return false
        }
    }

    func getConfiguredServer() throws(SourceError) -> String {
        guard var server = UserDefaults.standard.string(forKey: "\(sourceKey).server") else {
            throw SourceError.message("NO_SERVER_CONFIGURED")
        }
        if server.last == "/" {
            server.removeLast()
        }
        return server
    }

    func getServerUrl(path: String) throws(SourceError) -> URL {
        let baseUrl = try getConfiguredServer()
        guard let serverUrl = URL(string: "\(baseUrl)\(path)") else {
            throw SourceError.message("INVALID_SERVER_URL")
        }
        return serverUrl
    }

    func request<T: Decodable>(
        path: String,
        method: HttpMethod = .GET,
        body: Data? = nil,
    ) async throws(SourceError) -> T {
        func doRequest() async throws(SourceError) -> T? {

            let url = try getServerUrl(path: path)
            var request = URLRequest(url: url)
            guard authorize(request: &request) else {
                throw SourceError.message("NOT_LOGGED_IN")
            }
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = method.stringValue
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let result = try? await URLSession.shared.data(for: request)
            guard
                let data = result?.0,
                let response = result?.1 as? HTTPURLResponse
            else {
                throw SourceError.networkError
            }
            if response.statusCode == 401 {
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom({ decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                let formatter = DateFormatter()
                formatter.timeZone = if #available(iOS 16.0, *) {
                    .gmt
                } else {
                    .init(secondsFromGMT: 0)
                }
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
                var date = formatter.date(from: string)
                if date == nil {
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    date = formatter.date(from: string)
                }
                return date ?? .distantPast
            })
            if let result = try? decoder.decode(T.self, from: data) as T? {
                return result
            } else if let error = try? decoder.decode(KavitaErrorResponse.self, from: data) {
                throw SourceError.message(error.title)
            } else {
                throw SourceError.message("UNKNOWN_ERROR")
            }
        }

        let result = try await doRequest()
        if let result {
            return result
        } else {
            // try request again after re-auth
            guard
                try await refreshToken(),
                let result = try await doRequest()
            else {
                throw SourceError.message("NOT_LOGGED_IN")
            }
            return result
        }
    }

    func refreshToken() async throws(SourceError) -> Bool {
        let url = try getServerUrl(path: "/api/account/refresh-token")

        let token = UserDefaults.standard.string(forKey: "\(sourceKey).token")
        let refreshToken = UserDefaults.standard.string(forKey: "\(sourceKey).refreshToken")
        guard let token, let refreshToken else { return false }

        struct TokenRefresh: Codable {
            let token: String
            let refreshToken: String
        }

        let payload = TokenRefresh(token: token, refreshToken: refreshToken)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let response: TokenRefresh? = try? await URLSession.shared.object(from: request)
        guard let response else { return false }

        UserDefaults.standard.set(response.token, forKey: "\(sourceKey).token")
        UserDefaults.standard.set(response.refreshToken, forKey: "\(sourceKey).refreshToken")

        return true
    }
}

extension KavitaHelper {
    func getOnDeck(
        libraryId: Int = 0,
        pageNum: Int = 1,
        itemsPerPage: Int = 20
    ) async throws(SourceError) -> [KavitaSeries] {
        try await request(
            path: "/api/series/on-deck?libraryId=\(libraryId)&pageNumber=\(pageNum)&pageSize=\(itemsPerPage)",
            method: .POST,
            body: Data("{}".utf8)
        )
    }

    func getRecentlyAdded(
        pageNum: Int = 1,
        itemsPerPage: Int = 20
    ) async throws(SourceError) -> [KavitaSeries] {
        try await request(
            path: "/api/series/recently-added-v2?pageNumber=\(pageNum)&pageSize=\(itemsPerPage)",
            method: .POST,
            body: Data("{}".utf8)
        )
    }

    func getRecentlyUpdatedSeries() async throws(SourceError) -> [KavitaSeries] {
        let result: [KavitaSeriesGroup] = try await request(
            path: "/api/series/recently-updated-series",
            method: .POST,
            body: Data("{}".utf8)
        )
        return result.map { $0.into() }
    }

    enum QueryContext: Int {
        case none = 1
        case search = 2
        case recommended = 3
        case dashboard = 4
    }

    func getAllSeriesV2(
        pageNum: Int = 1,
        itemsPerPage: Int = 20,
        filter: KavitaFilterV2? = nil,
        context: QueryContext = .none
    ) async throws(SourceError) -> [KavitaSeries] {
        try await request(
            path: "/api/series/all-v2?context=\(context.rawValue)&pageNumber=\(pageNum)&pageSize=\(itemsPerPage)",
            method: .POST,
            body: {
                if let filter {
                    try? JSONEncoder().encode(filter)
                } else {
                    Data("{}".utf8)
                }
            }()
        )
    }

    func getAllGenres(context: QueryContext = .none) async throws(SourceError) -> [KavitaGenre] {
        try await request(
            path: "/api/metadata/genres?context=\(context.rawValue)"
        )
    }

    func getMoreIn(
        libraryId: Int = 0,
        genreId: Int,
        pageNum: Int = 1,
        itemsPerPage: Int = 20
    ) async throws(SourceError) -> [KavitaSeries] {
        try await request(
            path: "/api/recommended/more-in?libraryId=\(libraryId)&genreId=\(genreId)&pageNumber=\(pageNum)&pageSize=\(itemsPerPage)"
        )
    }

    func decodeFilter(_ encodedFilter: String) async throws(SourceError) -> KavitaFilterV2 {
        struct Payload: Encodable {
            let encodedFilter: String
        }
        return try await request(
            path: "/api/filter/decode",
            method: .POST,
            body: try? JSONEncoder().encode(Payload(encodedFilter: encodedFilter))
        )
    }
}

extension KavitaHelper {
    func getSearchFilter(
        query: String?,
        filters: [AidokuRunner.FilterValue],
        storedGenres: [KavitaSourceRunner.FilterItem],
        storedTags: [KavitaSourceRunner.FilterItem]
    ) async throws -> KavitaFilterV2 {
        var statements: [KavitaFilterV2.Statement] = []
        var sort: KavitaFilterV2.SortOptions?

        if let query {
            statements.append(.init(comparison: .matches, field: .seriesName, value: query))
        }

        for filter in filters {
            switch filter {
                case let .text(id, value):
                    struct Result: Decodable {
                        let id: Int
                        let name: String
                    }
                    if id == "author" {
                        let authors: [Result] = try await request(path: "/api/metadata/people-by-role?role=3")
                        if let author = authors.first(where: { $0.name == value }) {
                            statements.append(.init(comparison: .equal, field: .writers, value: String(author.id)))
                        }
                    } else if id == "artist" {
                        let artists: [Result] = try await request(path: "/api/metadata/people-by-role?role=4")
                        if let artist = artists.first(where: { $0.name == value }) {
                            statements.append(.init(comparison: .equal, field: .penciller, value: String(artist.id)))
                        }
                    }

                case let .sort(value):
                    let field: KavitaSortField = switch value.index {
                        case 0: .sortName
                        case 1: .createdDate
                        case 2: .lastModifiedDate
                        case 3: .lastChapterAdded
                        case 4: .timeToRead
                        case 5: .releaseYear
                        case 6: .readProgress
                        case 7: .averageRating
                        case 8: .random
                        default: .sortName
                    }
                    sort = .init(sortField: field, isAscending: value.ascending)

                case let .multiselect(filterId, included, excluded):
                    guard let field = Int(filterId).flatMap({ KavitaFilterField(rawValue: $0) }) else { continue }
                    if !included.isEmpty {
                        statements.append(.init(comparison: .contains, field: field, value: included.joined(separator: ",")))
                    }
                    if !excluded.isEmpty {
                        statements.append(.init(comparison: .notContains, field: field, value: excluded.joined(separator: ",")))
                    }

                case let .select(id, value):
                    if id == "genre" {
                        if let genre = storedGenres.first(where: { $0.title == value }) {
                            statements.append(.init(comparison: .contains, field: .genres, value: genre.id))
                        } else if let tag = storedTags.first(where: { $0.title == value }) {
                            statements.append(.init(comparison: .contains, field: .tags, value: tag.id))
                        }
                    }

                default:
                    continue
            }
        }

        return .init(
            statements: statements,
            sortOptions: sort
        )
    }
}
