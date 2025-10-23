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
        dynamicListings: true,
        providesImageRequests: true,
        providesBaseUrl: true,
        handlesBasicLogin: true
    )

    init(sourceKey: String) {
        self.sourceKey = sourceKey
        self.helper = .init(sourceKey: sourceKey)
    }

    struct FilterItem {
        let id: String
        let title: String
    }

    var storedGenres: [FilterItem] = []
    var storedTags: [FilterItem] = []

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        let filter = try await helper.getSearchFilter(
            query: query,
            filters: filters,
            storedGenres: storedGenres,
            storedTags: storedTags
        )
        let res: [KavitaSeries] = try await helper.request(
            path: "/api/series/v2",
            method: .POST,
            body: JSONEncoder().encode(filter)
        )
        let baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()
        return .init(
            entries: res.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
            hasNextPage: false
        )
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        let baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()

        var manga = manga

        if needsDetails {
            let series: KavitaSeries = try await helper.request(path: "/api/Series/\(manga.key)")
            let metadata: KavitaSeriesMetadata = try await helper.request(path: "/api/Series/metadata?seriesId=\(manga.key)")
            manga = manga.copy(from: series.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey, metadata: metadata))
        }

        if needsChapters {
            let volumes: [KavitaVolume] = try await helper.request(path: "/api/Series/volumes?seriesId=\(manga.key)")
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
        let chapter: KavitaVolume.Chapter = try await helper.request(
            path: "/api/Series/chapter?chapterId=\(chapter.key)"
        )

        let baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()

        return (0..<chapter.pages).compactMap { page in
            let url = "\(baseUrl)/api/Reader/image?chapterId=\(chapter.id)&page=\(page)&apiKey=\(apiKey)&extractPdf=true"
            return URL(string: url).flatMap {
                .init(content: .url(url: $0))
            }
        }
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        if listing.id.hasPrefix("library-") {
            let id = String(listing.id[listing.id.index(listing.id.startIndex, offsetBy: 8)...])

            let filter = KavitaFilterV2(
                statements: [.init(comparison: .equal, field: .libraries, value: id)],
            )
            let res: [KavitaSeries] = try await helper.request(
                path: "/api/series/v2",
                method: .POST,
                body: JSONEncoder().encode(filter)
            )
            let baseUrl = try helper.getConfiguredServer()
            let apiKey = helper.getApiKey()
            return .init(
                entries: res.map { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey) },
                hasNextPage: false
            )
        }
        throw SourceError.message("Invalid listing")
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
                taskGroup.addTask {
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
                    let result: [Result] = try await helper.request(path: type.path)
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
        let libraries: [KavitaLibrary] = try await helper.request(path: "/api/library/libraries")
        return libraries.map {
            .init(id: "library-\($0.id)", name: $0.name, kind: .default)
        }
    }

    func getImageRequest(url: String, context: PageContext?) async throws -> URLRequest {
        guard let url = URL(string: url) else { throw SourceError.message("Invalid URL") }
        var request = URLRequest(url: url)
//        request.setValue(helper.getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    func getBaseUrl() async throws -> URL? {
        URL(string: try helper.getConfiguredServer())
    }

    func handleBasicLogin(key _: String, username: String, password: String) async throws -> Bool {
        let server = try helper.getConfiguredServer()

        guard let loginUrl = URL(string: server + "/api/account/login") else {
            return false
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

        struct Response: Decodable {
            let apiKey: String
            let username: String
            let token: String
            let refreshToken: String
        }
        let response: Response? = try? await URLSession.shared.object(from: request)

        guard let response, response.username == username else {
            return false
        }

        UserDefaults.standard.setValue(response.apiKey, forKey: "\(sourceKey).apiKey")
        UserDefaults.standard.setValue(response.token, forKey: "\(sourceKey).token")
        UserDefaults.standard.setValue(response.refreshToken, forKey: "\(sourceKey).refreshToken")

        return true
    }
}

extension KavitaSourceRunner {
    func getHome() async throws -> Home {
        let dashComponents: [KavitaDashComponent] = try await helper.request(path: "/api/stream/dashboard?visibleOnly=true")

        let baseUrl = try helper.getConfiguredServer()
        let apiKey = helper.getApiKey()

        var components: [HomeComponent?] = Array(repeating: nil, count: dashComponents.count)

        try await withThrowingTaskGroup(of: (Int, String, [KavitaSeries]).self) { [helper, sourceKey] taskGroup in
            for (index, c) in dashComponents.enumerated() {
                taskGroup.addTask {
                    switch c.streamType {
                        case .onDeck:
                            let series = try await helper.getOnDeck()
                            return (index, NSLocalizedString("ON_DECK"), series)
                        case .recentlyUpdated:
                            let series = try await helper.getRecentlyUpdatedSeries()
                            return (index, NSLocalizedString("RECENTLY_UPDATED_SERIES"), series)
                        case .newlyAdded:
                            let series = try await helper.getRecentlyAdded()
                            return (index, NSLocalizedString("RECENTLY_ADDED_SERIES"), series)
                        case .smartFilter:
                            if let encodedFilter = c.smartFilterEncoded {
                                let filter = try await helper.decodeFilter(encodedFilter)
                                let series = try await helper.getAllSeriesV2(filter: filter, context: .dashboard)
                                return (index, c.name, series)
                            } else {
                                return (index, "", [])
                            }
                        case .moreInGenre:
                            let genres = try await helper.getAllGenres()
                            guard let randomGenre = genres.randomElement() else {
                                return (index, "", [])
                            }
                            let series = try await helper.getMoreIn(genreId: randomGenre.id, pageNum: 0, itemsPerPage: 30)
                            return (index, String(format: NSLocalizedString("MORE_IN_%@"), randomGenre.title), series)
                    }
                }
            }

            for try await (index, title, series) in taskGroup where !series.isEmpty {
                components[index] = .init(
                    title: title,
                    value: .scroller(
                        entries: series.map {
                            $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl, apiKey: apiKey).intoLink()
                        },
                        listing: nil
                    )
                )
            }
        }

        return .init(components: components.compactMap { $0 })
    }
}
