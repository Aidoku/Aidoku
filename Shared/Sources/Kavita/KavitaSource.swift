//
//  KavitaSource.swift
//  Aidoku
//
//  Created by Skitty on 10/19/25.
//

import AidokuRunner
import Foundation

#if canImport(UIKit)
import UIKit
#endif

extension AidokuRunner.Source {
    static func kavita(
        key: String = "kavita",
        name: String? = nil,
        server: String? = nil
    ) -> AidokuRunner.Source {
        .init(
            url: nil,
            key: key,
            name: name ?? NSLocalizedString("KAVITA"),
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
                            NSLocalizedString("SORT_CHAPTER_ADDED"),
                            NSLocalizedString("SORT_TIME_TO_READ"),
                            NSLocalizedString("SORT_RELEASE_DATE"),
                            NSLocalizedString("SORT_DATE_READ"),
                            NSLocalizedString("SORT_AVERAGE_RATING"),
                            NSLocalizedString("SORT_RANDOM")
                        ],
                        defaultValue: .init(index: 0, ascending: true)
                    )
                ),
                .init(
                    id: String(KavitaFilterField.publicationStatus.rawValue),
                    title: NSLocalizedString("STATUS"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: [
                            NSLocalizedString("ONGOING"),
                            NSLocalizedString("HIATUS"),
                            NSLocalizedString("COMPLETED"),
                            NSLocalizedString("CANCELLED"),
                            NSLocalizedString("ENDED")
                        ],
                        ids: ["0", "1", "2", "3", "4"],
                    ))
                ),
                .init(
                    id: String(KavitaFilterField.formats.rawValue),
                    title: NSLocalizedString("FORMAT"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: [
                            NSLocalizedString("FORMAT_IMAGE"),
                            NSLocalizedString("FORMAT_EPUB"),
                            NSLocalizedString("FORMAT_PDF"),
                            NSLocalizedString("FORMAT_ARCHIVE")
                        ],
                        ids: ["0", "3", "4", "1"],
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
                                value: .text(.init(
                                    placeholder: "https://demo.kavitareader.com",
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
                    title: "MIRRORS",
                    value: .group(.init(
                        footer: "MIRRORS_INFO",
                        items: [
                            .init(
                                key: "mirrors",
                                title: "MIRRORS",
                                value: .editableList(.init(
                                    lineLimit: 1,
                                    inline: true,
                                    placeholder: NSLocalizedString("SERVER_URL")
                                ))
                            )
                        ]
                    ))
                )
            ],
            runner: KavitaSourceRunner(sourceKey: key)
        )
    }
}

actor KavitaSourceRunner: Runner {
    let sourceKey: String
    let helper: KavitaHelper

    let features: SourceFeatures = .init(
        providesListings: true,
        providesHome: true,
        dynamicFilters: true,
        dynamicSettings: true,
        dynamicListings: true,
        providesImageRequests: true,
        providesBaseUrl: true,
        handlesNotifications: true,
        handlesBasicLogin: true,
        handlesWebLogin: true
    )

    init(sourceKey: String) {
        self.sourceKey = sourceKey
        self.helper = .init(sourceKey: sourceKey)
    }

    struct FilterItem {
        let id: String
        let title: String
    }

    private var storedGenres: [FilterItem] = []
    private var storedTags: [FilterItem] = []
    private var lastWorkingMirror: URL?

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        var baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()
        let filter = try await helper.getSearchFilter(
            query: query,
            filters: filters,
            storedGenres: storedGenres,
            storedTags: storedTags
        )
        var lastWorkingMirrorCopy = lastWorkingMirror
        let res: [KavitaSeries] = try await helper.request(
            path: "api/series/v2",
            method: .POST,
            body: JSONEncoder().encode(filter),
            lastWorkingMirror: &lastWorkingMirrorCopy
        )
        lastWorkingMirror = lastWorkingMirrorCopy
        baseUrl = lastWorkingMirrorCopy ?? baseUrl
        return .init(
            entries: res.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
            hasNextPage: false
        )
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        var baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()

        var lastWorkingMirrorCopy = lastWorkingMirror
        defer {
            lastWorkingMirror = lastWorkingMirrorCopy
        }

        var manga = manga

        if needsDetails {
            let series: KavitaSeries = try await helper.request(path: "api/Series/\(manga.key)", lastWorkingMirror: &lastWorkingMirrorCopy)
            let metadata: KavitaSeriesMetadata = try await helper.request(
                path: "api/Series/metadata?seriesId=\(manga.key)",
                lastWorkingMirror: &lastWorkingMirrorCopy
            )
            baseUrl = lastWorkingMirrorCopy ?? baseUrl
            manga = manga.copy(from: series.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey, metadata: metadata))
        }

        if needsChapters {
            let volumes: [KavitaVolume] = try await helper.request(
                path: "api/Series/volumes?seriesId=\(manga.key)",
                lastWorkingMirror: &lastWorkingMirrorCopy
            )
            baseUrl = lastWorkingMirrorCopy ?? baseUrl
            var chapters = volumes.flatMap { $0.intoChapters(baseUrl: baseUrl, apiKey: apiKey) }
            chapters.sort { a, b in
                if a.volumeNumber == b.volumeNumber {
                    if a.chapterNumber == b.chapterNumber {
                        return false // order doesn't matter
                    } else {
                        return a.chapterNumber ?? 0 > b.chapterNumber ?? 0
                    }
                } else {
                    if a.volumeNumber == nil || b.volumeNumber == nil {
                        return a.volumeNumber ?? 0 < b.volumeNumber ?? 0 // chapters with no volume should be on top (reverse order)
                    } else {
                        return a.volumeNumber ?? 0 > b.volumeNumber ?? 0
                    }
                }
            }
            manga.chapters = chapters
        }

        return manga
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        var baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()

        var lastWorkingMirrorCopy = lastWorkingMirror
        let chapter: KavitaVolume.Chapter = try await helper.request(
            path: "api/Series/chapter?chapterId=\(chapter.key)",
            lastWorkingMirror: &lastWorkingMirrorCopy
        )
        lastWorkingMirror = lastWorkingMirrorCopy

        baseUrl = lastWorkingMirrorCopy ?? baseUrl

        return (0..<chapter.pages).compactMap { page in
            let path = "api/Reader/image?chapterId=\(chapter.id)&page=\(page)&apiKey=\(apiKey)&extractPdf=true"
            return URL(string: path, relativeTo: baseUrl).flatMap {
                .init(content: .url(url: $0))
            }
        }
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        var baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()
        var lastWorkingMirrorCopy = lastWorkingMirror
        defer {
            lastWorkingMirror = lastWorkingMirrorCopy
        }

        switch listing.id {
            case "on_deck":
                let series = try await helper.getOnDeck(pageNum: page, lastWorkingMirror: &lastWorkingMirrorCopy)
                baseUrl = lastWorkingMirrorCopy ?? baseUrl
                return .init(
                    entries: series.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
                    hasNextPage: series.count == 20
                )

            case "recently_updated":
                let series = try await helper.getRecentlyUpdatedSeries(lastWorkingMirror: &lastWorkingMirrorCopy)
                baseUrl = lastWorkingMirrorCopy ?? baseUrl
                return .init(
                    entries: series.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
                    hasNextPage: false
                )

            case "recently_added":
                let series = try await helper.getRecentlyAdded(pageNum: page, lastWorkingMirror: &lastWorkingMirrorCopy)
                baseUrl = lastWorkingMirrorCopy ?? baseUrl
                return .init(
                    entries: series.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
                    hasNextPage: series.count == 20
                )

            case _ where listing.id.hasPrefix("morein-"):
                guard let genreId = Int(listing.id[listing.id.index(listing.id.startIndex, offsetBy: 7)...]) else {
                    throw SourceError.message("Invalid genre id")
                }
                let series = try await helper.getMoreIn(genreId: genreId, pageNum: page, lastWorkingMirror: &lastWorkingMirrorCopy)
                baseUrl = lastWorkingMirrorCopy ?? baseUrl
                return .init(
                    entries: series.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
                    hasNextPage: series.count == 20
                )

            case _ where listing.id.hasPrefix("filter-"):
                let encodedFilter = String(listing.id[listing.id.index(listing.id.startIndex, offsetBy: 7)...])
                let filter = try await helper.decodeFilter(encodedFilter, lastWorkingMirror: &lastWorkingMirrorCopy)
                let series = try await helper.getAllSeriesV2(
                    pageNum: page,
                    filter: filter,
                    context: .dashboard,
                    lastWorkingMirror: &lastWorkingMirrorCopy
                )
                baseUrl = lastWorkingMirrorCopy ?? baseUrl
                return .init(
                    entries: series.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
                    hasNextPage: series.count == 20
                )

            case _ where listing.id.hasPrefix("library-"):
                let id = String(listing.id[listing.id.index(listing.id.startIndex, offsetBy: 8)...])

                let filter = KavitaFilterV2(
                    statements: [.init(comparison: .equal, field: .libraries, value: id)],
                )
                var lastWorkingMirrorCopy = lastWorkingMirror
                let res: [KavitaSeries] = try await helper.request(
                    path: "api/series/v2",
                    method: .POST,
                    body: JSONEncoder().encode(filter),
                    lastWorkingMirror: &lastWorkingMirrorCopy
                )
                baseUrl = lastWorkingMirrorCopy ?? baseUrl
                return .init(
                    entries: res.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
                    hasNextPage: false
                )

            default:
                throw SourceError.message("Invalid listing")
        }
    }

    func getSearchFilters() async throws -> [AidokuRunner.Filter] {
        enum ResultType: String, CaseIterable {
            case libraries
            case genres = "genres?context=1"
            case tags
            case publishers = "people-by-role?role=10"
            case languages
            case ageRatings = "age-ratings"

            var path: String {
                switch self {
                    case .libraries: "/api/library/libraries"
                    default: "/api/metadata/\(self.rawValue)"
                }
            }
        }
        let result = try await withThrowingTaskGroup(
            of: (ResultType, [FilterItem]).self,
            returning: [ResultType: [FilterItem]].self
        ) { [helper] taskGroup in
            for type in ResultType.allCases {
                taskGroup.addTask { [lastWorkingMirror] in
                    struct Result: Decodable {
                        let id: Int?
                        let value: Int?
                        let isoCode: String?
                        let title: String?
                        let name: String?

                        var resolvedId: String { isoCode ?? String(id ?? value ?? 0) }
                        var resolvedTitle: String { title ?? name ?? "" }

                        func into() -> FilterItem {
                            .init(id: resolvedId, title: resolvedTitle)
                        }
                    }
                    var lastWorkingMirrorCopy = lastWorkingMirror
                    let result: [Result] = try await helper.request(path: type.path, lastWorkingMirror: &lastWorkingMirrorCopy)
                    return (type, result.map { $0.into() })
                }
            }
            var result: [ResultType: [FilterItem]] = [:]
            for try await value in taskGroup {
                result[value.0] = value.1
            }
            return result
        }
        var filters: [AidokuRunner.Filter] = []

        if let libraryObjects = result[.libraries], libraryObjects.count > 1 {
            filters.append(
                .init(
                    id: String(KavitaFilterField.libraries.rawValue),
                    title: NSLocalizedString("LIBRARY"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: libraryObjects.map { $0.title },
                        ids: libraryObjects.map { $0.id }
                    ))
                )
            )
        }

        if let genres = result[.genres], !genres.isEmpty {
            storedGenres = genres
            filters.append(
                .init(
                    id: String(KavitaFilterField.genres.rawValue),
                    title: NSLocalizedString("GENRE"),
                    value: .multiselect(.init(
                        isGenre: true,
                        canExclude: true,
                        usesTagStyle: true,
                        options: genres.map { $0.title },
                        ids: genres.map { $0.id }
                    ))
                )
            )
        }
        if let tags = result[.tags], !tags.isEmpty {
            storedTags = tags
            filters.append(
                .init(
                    id: String(KavitaFilterField.tags.rawValue),
                    title: NSLocalizedString("TAG"),
                    value: .multiselect(.init(
                        isGenre: true,
                        canExclude: true,
                        usesTagStyle: true,
                        options: tags.map { $0.title },
                        ids: tags.map { $0.id }
                    ))
                )
            )
        }
        if let publishers = result[.publishers], !publishers.isEmpty {
            filters.append(
                .init(
                    id: String(KavitaFilterField.publisher.rawValue),
                    title: NSLocalizedString("PUBLISHER"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: publishers.map { $0.title },
                        ids: publishers.map { $0.id }
                    ))
                )
            )
        }
        if let languages = result[.languages], !languages.isEmpty {
            filters.append(
                .init(
                    id: String(KavitaFilterField.languages.rawValue),
                    title: NSLocalizedString("LANGUAGE"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: languages.map { $0.title },
                        ids: languages.map { $0.id }
                    ))
                )
            )
        }
        if let ratings = result[.ageRatings], ratings.count > 1 {
            filters.append(
                .init(
                    id: String(KavitaFilterField.ageRating.rawValue),
                    title: NSLocalizedString("AGE_RATING"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: ratings.map { $0.title },
                        ids: ratings.map { $0.id }
                    ))
                )
            )
        }
        return filters
    }

    func getListings() async throws -> [AidokuRunner.Listing] {
        var lastWorkingMirrorCopy = lastWorkingMirror
        let libraries: [KavitaLibrary] = try await helper.request(path: "api/library/libraries", lastWorkingMirror: &lastWorkingMirrorCopy)
        lastWorkingMirror = lastWorkingMirrorCopy
        return libraries.map {
            .init(id: "library-\($0.id)", name: $0.name, kind: .default)
        }
    }

    func getImageRequest(url: String, context: PageContext?) async throws -> URLRequest {
        guard let url = URL(string: url) else { throw SourceError.message("Invalid URL") }
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    func getSettings() async throws -> [Setting] {
        // check for oidc support
        let server = try helper.getConfiguredServer()
        guard let oidcCheckUrl = URL(string: "api/settings/oidc", relativeTo: server) else {
            return []
        }

        struct OIDCResponse: Decodable {
            let disablePasswordAuthentication: Bool
            let enabled: Bool
            let providerName: String
        }
        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 5 // time out requests after 5s
            return config
        }())
        let response: OIDCResponse? = try? await session.object(from: oidcCheckUrl)
        guard let response else { return [] }

        var settings: [Setting] = []

        let isBasicLoggedIn = UserDefaults.standard.string(forKey: "\(sourceKey).login") != nil
        let isOidcLoggedIn = UserDefaults.standard.string(forKey: "\(sourceKey).login_oidc") != nil

        if !response.disablePasswordAuthentication && !isOidcLoggedIn {
            settings.append(.init(
                value: .group(.init(
                    items: [
                        .init(
                            key: "login",
                            title: "LOGIN",
                            notification: "login",
                            requires: "server",
                            requiresFalse: "login_oidc",
                            refreshes: ["content", "listings", "filters", "settings"],
                            value: .login(.init(method: .basic))
                        )
                    ]
                ))
            ))
        }
        if response.enabled && !isBasicLoggedIn {
            settings.append(.init(
                value: .group(.init(
                    items: [
                        .init(
                            key: "login_oidc",
                            title: "LOGIN_VIA_OIDC",
                            notification: "login_oidc",
                            requires: "server",
                            requiresFalse: "login",
                            refreshes: ["content", "listings", "filters", "settings"],
                            value: .login(.init(method: .web, url: URL(string: "/oidc/login", relativeTo: server)?.absoluteString))
                        )
                    ]
                ))
            ))
        }

        return settings
    }

    func getBaseUrl() async throws -> URL? {
        try helper.getConfiguredServer()
    }

    func handleBasicLogin(key _: String, username: String, password: String) async throws -> Bool {
        let server = try helper.getConfiguredServer()
        let response = await Self.getLoginResponse(server: server, username: username, password: password)

        guard
            let response,
            let token = response.token,
            let refreshToken = response.refreshToken,
            let apiKey = response.getApiKey(),
            response.username == username
        else {
            return false
        }

        UserDefaults.standard.setValue(apiKey, forKey: "\(sourceKey).apiKey")
        UserDefaults.standard.setValue(token, forKey: "\(sourceKey).token")
        UserDefaults.standard.setValue(refreshToken, forKey: "\(sourceKey).refreshToken")

        return true
    }

    func handleWebLogin(key: String, cookies: [String: String]) async throws -> Bool {
        let server = try helper.getConfiguredServer()

        guard
            let cookie = cookies[".AspNetCore.Cookies"],
            let httpCookie = HTTPCookie(properties: [
                .name: ".AspNetCore.Cookies",
                .value: cookie,
                .domain: server.domain ?? "",
                .path: "/"
            ])
        else {
            return false
        }

        let response = await Self.getLoginResponse(server: server, cookies: [httpCookie])

        guard
            let response,
            let cookie = response.cookie,
            let apiKey = response.getApiKey()
        else {
            return false
        }

        UserDefaults.standard.setValue(apiKey, forKey: "\(sourceKey).apiKey")
        UserDefaults.standard.setValue(cookie, forKey: "\(sourceKey).cookie")

        return true
    }

    func handleNotification(notification: String) async throws {
        // clear additional login values when logging out
        switch notification {
            case "login":
                let isLoggedIn = UserDefaults.standard.string(forKey: "\(sourceKey).login") != nil
                if !isLoggedIn {
                    UserDefaults.standard.setValue(nil, forKey: "\(sourceKey).apiKey")
                    UserDefaults.standard.setValue(nil, forKey: "\(sourceKey).token")
                    UserDefaults.standard.setValue(nil, forKey: "\(sourceKey).refreshToken")
                }

            case "login_oidc":
                let isLoggedIn = UserDefaults.standard.string(forKey: "\(sourceKey).login_oidc") != nil
                if !isLoggedIn {
                    UserDefaults.standard.setValue(nil, forKey: "\(sourceKey).apiKey")
                    UserDefaults.standard.setValue(nil, forKey: "\(sourceKey).cookie")
                }

            default:
                break
        }
    }
}

extension KavitaSourceRunner {
    func getHome() async throws -> Home {
        var lastWorkingMirrorCopy = lastWorkingMirror
        let dashComponents: [KavitaDashComponent] = try await helper.request(
            path: "api/stream/dashboard?visibleOnly=true",
            lastWorkingMirror: &lastWorkingMirrorCopy
        )
        lastWorkingMirror = lastWorkingMirrorCopy

        let baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()

        var components: [HomeComponent?] = Array(repeating: nil, count: dashComponents.count)

        try await withThrowingTaskGroup(of: (Int, String, String, URL, [KavitaSeries]).self) { [helper, sourceKey] taskGroup in
            for (index, c) in dashComponents.enumerated() {
                taskGroup.addTask { [lastWorkingMirror] in
                    var lastWorkingMirrorCopy = lastWorkingMirror
                    switch c.streamType {
                        case .onDeck:
                            let series = try await helper.getOnDeck(lastWorkingMirror: &lastWorkingMirrorCopy)
                            return (index, NSLocalizedString("ON_DECK"), "on_deck", lastWorkingMirrorCopy ?? baseUrl, series)
                        case .recentlyUpdated:
                            let series = try await helper.getRecentlyUpdatedSeries(lastWorkingMirror: &lastWorkingMirrorCopy)
                            return (index, NSLocalizedString("RECENTLY_UPDATED_SERIES"), "recently_updated", lastWorkingMirrorCopy ?? baseUrl, series)
                        case .newlyAdded:
                            let series = try await helper.getRecentlyAdded(lastWorkingMirror: &lastWorkingMirrorCopy)
                            return (index, NSLocalizedString("RECENTLY_ADDED_SERIES"), "recently_added", lastWorkingMirrorCopy ?? baseUrl, series)
                        case .smartFilter:
                            if let encodedFilter = c.smartFilterEncoded {
                                let filter = try await helper.decodeFilter(encodedFilter, lastWorkingMirror: &lastWorkingMirrorCopy)
                                let series = try await helper.getAllSeriesV2(
                                    filter: filter,
                                    context: .dashboard,
                                    lastWorkingMirror: &lastWorkingMirrorCopy
                                )
                                return (index, c.name, "filter-\(encodedFilter)", lastWorkingMirrorCopy ?? baseUrl, series)
                            } else {
                                return (index, "", "", baseUrl, [])
                            }
                        case .moreInGenre:
                            let genres = try await helper.getAllGenres(context: .dashboard, lastWorkingMirror: &lastWorkingMirrorCopy)
                            guard let randomGenre = genres.randomElement() else {
                                return (index, "", "", baseUrl, [])
                            }
                            let series = try await helper.getMoreIn(
                                genreId: randomGenre.id,
                                pageNum: 0,
                                itemsPerPage: 30,
                                lastWorkingMirror: &lastWorkingMirrorCopy
                            )
                            return (
                                index,
                                String(format: NSLocalizedString("MORE_IN_%@"), randomGenre.title),
                                "morein-\(randomGenre.id)",
                                lastWorkingMirrorCopy ?? baseUrl,
                                series
                            )
                    }
                }
            }

            for try await (index, title, listingId, baseUrl, series) in taskGroup where !series.isEmpty {
                components[index] = .init(
                    title: title,
                    value: .scroller(
                        entries: series.map {
                            $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey).intoLink()
                        },
                        listing: .init(id: listingId, name: title)
                    )
                )
            }
        }

        return .init(components: components.compactMap { $0 })
    }
}

extension KavitaSourceRunner {
    struct LoginResponse: Decodable {
        let apiKey: String?
        let username: String
        let token: String?
        let refreshToken: String?
        let authKeys: [AuthKey]?
        var cookie: String?

        func getApiKey() -> String? {
            authKeys?.first(where: { $0.name == "opds" })?.key ?? apiKey
        }

        struct AuthKey: Decodable {
            let key: String
            let name: String
        }
    }

    static func getLoginResponse(server: URL, username: String, password: String) async -> LoginResponse? {
        guard let loginUrl = URL(string: "api/account/login", relativeTo: server) else {
            return nil
        }

        struct Payload: Encodable {
            let username: String
            let password: String
            let apiKey: String
        }

        let payload = Payload(username: username, password: password, apiKey: "")

        var request = URLRequest(url: loginUrl)
        request.httpMethod = "POST"
        request.httpBody = try? JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try? await URLSession.shared.object(from: request)
    }

    static func getLoginResponse(server: URL, cookies: [HTTPCookie]) async -> LoginResponse? {
        guard
            let cookie = cookies.first(where: { $0.name == ".AspNetCore.Cookies" }),
            let accountUrl = URL(string: "api/account", relativeTo: server)
        else {
            return nil
        }

        var request = URLRequest(url: accountUrl)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in HTTPCookie.requestHeaderFields(with: [cookie]) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var response: LoginResponse? = try? await URLSession.shared.object(from: request)
        response?.cookie = request.value(forHTTPHeaderField: "Cookie")
        return response
    }
}
