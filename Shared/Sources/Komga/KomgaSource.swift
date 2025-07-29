//
//  KomgaSource.swift
//  Aidoku
//
//  Created by Skitty on 5/22/25.
//

import AidokuRunner
import Foundation

#if canImport(UIKit)
import UIKit
#endif

extension AidokuRunner.Source {
    static func komga(
        key: String = "komga",
        name: String? = nil,
        server: String? = nil
    ) -> AidokuRunner.Source {
        .init(
            url: nil,
            key: key,
            name: name ?? NSLocalizedString("KOMGA"),
            version: 1,
            languages: ["multi"],
            urls: UserDefaults.standard.string(forKey: "\(key).server")
                .flatMap { URL(string: $0) }
                .flatMap { [$0] } ?? [],
            contentRating: .safe,
            config: .init(
                languageSelectType: .single,
                supportsTagSearch: true
            ),
            staticListings: [],
            staticFilters: [
                .init(
                    id: "author",
                    title: NSLocalizedString("AUTHOR"),
                    value: .text(placeholder: NSLocalizedString("AUTHOR"))
                ),
                .init(
                    id: "artist",
                    title: NSLocalizedString("ARTIST"),
                    value: .text(placeholder: NSLocalizedString("ARTIST"))
                ),
                .init(
                    id: "sort",
                    title: NSLocalizedString("SORT"),
                    value: .sort(
                        canAscend: true,
                        options: [
                            NSLocalizedString("SORT_NAME"),
                            NSLocalizedString("SORT_DATE_ADDED"),
                            NSLocalizedString("SORT_DATE_UPDATED"),
                            NSLocalizedString("SORT_DATE_READ"),
                            NSLocalizedString("SORT_RELEASE_DATE"),
                            NSLocalizedString("SORT_FOLDER_NAME"),
                            NSLocalizedString("SORT_BOOKS_COUNT"),
                            NSLocalizedString("SORT_RANDOM")
                        ],
                        defaultValue: .init(index: 0, ascending: true)
                    )
                ),
                .init(
                    id: "status",
                    title: NSLocalizedString("STATUS"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: [
                            NSLocalizedString("COMPLETED"),
                            NSLocalizedString("ONGOING"),
                            NSLocalizedString("CANCELLED"),
                            NSLocalizedString("HIATUS")
                        ],
                        ids: ["ENDED", "ONGOING", "ABANDONED", "HIATUS"],
                    ))
                )
            ],
            staticSettings: [
                .init(
                    title: "SERVER_URL",
                    value: .group(.init(
                        footer: "SERVER_URL_INFO",
                        items: [
                            .init(
                                key: "server",
                                title: "SERVER_URL",
                                value: .text(.init(
                                    placeholder: "https://demo.komga.org",
                                    autocapitalizationType: UITextAutocapitalizationType.none.rawValue,
                                    keyboardType: UIKeyboardType.URL.rawValue,
                                    returnKeyType: UIReturnKeyType.done.rawValue,
                                    autocorrectionDisabled: true,
                                    defaultValue: server
                                ))
                            )
                        ]
                    ))
                ),
                .init(
                    value: .group(.init(
                        items: [
                            .init(
                                key: "login",
                                title: "LOGIN",
                                requires: "server",
                                refreshes: ["content", "listings", "filters"],
                                value: .login(.init(method: .basic))
                            )
                        ]
                    ))
                ),
                .init(
                    title: "OTHER_SETTINGS",
                    value: .group(.init(
                        items: [
                            .init(
                                key: "useChapters",
                                title: "USE_CHAPTERS",
                                value: .toggle(.init(subtitle: "USE_CHAPTERS_TEXT"))
                            )
                        ]
                    ))
                )
            ],
            runner: KomgaSourceRunner(sourceKey: key)
        )
    }
}

actor KomgaSourceRunner: Runner {
    let sourceKey: String
    let helper: KomgaHelper

    let features: SourceFeatures = .init(
        providesListings: true,
        providesHome: true,
        dynamicFilters: true,
        dynamicListings: true,
        providesImageRequests: true,
        providesBaseUrl: true,
        handlesBasicLogin: true
    )

    var storedKomgaTags: [String] = []

    init(sourceKey: String) {
        self.sourceKey = sourceKey
        self.helper = KomgaHelper(sourceKey: sourceKey)
    }

    private struct Sort {
        var value: Int
        var ascending: Bool
    }

    private func getConditions(filters: [AidokuRunner.FilterValue]) async throws -> (Sort, [KomgaSearchCondition]) {
        var conditions: [KomgaSearchCondition] = []
        var sort = Sort(value: 0, ascending: true)

        for filter in filters {
            switch filter {
                case let .text(id, value):
                    let search = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                    var authors: [KomgaBook.Metadata.Author] = []
                    if id == "author" {
                        let result: KomgaPageResponse<[KomgaBook.Metadata.Author]> = try await helper.request(
                            path: "/api/v2/authors?search=\(search)&role=writer"
                        )
                        authors.append(contentsOf: result.content)
                    } else if id == "artist" {
                        let result: KomgaPageResponse<[KomgaBook.Metadata.Author]> = try await helper.request(
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
                    if filterId == "genre"  || filterId == "tag" {
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
                            storedKomgaTags.contains(value) ? .tag(value) : .genre(value)
                        ]))
                    }

                default:
                    continue
            }
        }

        return (sort, conditions)
    }

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        let (sort, conditions) = try await getConditions(filters: filters)
        let sortOption = [
            "metadata.titleSort", // name
            "createdDate", // date added
            "lastModifiedDate", // date updated
            "readDate", // date read
            "booksMetadata.releaseDate", // release date
            "name", // folder name
            "booksCount", // books count
            "random" // random
        ][sort.value]
        let res: KomgaPageResponse<[KomgaSeries]> = try await helper.request(
            path: "/api/v1/series/list?page=\(page - 1)&size=20&sort=\(sortOption)%2C\(sort.ascending ? "asc" : "desc")",
            method: .POST,
            body: .init(
                condition: .allOf(conditions),
                fullTextSearch: (query?.isEmpty ?? true) ? nil : query
            )
        )
        let baseUrl = try helper.getConfiguredServer()
        return .init(
            entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
            hasNextPage: res.totalPages > page
        )
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        let baseUrl = try helper.getConfiguredServer()

        var manga = manga

        if needsDetails {
            let series: KomgaSeries = try await helper.request(path: "/api/v1/series/\(manga.key)")
            manga = manga.copy(from: series.intoManga(sourceKey: sourceKey, baseUrl: baseUrl))
        }

        if needsChapters {
            let chapters: KomgaPageResponse<[KomgaBook]> = try await helper.request(
                path: "/api/v1/books/list?unpaged=true&sort=metadata.numberSort%2Cdesc",
                method: .POST,
                body: .init(condition: .allOf([
                    .seriesId(manga.key),
                    .deleted(false)
                ]))
            )

            manga.chapters = chapters.content
                .filter { $0.media.mediaProfile != "EPUB" || $0.media.epubDivinaCompatible } // can't read epubs (yet?)
                .map {
                    $0.intoChapter(
                        baseUrl: baseUrl,
                        useChapters: UserDefaults.standard.bool(forKey: "\(sourceKey).useChapters")
                    )
                }
        }

        return manga
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        let pages: [KomgaPage] = try await helper.request(
            path: "/api/v1/books/\(chapter.id)/pages"
        )

        let baseUrl = try helper.getConfiguredServer()
        let pageBaseUrl = "\(baseUrl)/api/v1/books/\(chapter.id)/pages"

        return pages.compactMap { page in
            let convert = if !["image/jpeg", "image/png", "image/gif", "image/webp"].contains(page.mediaType) {
                "?convert=png"
            } else {
                ""
            }
            let url = "\(pageBaseUrl)/\(page.number)\(convert)"
            return URL(string: url).flatMap {
                .init(content: .url(url: $0))
            }
        }
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        try await helper.getMangaList(listing: listing, page: page)
    }

    func getHome() async throws -> Home {
        var components: [HomeComponent] = [
            .init(
                title: NSLocalizedString("KEEP_READING"),
                value: .scroller(
                    entries: [],
                    listing: .init(
                        id: "keep_reading",
                        name: NSLocalizedString("KEEP_READING"),
                        kind: .default
                    )
                )
            ),
            .init(
                title: NSLocalizedString("RECENTLY_ADDED_BOOKS"),
                value: .scroller(
                    entries: [],
                    listing: .init(
                        id: "recently_added_books",
                        name: NSLocalizedString("RECENTLY_ADDED_BOOKS"),
                        kind: .default
                    )
                )
            ),
            .init(
                title: NSLocalizedString("RECENTLY_ADDED_SERIES"),
                value: .scroller(
                    entries: [],
                    listing: .init(
                        id: "recently_added_series",
                        name: NSLocalizedString("RECENTLY_ADDED_SERIES"),
                        kind: .default
                    )
                )
            ),
            .init(
                title: NSLocalizedString("RECENTLY_UPDATED_SERIES"),
                value: .scroller(
                    entries: [],
                    listing: .init(
                        id: "recently_updated_series",
                        name: NSLocalizedString("RECENTLY_UPDATED_SERIES"),
                        kind: .default
                    )
                )
            ),
            .init(
                title: NSLocalizedString("RECENTLY_READ_BOOKS"),
                value: .scroller(
                    entries: [],
                    listing: .init(
                        id: "recently_read_books",
                        name: NSLocalizedString("RECENTLY_READ_BOOKS"),
                        kind: .default
                    )
                )
            )
        ]

//        homeSubject.send(.init(components: components))

        try await withThrowingTaskGroup(of: (AidokuRunner.Listing, [HomeComponent.Value.Link]).self) { [helper, sourceKey] taskGroup in
            // on deck
            taskGroup.addTask {
                let listing = AidokuRunner.Listing(id: "on_deck", name: NSLocalizedString("ON_DECK"), kind: .default)
                let onDeck: KomgaPageResponse<[KomgaBook]> = try await helper.request(
                    path: "/api/v1/books/ondeck?sort=createdDate%2Cdesc",
                    method: .GET
                )
                let baseUrl = try helper.getConfiguredServer()
                return (listing, onDeck.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl).intoLink() })
            }

            let listings: [AidokuRunner.Listing] = [
                .init(id: "keep_reading", name: NSLocalizedString("KEEP_READING"), kind: .default),
                .init(id: "recently_added_books", name: NSLocalizedString("RECENTLY_ADDED_BOOKS"), kind: .default),
                .init(id: "recently_added_series", name: NSLocalizedString("RECENTLY_ADDED_SERIES"), kind: .default),
                .init(id: "recently_updated_series", name: NSLocalizedString("RECENTLY_UPDATED_SERIES"), kind: .default),
                .init(id: "recently_read_books", name: NSLocalizedString("RECENTLY_READ_BOOKS"), kind: .default)
            ]

            for listing in listings {
                taskGroup.addTask {
                    let result = try await helper.getMangaList(listing: listing, page: 1)
                    return (listing, result.entries.map { $0.intoLink() })
                }
            }

            for try await (listing, entries) in taskGroup {
                if let index = components.firstIndex(where: { $0.title == listing.name }) {
                    if entries.isEmpty {
                        components.remove(at: index)
                    } else {
                        components[index].value = .scroller(
                            entries: entries,
                            listing: listing
                        )
                    }
//                    self.homeSubject.send(.init(components: components))
                } else if !entries.isEmpty {
                    // insert on deck listing
                    components.insert(.init(
                        title: listing.name,
                        value: .scroller(
                            entries: entries,
                            listing: listing
                        )
                    ), at: 1)
                }
            }
        }

        return .init(components: components)
    }

    func getSearchFilters() async throws -> [AidokuRunner.Filter] {
        enum ResultType: String, CaseIterable {
            case genres
            case tags
            case publishers
            case languages
            case ageRatings = "age-ratings"
            case releaseDates = "series/release-dates"
            case sharingLabels = "sharing-labels"
        }
        let helper = self.helper // capture the helper
        let result = try await withThrowingTaskGroup(of: (ResultType, [String]).self, returning: [ResultType: [String]].self) { taskGroup in
            for type in ResultType.allCases {
                taskGroup.addTask {
                    let result: [String] = try await helper.request(path: "/api/v1/\(type.rawValue)")
                    return (type, result)
                }
            }
            var result: [ResultType: [String]] = [:]
            for try await value in taskGroup {
                result[value.0] = value.1
            }
            return result
        }
        var filters: [AidokuRunner.Filter] = []
        if let genres = result[.genres], !genres.isEmpty {
            filters.append(
                .init(
                    id: "genre",
                    title: NSLocalizedString("GENRE"),
                    value: .multiselect(.init(
                        isGenre: true,
                        canExclude: true,
                        usesTagStyle: true,
                        options: [NSLocalizedString("ANY")] + genres,
                        ids: [""] + genres
                    ))
                )
            )
        }
        if let tags = result[.tags], !tags.isEmpty {
            storedKomgaTags = tags
            filters.append(
                .init(
                    id: "tag",
                    title: NSLocalizedString("TAG"),
                    value: .multiselect(.init(
                        isGenre: true,
                        canExclude: true,
                        usesTagStyle: true,
                        options: [NSLocalizedString("ANY")] + tags,
                        ids: [""] + tags
                    ))
                )
            )
        }
        if let publishers = result[.publishers], !publishers.isEmpty {
            filters.append(
                .init(
                    id: "publisher",
                    title: NSLocalizedString("PUBLISHER"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: [NSLocalizedString("ANY")] + publishers,
                        ids: [""] + publishers,
                    ))
                )
            )
        }
        if let languages = result[.languages], !languages.isEmpty {
            filters.append(
                .init(
                    id: "language",
                    title: NSLocalizedString("LANGUAGE"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: [NSLocalizedString("ANY")] + languages.map {
                            if let localizedName = Locale.current.localizedString(forIdentifier: $0) {
                                "\(localizedName) (\($0))"
                            } else {
                                $0
                            }
                        },
                        ids: [""] + languages,
                    ))
                )
            )
        }
        if let ratings = result[.ageRatings], ratings.count > 1 {
            filters.append(
                .init(
                    id: "age_rating",
                    title: NSLocalizedString("AGE_RATING"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: result[.ageRatings, default: []]
                    ))
                )
            )
        }
        if let releaseDates = result[.releaseDates], !releaseDates.isEmpty {
            filters.append(
                .init(
                    id: "release_date",
                    title: NSLocalizedString("RELEASE_DATE"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: [NSLocalizedString("ANY")] + releaseDates,
                        ids: [""] + releaseDates
                    ))
                )
            )
        }
        if let labels = result[.sharingLabels], !labels.isEmpty {
            filters.append(
                .init(
                    id: "sharing_label",
                    title: NSLocalizedString("SHARING_LABEL"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: [NSLocalizedString("ANY")] + labels,
                        ids: [""] + labels
                    ))
                )
            )
        }
        return filters
    }

    func getListings() async throws -> [AidokuRunner.Listing] {
        let libraries: [KomgaLibrary] = try await helper.request(path: "/api/v1/libraries")

        return libraries.map {
            .init(id: "library-\($0.id)", name: $0.name, kind: .default)
        }
    }

    func getImageRequest(url: String, context: PageContext?) async throws -> URLRequest {
        guard let url = URL(string: url) else { throw SourceError.message("Invalid URL") }
        var request = URLRequest(url: url)
        request.setValue(helper.getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        return request
    }

    func getBaseUrl() async throws -> URL? {
        URL(string: try helper.getConfiguredServer())
    }

    func handleBasicLogin(key _: String, username email: String, password: String) async throws -> Bool {
        let server = try helper.getConfiguredServer()
        guard let testUrl = URL(string: server + "/api/v2/users/me") else {
            return false
        }

        var request = URLRequest(url: testUrl)
        let auth = Data("\(email):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        struct Response: Codable {
            let email: String
        }
        let response: Response? = try? await URLSession.shared.object(from: request)

        guard let response, response.email == email else {
            return false
        }

        return true
    }
}

struct KomgaHelper: Sendable {
    let sourceKey: String

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        let baseUrl = try getConfiguredServer()
        switch listing.id {
            case "keep_reading":
                let res: KomgaPageResponse<[KomgaBook]> = try await request(
                    path: "/api/v1/books/list?page=\(page - 1)&size=20&sort=readProgress.readDate%2Cdesc",
                    method: .POST,
                    body: .init(condition: .allOf([
                        .readStatus(.inProgress),
                        .deleted(false)
                    ]))
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "on_deck":
                let res: KomgaPageResponse<[KomgaBook]> = try await request(
                    path: "/api/v1/books/ondeck?page=\(page - 1)&size=20&sort=createdDate%2Cdesc",
                    method: .GET
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "recently_added_books":
                let res: KomgaPageResponse<[KomgaBook]> = try await request(
                    path: "/api/v1/books/list?page=\(page - 1)&size=20&sort=createdDate%2Cdesc",
                    method: .POST,
                    body: .init(condition: .allOf([])) // needs to have some condition
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "recently_added_series":
                let res: KomgaPageResponse<[KomgaSeries]> = try await request(
                    path: "/api/v1/series/new?page=\(page - 1)&size=20&oneshot=false",
                    method: .GET
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "recently_updated_series":
                let res: KomgaPageResponse<[KomgaSeries]> = try await request(
                    path: "/api/v1/series/updated?page=\(page - 1)&size=20&oneshot=false",
                    method: .GET
                )
                return .init(
                    entries: res.content.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) },
                    hasNextPage: res.totalPages > page
                )

            case "recently_read_books":
                let res: KomgaPageResponse<[KomgaBook]> = try await request(
                    path: "/api/v1/books/list?page=\(page - 1)&size=20&sort=readProgress.readDate%2Cdesc",
                    method: .POST,
                    body: .init(condition: .allOf([
                        .readStatus(.read),
                        .deleted(false)
                    ]))
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

    private func getServerUrl(path: String) throws(SourceError) -> URL {
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
        switch method {
            case .GET: request.httpMethod = "GET"
            case .POST: request.httpMethod = "POST"
            case .HEAD: request.httpMethod = "HEAD"
            case .PUT: request.httpMethod = "PUT"
            case .DELETE: request.httpMethod = "DELETE"
        }
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
