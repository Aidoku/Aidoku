//
//  SuwayomiSource.swift
//  Aidoku
//
//  Created by skitty on 7/1/26.
//

import AidokuRunner
import Foundation

#if canImport(UIKit)
import UIKit
#endif

extension AidokuRunner.Source {
    static func suwayomi(
        key: String = "suwayomi",
        name: String,
        server: String
    ) -> AidokuRunner.Source {
        .init(
            url: nil,
            key: key,
            name: name,
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
                    value: .text(placeholder: NSLocalizedString("AUTHOR_NAME"))
                ),
                .init(
                    id: "artist",
                    title: NSLocalizedString("AUTHOR"),
                    value: .text(placeholder: NSLocalizedString("ARTIST_NAME"))
                )
            ],
            staticSettings: [],
            runner: SuwayomiSourceRunner(sourceKey: key, name: name, server: server)
        )
    }
}

actor SuwayomiSourceRunner: Runner {
    static let sourceKeyPrefix = "suwayomi"

    let sourceKey: String
    let helper: SuwayomiHelper

    let features: SourceFeatures = .init(
        providesListings: true,
        dynamicFilters: true,
        dynamicSettings: true,
        providesImageRequests: true,
        providesBaseUrl: true,
        handlesNotifications: true,
        handlesBasicLogin: true
    )

    private var name: String
    private var server: String

    init(sourceKey: String, name: String, server: String) {
        self.sourceKey = sourceKey
        self.helper = .init(sourceKey: sourceKey)
        self.name = name
        self.server = server
    }

    private enum SortOption: CaseIterable {
        case unreadChapters
        case totalChapters
        case title
        case dateAdded
        case recentlyRead
        case latestFetchedChapter
        case latestUploadedChapter

        var title: String {
            switch self {
                case .unreadChapters: NSLocalizedString("UNREAD_CHAPTERS")
                case .totalChapters: NSLocalizedString("TOTAL_CHAPTERS")
                case .title: NSLocalizedString("SORT_NAME")
                case .dateAdded: NSLocalizedString("SORT_DATE_ADDED")
                case .recentlyRead: NSLocalizedString("LAST_READ")
                case .latestFetchedChapter: NSLocalizedString("LAST_UPDATED")
                case .latestUploadedChapter: NSLocalizedString("SORT_CHAPTER_ADDED")
            }
        }

        var serverOrder: SuwayomiMangaOrderBy? {
            switch self {
                case .title: .title
                case .dateAdded: .inLibraryAt
                case .latestFetchedChapter: .lastFetchedAt
                default: nil
            }
        }
    }

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        struct Payload: Encodable {
            let variables: Variables
            let query = """
                query SearchManga($filter: MangaFilterInput, $orderBy: MangaOrderBy, $orderByType: SortOrder) {
                  mangas(condition: {inLibrary: true}, filter: $filter, orderBy: $orderBy, orderByType: $orderByType) {
                    nodes {
                      artist
                      author
                      id
                      inLibraryAt
                      thumbnailUrl
                      title
                      chapters {
                        totalCount
                      }
                      latestUploadedChapter {
                        uploadDate
                      }
                      latestFetchedChapter {
                        fetchedAt
                      }
                      latestReadChapter {
                        lastReadAt
                      }
                      unreadCount
                      downloadCount
                    }
                  }
                }
                """

            struct Variables: Encodable {
                let filter: SuwayomiMangaFilterInput?
                let orderBy: SuwayomiMangaOrderBy?
                let orderByType: SuwayomiSortOrder?
            }
        }

        let baseUrl = try helper.getConfiguredServer()
        let searchFilter = getSearchFilter(query: query, filters: filters)
        let response: SuwayomiMangaResponse = try await helper.request(body: Payload(variables: .init(
            filter: searchFilter.filter,
            orderBy: searchFilter.serverSort?.orderBy,
            orderByType: searchFilter.serverSort?.orderByType
        )))
        let nodes = sort(response.data.mangas.nodes, sort: searchFilter.localSort) // todo
        let entries = nodes.compactMap { $0.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) }

        return .init(entries: entries, hasNextPage: false)
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        guard let mangaId = Int(manga.key) else { throw SourceError.message("INVALID_KEY") }

        struct Payload: Encodable {
            let variables: Variables
            let query = """
                query GetMangaUpdate($mangaId: Int!) {
                  manga(id: $mangaId) {
                    artist
                    author
                    description
                    id
                    status
                    thumbnailUrl
                    title
                    url
                    genre
                    realUrl
                  }
                  chapters(condition: {mangaId: $mangaId}, orderBy: SOURCE_ORDER, orderByType: DESC) {
                    nodes {
                      id
                      url
                      chapterNumber
                      name
                      uploadDate
                      scanlator
                      sourceOrder
                      mangaId
                    }
                  }
                }
                """

            struct Variables: Encodable {
                let mangaId: Int
            }
        }

        let baseUrl = try helper.getConfiguredServer()
        let response: SuwayomiMangaUpdateResponse = try await helper.request(
            body: Payload(variables: .init(mangaId: mangaId))
        )

        var manga = manga
        if needsDetails, let updatedManga = response.data.manga.intoManga(sourceKey: sourceKey, baseUrl: baseUrl) {
            manga = manga.copy(from: updatedManga)
        }
        if needsChapters {
            manga.chapters = response.data.chapters.nodes.map {
                $0.intoChapter(baseUrl: baseUrl)
            }
        }
        return manga
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        guard let chapterId = Int(chapter.key) else { throw SourceError.message("INVALID_KEY") }

        struct Payload: Encodable {
            let variables: Variables
            let query = """
                mutation GetPages($chapterId: Int!) {
                  fetchChapterPages(input: {chapterId: $chapterId}) {
                    pages
                  }
                }
                """

            struct Variables: Encodable {
                let chapterId: Int
            }
        }

        let baseUrl = try helper.getConfiguredServer()
        let response: SuwayomiPagesResponse = try await helper.request(
            body: Payload(variables: .init(chapterId: chapterId))
        )
        return response.data.fetchChapterPages.pages.compactMap {
            URL(string: $0, relativeTo: baseUrl).map { .init(content: .url(url: $0)) }
        }
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        .init(entries: [], hasNextPage: false)
    }

    func getImageRequest(url: String, context: PageContext?) async throws -> URLRequest {
        guard let url = URL(string: url) else { throw SourceError.message("INVALID_URL") }
        var request = URLRequest(url: url)
        helper.authorize(request: &request)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    func getSettings() async throws -> [Setting] {
        var settings: [Setting] = [
            .init(
                title: "SOURCE_NAME",
                value: .group(.init(
                    footer: "SOURCE_NAME_INFO",
                    items: [
                        .init(
                            key: "name",
                            notification: "name_change",
                            value: .text(.init(
                                placeholder: NSLocalizedString("SUWAYOMI"),
                                returnKeyType: UIReturnKeyType.done.rawValue,
                                autocorrectionDisabled: true,
                                defaultValue: name
                            ))
                        )
                    ]
                ))
            ),
            .init(
                title: "SERVER_URL",
                value: .group(.init(
                    footer: "SERVER_URL_INFO",
                    items: [
                        .init(
                            key: "server",
                            notification: "server_change",
                            refreshes: ["settings", "content"],
                            value: .text(.init(
                                placeholder: "http://127.0.0.1:4567",
                                autocapitalizationType: UITextAutocapitalizationType.none.rawValue,
                                keyboardType: UIKeyboardType.URL.rawValue,
                                returnKeyType: UIReturnKeyType.done.rawValue,
                                autocorrectionDisabled: true,
                                defaultValue: server
                            ))
                        )
                    ]
                ))
            )
        ]
        let isLoggedIn = UserDefaults.standard.value(forKey: "\(sourceKey).login") != nil
        var shouldShowLoginSetting = isLoggedIn
        if !shouldShowLoginSetting {
            let loginType = try await helper.getLoginType()
            if let loginType {
                shouldShowLoginSetting = loginType != .none
            }
        }
        if shouldShowLoginSetting {
            settings.append(contentsOf: [
                .init(
                    value: .group(.init(
                        items: [
                            .init(
                                key: "login",
                                title: "LOGIN",
                                notification: "login",
                                requires: "server",
                                refreshes: ["content", "filters"],
                                value: .login(.init(method: .basic))
                            )
                        ]
                    ))
                )
            ])
        }
        return settings
    }

    func getBaseUrl() async throws -> URL? {
        try helper.getConfiguredServer()
    }

    func handleBasicLogin(key _: String, username: String, password: String) async throws -> Bool {
        let server = try helper.getConfiguredServer()

        guard let response = await SuwayomiHelper.checkLogin(server: server, username: username, password: password) else {
            return false
        }

        if let cookie = response.cookie {
            UserDefaults.standard.setValue(cookie, forKey: "\(sourceKey).cookie")
        }
        if let accessToken = response.accessToken, let refreshToken = response.refreshToken {
            UserDefaults.standard.setValue(accessToken, forKey: "\(sourceKey).token")
            UserDefaults.standard.setValue(refreshToken, forKey: "\(sourceKey).refreshToken")
        }

        return true
    }

    func handleNotification(notification: String) async throws {
        // clear additional login values when logging out
        switch notification {
            case "login":
                let isLoggedIn = UserDefaults.standard.value(forKey: "\(sourceKey).login") != nil
                if !isLoggedIn {
                    UserDefaults.standard.removeObject(forKey: "\(sourceKey).cookie")
                    UserDefaults.standard.removeObject(forKey: "\(sourceKey).token")
                    UserDefaults.standard.removeObject(forKey: "\(sourceKey).refreshToken")
                }

            case "name_change":
                let key = "\(sourceKey).name"
                let newValue = UserDefaults.standard.string(forKey: key) ?? ""

                // ensure normalized value
                let normalizedValue = newValue.trimmingCharacters(in: .whitespaces)
                if newValue != normalizedValue {
                    UserDefaults.standard.set(normalizedValue, forKey: key)
                    return // the function will be called again with the new value
                }

                if newValue != name {
                    // update db source config with new name
                    name = newValue
                    updateSourceConfig(updateSourceList: true)
                }

            case "server_change":
                let key = "\(sourceKey).server"
                let newValue = UserDefaults.standard.string(forKey: key) ?? ""

                // ensure normalized value
                let normalizedValue = (newValue.last == "/" ? String(newValue[..<newValue.index(before: newValue.endIndex)]) : newValue)
                    .trimmingCharacters(in: .whitespaces)
                if newValue != normalizedValue {
                    UserDefaults.standard.set(normalizedValue, forKey: key)
                    return // the function will be called again with the new value
                }

                if newValue != server {
                    // update db source config with new server url
                    server = newValue
                    updateSourceConfig()
                }

            default:
                break
        }
    }

    private func updateSourceConfig(updateSourceList: Bool = false) {
        let config = CustomSourceConfig.suwayomi(.init(key: sourceKey, name: name, server: server))
        SourceManager.shared.updateCustomSource(key: sourceKey, config: config, updateSourceList: updateSourceList)
    }
}

// MARK: Search Filters
extension SuwayomiSourceRunner {
    func getSearchFilters() async throws -> [AidokuRunner.Filter] {
        async let categories = getCategories()
        async let tags = getTags()

        let categoryItems = try await categories
        let tagItems = try await tags

        var filters: [AidokuRunner.Filter] = [
            .init(
                id: "sort",
                title: NSLocalizedString("SORT"),
                value: .sort(
                    canAscend: true,
                    options: SuwayomiSourceRunner.SortOption.allCases.map(\.title),
                    defaultValue: .init(index: 3, ascending: false)
                )
            ),
            .init(
                id: "status",
                title: NSLocalizedString("STATUS"),
                value: .multiselect(.init(
                    canExclude: true,
                    options: SuwayomiMangaStatus.allCases.map(\.title),
                    ids: SuwayomiMangaStatus.allCases.map(\.rawValue)
                ))
            )
        ]

        if categoryItems.count > 1 {
            filters.append(
                .init(
                    id: "category",
                    title: NSLocalizedString("CATEGORY"),
                    value: .select(.init(
                        options: [NSLocalizedString("ALL"), NSLocalizedString("NONE")] + categoryItems.map(\.title),
                        ids: ["", "0"] + categoryItems.map(\.id)
                    ))
                )
            )
        }

        if !tagItems.isEmpty {
            filters.append(
                .init(
                    id: "genre",
                    title: NSLocalizedString("TAG"),
                    value: .multiselect(.init(
                        isGenre: true,
                        canExclude: true,
                        usesTagStyle: true,
                        options: tagItems.map(\.title),
                        ids: tagItems.map(\.id)
                    ))
                )
            )
        }

        return filters
    }

    private struct SearchFilter {
        let filter: SuwayomiMangaFilterInput?
        let serverSort: (orderBy: SuwayomiMangaOrderBy, orderByType: SuwayomiSortOrder)?
        let localSort: (option: SortOption, ascending: Bool)?
    }

    private func getSearchFilter(query: String?, filters: [AidokuRunner.FilterValue]) -> SearchFilter {
        var filterInput: [SuwayomiMangaFilterInput] = []
        var sortOption = SortOption.allCases[3]
        var sortAscending = false

        if let query, !query.isEmpty {
            filterInput.append(.init(or: [
                .init(title: .includesInsensitive(query)),
                .init(url: .includesInsensitive(query)),
                .init(artist: .includesInsensitive(query)),
                .init(author: .includesInsensitive(query)),
                .init(description: .includesInsensitive(query))
            ]))
        }

        for filter in filters {
            switch filter {
                case let .text(id, value):
                    switch id {
                        case "author": filterInput.append(.init(author: .includesInsensitive(value)))
                        case "artist": filterInput.append(.init(artist: .includesInsensitive(value)))
                        default: break
                    }
                case let .sort(value):
                    sortOption = SortOption.allCases[safe: Int(value.index)] ?? sortOption
                    sortAscending = value.ascending
                case let .select(id, value):
                    switch id {
                        case "category":
                            filterInput.append(.init(
                                categoryId: value == "0"
                                    ? .isNull(true)
                                    : Int(value).flatMap { .equalTo($0) }
                            ))
                        case "genre":
                            filterInput.append(.init(genre: .includesInsensitive(value)))
                        default:
                            break
                    }
                case let .multiselect(id, included, excluded):
                    switch id {
                        case "status":
                            let included = included.compactMap(SuwayomiMangaStatus.init)
                            let excluded = excluded.compactMap(SuwayomiMangaStatus.init)
                            if !included.isEmpty {
                                filterInput.append(.init(status: .in(included)))
                            }
                            if !excluded.isEmpty {
                                filterInput.append(.init(status: .notEqualToAny(excluded)))
                            }
                        case "genre":
                            filterInput.append(contentsOf: included.map {
                                .init(genre: .includesInsensitive($0))
                            })
                            filterInput.append(contentsOf: excluded.map {
                                .init(genre: .notIncludesInsensitive($0))
                            })
                        default:
                            break
                    }
                default:
                    continue
            }
        }

        let filter = filterInput.isEmpty ? nil : SuwayomiMangaFilterInput(and: filterInput)
        let serverSort = sortOption.serverOrder.map { ($0, sortAscending ? SuwayomiSortOrder.asc : .desc) }
        let localSort = sortOption.serverOrder == nil ? (sortOption, sortAscending) : nil
        return .init(filter: filter, serverSort: serverSort, localSort: localSort)
    }

    private func sort(_ nodes: [SuwayomiMangaNode], sort: (option: SortOption, ascending: Bool)?) -> [SuwayomiMangaNode] {
        guard let sort else { return nodes }
        let result = switch sort.option {
            case .totalChapters:
                nodes.sorted { ($0.chapters?.totalCount ?? 0) < ($1.chapters?.totalCount ?? 0) }
            case .latestUploadedChapter:
                nodes.sorted { ($0.latestUploadedChapter?.uploadDate ?? "") < ($1.latestUploadedChapter?.uploadDate ?? "") }
            case .recentlyRead:
                nodes.sorted { ($0.latestReadChapter?.lastReadAt ?? "") < ($1.latestReadChapter?.lastReadAt ?? "") }
            case .unreadChapters:
                nodes.sorted { ($0.unreadCount ?? 0) < ($1.unreadCount ?? 0) }
            default:
                nodes
        }
        return sort.ascending ? result : Array(result.reversed())
    }

    struct FilterItem {
        let id: String
        let title: String
    }

    private func getCategories() async throws -> [FilterItem] {
        struct Payload: Encodable {
            let variables = Variables()
            let query = """
                query GetCategories($orderBy: CategoryOrderBy, $orderByType: SortOrder) {
                  categories(orderBy: $orderBy, orderByType: $orderByType) {
                    nodes {
                      id
                      name
                    }
                  }
                }
                """

            struct Variables: Encodable {
                let orderBy = "ORDER"
                let orderByType = "ASC"
            }
        }

        let response: SuwayomiCategoryResponse = try await helper.request(body: Payload())
        return response.data.categories.nodes.map {
            .init(id: String($0.id), title: $0.name)
        }
    }

    private func getTags() async throws -> [FilterItem] {
        struct Payload: Encodable {
            let query = """
                query GetMangaTags {
                  mangas(condition: {inLibrary: true}) {
                    nodes {
                      genre
                    }
                  }
                }
                """
        }

        let response: SuwayomiMangaResponse = try await helper.request(body: Payload())
        return response.data.mangas.nodes
            .flatMap { $0.genre ?? [] }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { .init(id: $0, title: $0) }
    }
}
