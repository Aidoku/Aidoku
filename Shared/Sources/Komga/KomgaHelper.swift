//
//  KomgaHelper.swift
//  Aidoku
//
//  Created by Skitty on 10/19/25.
//

import AidokuRunner
import Foundation

struct KomgaHelper: Sendable {
    let sourceKey: String

    func getAuthorizationHeader() -> String? {
        let username = UserDefaults.standard.string(forKey: "\(sourceKey).login.username")
        let password = UserDefaults.standard.string(forKey: "\(sourceKey).login.password")
        guard let username, let password else {
            return nil
        }
        let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(encoded)"
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

    func request<T: Codable>(
        path: String,
        method: HttpMethod = .GET,
        body: KomgaSearchBody? = nil
    ) async throws(SourceError) -> T {
        guard let auth = getAuthorizationHeader() else {
            throw SourceError.message("NOT_LOGGED_IN")
        }

        let url = try getServerUrl(path: path)
        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = method.stringValue
        if let body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .custom({ date, encoder in
                var container = encoder.singleValueContainer()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                try container.encode(formatter.string(from: date))
            })
            request.httpBody = try? encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let result = try? await URLSession.shared.data(for: request)
        guard let data = result?.0 else {
            throw SourceError.networkError
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
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            var date = formatter.date(from: string)
            if date == nil {
                formatter.dateFormat = "yyyy-MM-dd"
                date = formatter.date(from: string)
            }
            return date ?? .distantPast
        })
        if let result = try? decoder.decode(T.self, from: data) as T? {
            return result
        } else if let error = try? decoder.decode(KomgaError.self, from: data) {
            throw SourceError.message(error.error)
        } else {
            throw SourceError.message("UNKNOWN_ERROR")
        }
    }
}

extension KomgaHelper {
    struct Sort {
        var value: Int
        var ascending: Bool
    }

    func getConditions(filters: [AidokuRunner.FilterValue], storedTags: [String]) async throws -> (Sort, [KomgaSearchCondition]) {
        var conditions: [KomgaSearchCondition] = []
        var sort = Sort(value: 0, ascending: true)

        for filter in filters {
            switch filter {
                case let .text(id, value):
                    let search = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                    var authors: [KomgaBook.Metadata.Author] = []
                    if id == "author" {
                        let result: KomgaPageResponse<[KomgaBook.Metadata.Author]> = try await request(
                            path: "/api/v2/authors?search=\(search)&role=writer"
                        )
                        authors.append(contentsOf: result.content)
                    } else if id == "artist" {
                        let result: KomgaPageResponse<[KomgaBook.Metadata.Author]> = try await request(
                            path: "/api/v2/authors?search=\(search)&role=penciller"
                        )
                        authors.append(contentsOf: result.content)
                    }
                    if !authors.isEmpty {
                        conditions.append(.anyOf(authors.map {
                            .author(name: $0.name, role: $0.role, exclude: false)
                        }))
                    }

                case let .sort(value):
                    sort.value = Int(value.index)
                    sort.ascending = value.ascending

                case let .multiselect(filterId, included, excluded):
                    if filterId == "library" {
                        let includedConditions: [KomgaSearchCondition] = included
                            .map { .libraryId($0, exclude: false) }
                        let excludedConditions: [KomgaSearchCondition] = excluded
                            .map { .libraryId($0, exclude: true) }
                        let condition: KomgaSearchCondition = if excluded.isEmpty {
                            .anyOf(includedConditions)
                        } else {
                            .allOf(includedConditions + excludedConditions)
                        }
                        conditions.append(condition)
                    } else if filterId == "genre"  || filterId == "tag" {
                        let includedConditions: [KomgaSearchCondition] = included
                            .map { filterId == "genre" ? .genre($0) : .tag($0) }
                        let excludedConditions: [KomgaSearchCondition] = excluded
                            .map { filterId == "genre" ? .genre($0, exclude: true) : .tag($0, exclude: true) }
                        let condition: KomgaSearchCondition = if excluded.isEmpty {
                            .anyOf(includedConditions)
                        } else {
                            .allOf(includedConditions + excludedConditions)
                        }
                        conditions.append(condition)
                    } else {
                        func filterMap(id: String, exclude: Bool) -> KomgaSearchCondition? {
                            switch filterId {
                                case "age_rating":
                                    if id == "None" {
                                        .ageRating(nil, exclude: exclude)
                                    } else {
                                        Int(id).flatMap { .ageRating($0, exclude: exclude) }
                                    }
                                case "release_date":
                                    if id.isEmpty {
                                        .releaseDate(nil, exclude: exclude)
                                    } else {
                                        Int(id).flatMap { .releaseDate($0, exclude: exclude) }
                                    }
                                case "language":
                                        .language(id, exclude: exclude)
                                case "publisher":
                                        .publisher(id, exclude: exclude)
                                case "sharing_label":
                                        .sharingLabel(id, exclude: exclude)
                                case "status":
                                    KomgaSeries.Metadata.Status(rawValue: id).flatMap { .seriesStatus($0, exclude: exclude) }
                                default:
                                    nil
                            }
                        }
                        let includedConditions = included.compactMap { filterMap(id: $0, exclude: false) }
                        let excludedConditions = excluded.compactMap { filterMap(id: $0, exclude: true) }
                        let condition: KomgaSearchCondition? = if excluded.isEmpty && !included.isEmpty {
                            .anyOf(includedConditions)
                        } else if !included.isEmpty || !excluded.isEmpty {
                            .allOf(includedConditions + excludedConditions)
                        } else {
                            nil
                        }
                        if let condition {
                            conditions.append(condition)
                        }
                    }

                case let .select(id, value):
                    if id == "genre" {
                        conditions.append(.anyOf([
                            storedTags.contains(value) ? .tag(value) : .genre(value)
                        ]))
                    }

                default:
                    continue
            }
        }

        return (sort, conditions)
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        let baseUrl = try getConfiguredServer()

        // Extract library ID if this is a library-specific listing
        // Format: library-{libraryId}-{listingType}
        var libraryId: String?
        var actualListingId = listing.id

        if listing.id.hasPrefix("library-") {
            let parts = listing.id.split(separator: "-")
            if parts.count >= 3 {
                // This is library-specific (e.g., "library-abc123-keep_reading")
                libraryId = String(parts[1])
                actualListingId = parts[2...].joined(separator: "-")
            } else if parts.count == 2 {
                // This is a library listing (e.g., "library-abc123")
                libraryId = String(parts[1])
                actualListingId = listing.id
            }
        }

        switch actualListingId {
            case "keep_reading":
                let conditions: [KomgaSearchCondition] = [
                    .readStatus(.inProgress),
                    .deleted(false)
                ] + (libraryId.map { [.libraryId($0)] } ?? [])
                let res: KomgaPageResponse<[KomgaBook]> = try await request(
                    path: "/api/v1/books/list?page=\(page - 1)&size=20&sort=readProgress.readDate%2Cdesc",
                    method: .POST,
                    body: .init(condition: .allOf(conditions))
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "on_deck":
                let libraryParam = libraryId.map { "&library_id=\($0)" } ?? ""
                let res: KomgaPageResponse<[KomgaBook]> = try await request(
                    path: "/api/v1/books/ondeck?page=\(page - 1)&size=20&sort=createdDate%2Cdesc\(libraryParam)",
                    method: .GET
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "recently_added_books":
                let conditions: [KomgaSearchCondition] = [.deleted(false)] + (libraryId.map { [.libraryId($0)] } ?? [])
                let res: KomgaPageResponse<[KomgaBook]> = try await request(
                    path: "/api/v1/books/list?page=\(page - 1)&size=20&sort=createdDate%2Cdesc",
                    method: .POST,
                    body: .init(condition: .allOf(conditions))
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "recently_added_series":
                let libraryParam = libraryId.map { "&library_id=\($0)" } ?? ""
                let res: KomgaPageResponse<[KomgaSeries]> = try await request(
                    path: "/api/v1/series/new?page=\(page - 1)&size=20&oneshot=false&deleted=false\(libraryParam)",
                    method: .GET
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "recently_updated_series":
                let libraryParam = libraryId.map { "&library_id=\($0)" } ?? ""
                let res: KomgaPageResponse<[KomgaSeries]> = try await request(
                    path: "/api/v1/series/updated?page=\(page - 1)&size=20&oneshot=false&deleted=false\(libraryParam)",
                    method: .GET
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "recently_read_books":
                let conditions: [KomgaSearchCondition] = [
                    .readStatus(.read),
                    .deleted(false)
                ] + (libraryId.map { [.libraryId($0)] } ?? [])
                let res: KomgaPageResponse<[KomgaBook]> = try await request(
                    path: "/api/v1/books/list?page=\(page - 1)&size=20&sort=readProgress.readDate%2Cdesc",
                    method: .POST,
                    body: .init(condition: .allOf(conditions))
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case _ where listing.id.hasPrefix("library-"):
                let id = String(listing.id[listing.id.index(listing.id.startIndex, offsetBy: 8)...])
                let res: KomgaPageResponse<[KomgaSeries]> = try await request(
                    path: "/api/v1/series/list?page=\(page - 1)&size=20&sort=metadata.titleSort%2Casc",
                    method: .POST,
                    body: .init(condition: .allOf([
                        .libraryId(id),
                        .deleted(false)
                    ]))
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            default:
                return .init(entries: [], hasNextPage: false)
        }
    }
}
