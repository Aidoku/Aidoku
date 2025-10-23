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

    var storedTags: [String] = []

    init(sourceKey: String) {
        self.sourceKey = sourceKey
        self.helper = KomgaHelper(sourceKey: sourceKey)
    }

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        let (sort, conditions) = try await helper.getConditions(filters: filters, storedTags: storedTags)
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
                condition: .allOf([.deleted(false)] + conditions),
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

    func getSearchFilters() async throws -> [AidokuRunner.Filter] {
        enum ResultType: String, CaseIterable {
            case libraries
            case genres
            case tags
            case publishers
            case languages
            case ageRatings = "age-ratings"
            case releaseDates = "series/release-dates"
            case sharingLabels = "sharing-labels"
        }
        let result = try await withThrowingTaskGroup(of: (ResultType, Any).self, returning: [ResultType: Any].self) { [helper] taskGroup in
            for type in ResultType.allCases {
                taskGroup.addTask {
                    if type == .libraries {
                        let libraries: [KomgaLibrary] = try await helper.request(path: "/api/v1/\(type.rawValue)")
                        return (type, libraries)
                    } else {
                        let result: [String] = try await helper.request(path: "/api/v1/\(type.rawValue)")
                        return (type, result)
                    }
                }
            }
            var result: [ResultType: Any] = [:]
            for try await value in taskGroup {
                result[value.0] = value.1
            }
            return result
        }
        var filters: [AidokuRunner.Filter] = []

        if let libraryObjects = result[.libraries] as? [KomgaLibrary], libraryObjects.count > 1 {
            filters.append(
                .init(
                    id: "library",
                    title: NSLocalizedString("LIBRARY"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: [NSLocalizedString("ALL")] + libraryObjects.map { $0.name },
                        ids: [""] + libraryObjects.map { $0.id }
                    ))
                )
            )
        }

        if let genres = result[.genres] as? [String], !genres.isEmpty {
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
        if let tags = result[.tags] as? [String], !tags.isEmpty {
            storedTags = tags
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
        if let publishers = result[.publishers] as? [String], !publishers.isEmpty {
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
        if let languages = result[.languages] as? [String], !languages.isEmpty {
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
        if let ratings = result[.ageRatings] as? [String], ratings.count > 1 {
            filters.append(
                .init(
                    id: "age_rating",
                    title: NSLocalizedString("AGE_RATING"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: false,
                        options: ratings
                    ))
                )
            )
        }
        if let releaseDates = result[.releaseDates] as? [String], !releaseDates.isEmpty {
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
        if let labels = result[.sharingLabels] as? [String], !labels.isEmpty {
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

extension KomgaSourceRunner {
    enum HomeListingType {
        case onDeck
        case keepReading
        case recentlyAddedBooks
        case recentlyAddedSeries
        case recentlyUpdatedSeries
        case recentlyReadBooks

        var id: String {
            switch self {
                case .onDeck: "on_deck"
                case .keepReading: "keep_reading"
                case .recentlyAddedBooks: "recently_added_books"
                case .recentlyAddedSeries: "recently_added_series"
                case .recentlyUpdatedSeries: "recently_updated_series"
                case .recentlyReadBooks: "recently_read_books"
            }
        }

        var name: String {
            switch self {
                case .onDeck: NSLocalizedString("ON_DECK")
                case .keepReading: NSLocalizedString("KEEP_READING")
                case .recentlyAddedBooks: NSLocalizedString("RECENTLY_ADDED_BOOKS")
                case .recentlyAddedSeries: NSLocalizedString("RECENTLY_ADDED_SERIES")
                case .recentlyUpdatedSeries: NSLocalizedString("RECENTLY_UPDATED_SERIES")
                case .recentlyReadBooks: NSLocalizedString("RECENTLY_READ_BOOKS")
            }
        }

        var isBookBased: Bool {
            switch self {
                case .onDeck, .keepReading, .recentlyAddedBooks, .recentlyReadBooks: true
                case .recentlyAddedSeries, .recentlyUpdatedSeries: false
            }
        }
    }

    func getHome() async throws -> Home {
        let listingTypes: [HomeListingType] = [
            .keepReading,
            .onDeck,
            .recentlyAddedBooks,
            .recentlyAddedSeries,
            .recentlyUpdatedSeries,
            .recentlyReadBooks
        ]
        var components: [HomeComponent?] = Array(repeating: nil, count: listingTypes.count)

        try await withThrowingTaskGroup(of: (Int, AidokuRunner.Listing, [HomeComponent.Value.Link]).self) { [helper, sourceKey] taskGroup in
            for (index, listingType) in listingTypes.enumerated() {
                taskGroup.addTask { [self] in
                    let listing = AidokuRunner.Listing(id: listingType.id, name: listingType.name, kind: .default)
                    let baseUrl = try helper.getConfiguredServer()

                    if listingType.isBookBased {
                        let path: String
                        let method: HttpMethod
                        let body: KomgaSearchBody?

                        switch listingType {
                            case .onDeck:
                                path = "/api/v1/books/ondeck?sort=createdDate%2Cdesc"
                                method = .GET
                                body = nil
                            case .keepReading:
                                path = "/api/v1/books/list?page=0&size=20&sort=readProgress.readDate%2Cdesc"
                                method = .POST
                                body = .init(condition: .allOf([.readStatus(.inProgress), .deleted(false)]))
                            case .recentlyAddedBooks:
                                path = "/api/v1/books/list?page=0&size=20&sort=createdDate%2Cdesc"
                                method = .POST
                                body = .init(condition: .allOf([.deleted(false)]))
                            case .recentlyReadBooks:
                                path = "/api/v1/books/list?page=0&size=20&sort=readProgress.readDate%2Cdesc"
                                method = .POST
                                body = .init(condition: .allOf([.readStatus(.read), .deleted(false)]))
                            default:
                                throw SourceError.message("Invalid listing type")
                        }

                        let res: KomgaPageResponse<[KomgaBook]> = try await helper.request(path: path, method: method, body: body)
                        let links = try await self.createLinks(for: res.content, sourceKey: sourceKey, baseUrl: baseUrl, isBookBased: true)
                        return (index, listing, links)
                    } else {
                        let path: String
                        let method: HttpMethod

                        switch listingType {
                            case .recentlyAddedSeries:
                                path = "/api/v1/series/new?page=0&size=20&oneshot=false&deleted=false"
                                method = .GET
                            case .recentlyUpdatedSeries:
                                path = "/api/v1/series/updated?page=0&size=20&oneshot=false&deleted=false"
                                method = .GET
                            default:
                                throw SourceError.message("Invalid listing type")
                        }

                        let res: KomgaPageResponse<[KomgaSeries]> = try await helper.request(path: path, method: method)
                        let links = try await self.createLinks(for: res.content, sourceKey: sourceKey, baseUrl: baseUrl, isBookBased: false)
                        return (index, listing, links)
                    }
                }
            }

            for try await (index, listing, entries) in taskGroup where !entries.isEmpty {
                components[index] = .init(
                    title: listing.name,
                    value: .scroller(
                        entries: entries,
                        listing: listing
                    )
                )
            }
        }

        return .init(components: components.compactMap { $0 })
    }

    func getListingHome(listing: AidokuRunner.Listing) async throws -> Home? {
        // Check if there are multiple libraries
        let libraries: [KomgaLibrary] = try await helper.request(path: "/api/v1/libraries")

        // If only one library, use default HomeGridView instead of Home-like layout
        guard libraries.count > 1 else { return nil }

        // Extract library ID from listing id (e.g., "library-abc123" -> "abc123")
        let libraryId = String(listing.id.dropFirst("library-".count))

        // Define the 6 listing types for this library
        let listingTypes: [HomeListingType] = [
            .keepReading,
            .onDeck,
            .recentlyAddedBooks,
            .recentlyAddedSeries,
            .recentlyUpdatedSeries,
            .recentlyReadBooks
        ]

        // Create components for each listing type
        var components: [HomeComponent?] = Array(repeating: nil, count: listingTypes.count)

        try await withThrowingTaskGroup(of: (Int, AidokuRunner.Listing, [HomeComponent.Value.Link]).self) { [helper, sourceKey] taskGroup in
            for (index, listingType) in listingTypes.enumerated() {
                taskGroup.addTask { [self] in
                    // Create a listing for this specific type within the library
                    let componentListing = AidokuRunner.Listing(
                        id: "library-\(libraryId)-\(listingType.id)",
                        name: listingType.name,
                        kind: .default
                    )
                    let baseUrl = try helper.getConfiguredServer()

                    if listingType.isBookBased {
                        let path: String
                        let method: HttpMethod
                        let body: KomgaSearchBody?

                        switch listingType {
                            case .onDeck:
                                path = "/api/v1/books/ondeck?library_id=\(libraryId)&size=20&sort=createdDate%2Cdesc"
                                method = .GET
                                body = nil
                            case .keepReading:
                                path = "/api/v1/books/list?page=0&size=20&sort=readProgress.readDate%2Cdesc"
                                method = .POST
                                body = .init(condition: .allOf([
                                    .readStatus(.inProgress),
                                    .deleted(false),
                                    .libraryId(libraryId)
                                ]))
                            case .recentlyAddedBooks:
                                path = "/api/v1/books/list?page=0&size=20&sort=createdDate%2Cdesc"
                                method = .POST
                                body = .init(condition: .allOf([
                                    .deleted(false),
                                    .libraryId(libraryId)
                                ]))
                            case .recentlyReadBooks:
                                path = "/api/v1/books/list?page=0&size=20&sort=readProgress.readDate%2Cdesc"
                                method = .POST
                                body = .init(condition: .allOf([
                                    .readStatus(.read),
                                    .deleted(false),
                                    .libraryId(libraryId)
                                ]))
                            default:
                                throw SourceError.message("Invalid listing type")
                        }

                        let res: KomgaPageResponse<[KomgaBook]> = try await helper.request(path: path, method: method, body: body)
                        let links = try await self.createLinks(for: res.content, sourceKey: sourceKey, baseUrl: baseUrl, isBookBased: true)
                        return (index, componentListing, links)
                    } else {
                        let path: String
                        let method: HttpMethod

                        switch listingType {
                            case .recentlyAddedSeries:
                                path = "/api/v1/series/new?library_id=\(libraryId)&page=0&size=20&oneshot=false&deleted=false"
                                method = .GET
                            case .recentlyUpdatedSeries:
                                path = "/api/v1/series/updated?library_id=\(libraryId)&page=0&size=20&oneshot=false&deleted=false"
                                method = .GET
                            default:
                                throw SourceError.message("Invalid listing type")
                        }

                        let res: KomgaPageResponse<[KomgaSeries]> = try await helper.request(path: path, method: method)
                        let links = try await self.createLinks(for: res.content, sourceKey: sourceKey, baseUrl: baseUrl, isBookBased: false)
                        return (index, componentListing, links)
                    }
                }
            }

            for try await (index, componentListing, entries) in taskGroup where !entries.isEmpty {
                components[index] = .init(
                    title: componentListing.name,
                    value: .scroller(
                        entries: entries,
                        listing: componentListing
                    )
                )
            }
        }

        return .init(components: components.compactMap { $0 })
    }

    private func createLinks<T: Codable>(
        for items: [T],
        sourceKey: String,
        baseUrl: String,
        isBookBased: Bool
    ) async throws -> [HomeComponent.Value.Link] {
        var links: [HomeComponent.Value.Link?] = Array(repeating: nil, count: items.count)
        try await withThrowingTaskGroup(of: (Int, HomeComponent.Value.Link).self) { [helper] taskGroup in
            for (index, item) in items.enumerated() {
                taskGroup.addTask {
                    let link: HomeComponent.Value.Link
                    if isBookBased, let book = item as? KomgaBook {
                        let series: KomgaSeries = try await helper.request(path: "/api/v1/series/\(book.seriesId)")
                        let manga = book.intoManga(sourceKey: sourceKey, baseUrl: baseUrl)
                        let bookTitle = book.metadata.title.isEmpty ? book.name : book.metadata.title
                        let subtitle = "\(book.metadata.number) - \(bookTitle)"
                        link = HomeComponent.Value.Link(
                            title: series.metadata.title.isEmpty ? series.name : series.metadata.title,
                            imageUrl: manga.cover,
                            subtitle: subtitle,
                            value: .manga(manga)
                        )
                    } else if let series = item as? KomgaSeries {
                        let manga = series.intoManga(sourceKey: sourceKey, baseUrl: baseUrl)
                        let subtitle = series.booksCount == 1
                            ? NSLocalizedString("1_BOOK", comment: "")
                            : String(format: NSLocalizedString("%@_BOOKS", comment: ""), String(series.booksCount))
                        link = HomeComponent.Value.Link(
                            title: series.metadata.title.isEmpty ? series.name : series.metadata.title,
                            imageUrl: manga.cover,
                            subtitle: subtitle,
                            value: .manga(manga)
                        )
                    } else {
                        throw SourceError.message("Invalid item type")
                    }
                    return (index, link)
                }
            }
            for try await (index, link) in taskGroup {
                links[index] = link
            }
        }
        return links.compactMap { $0 }
    }
}
