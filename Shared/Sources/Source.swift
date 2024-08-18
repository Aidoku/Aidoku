//
//  Source.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import WasmInterpreter
import CWasm3

struct SourceInfo: Codable {
    let id: String
    let lang: String
    let name: String
    let version: Int
    let url: String?
    let urls: [String]?
    let nsfw: Int?
}

struct LanguageInfo: Codable {
    let code: String
    let value: String?
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case code
        case value
        case isDefault = "default"
    }
}

struct FilterInfo: Codable {
    let type: String

    let name: String?
    let defaultValue: JsonAnyValue?
    let id: JsonAnyValue?

    let filters: [FilterInfo]?
    let options: [String]?

    let canExclude: Bool?
    let canAscend: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case defaultValue = "default"
        case id
        case filters
        case options
        case canExclude
        case canAscend
    }
}

class Source: Identifiable {

    struct SourceManifest: Codable {
        let info: SourceInfo
        let languageSelectType: String?
        let languages: [LanguageInfo]?
        let listings: [Listing]?
        let filters: [FilterInfo]?
    }

    var id: String {
        manifest.info.id
    }
    var url: URL
    var manifest: SourceManifest

    var filters: [FilterBase] = []
    var defaultFilters: [FilterBase] = []
    var listings: [Listing] {
        manifest.listings ?? []
    }

    var languages: [LanguageInfo] {
        manifest.languages ?? []
    }
    var settingItems: [SettingItem] = []

    var titleSearchable: Bool {
        filters.contains { $0 is TitleFilter }
    }
    var authorSearchable: Bool {
        filters.contains { $0 is AuthorFilter }
    }
    var filterable: Bool {
        filters.contains { !($0 is TextFilter) }
    }

    var handlesImageRequests = false
    var needsFilterRefresh = true

    var globalStore: WasmGlobalStore
    var netModule: WasmNet

    var actor: SourceActor!

    init(from url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url.appendingPathComponent("source.json"))
        manifest = try JSONDecoder().decode(SourceManifest.self, from: data)

        let bytes = try Data(contentsOf: url.appendingPathComponent("main.wasm"))
        let vm = try WasmInterpreter(stackSize: 512 * 1024, module: [UInt8](bytes))
        globalStore = WasmGlobalStore(id: manifest.info.id, vm: vm)
        netModule = WasmNet(globalStore: globalStore)
        actor = SourceActor(source: self)

        exportFunctions()
        loadSettings()

        handlesImageRequests = (try? vm.function(named: "modify_image_request")) != nil
        initialize()
    }

    func toInfo() -> SourceInfo2 {
        SourceInfo2(
            sourceId: manifest.info.id,
            iconUrl: url.appendingPathComponent("Icon.png"),
            name: manifest.info.name,
            lang: manifest.info.lang,
            version: manifest.info.version,
            contentRating: SourceInfo2.ContentRating(rawValue: manifest.info.nsfw ?? 0) ?? .safe
        )
    }

    func exportFunctions() {
        try? globalStore.vm.addImportHandler(named: "print", namespace: "env", block: self.printFunction)
        try? globalStore.vm.addImportHandler(named: "abort", namespace: "env", block: self.abort)

        WasmAidoku(globalStore: globalStore).export()
        WasmStd(globalStore: globalStore).export()
        WasmDefaults(globalStore: globalStore).export()
        netModule.export()
        WasmJson(globalStore: globalStore).export()
        WasmHtml(globalStore: globalStore).export()
    }

    var printFunction: (Int32, Int32) -> Void {
        { string, length in
            LogManager.logger.log(self.globalStore.readString(offset: string, length: length) ?? "")
        }
    }

    // needed for assemblyscript
    var abort: (Int32, Int32, Int32, Int32) -> Void {
        { msg, fileName, line, column in
            let messageLength = self.globalStore.readBytes(offset: msg - 4, length: 1)?.first ?? 0
            let fileLength = self.globalStore.readBytes(offset: fileName - 4, length: 1)?.first ?? 0

            let message = self.globalStore.readString(offset: msg, length: Int32(messageLength))
            let file = self.globalStore.readString(offset: fileName, length: Int32(fileLength))

            LogManager.logger.error("[\(self.id)] [Abort] \(message ?? "") \(file ?? ""):\(line):\(column)")

            // break out of the current wasm execution to prevent unreachable from being called (prevents a crash)
            set_should_yield_next()
        }
    }
}

// MARK: - Settings
extension Source {

    // swiftlint:disable:next cyclomatic_complexity
    func loadSettings() {
        var defaultLanguages: [String] = []

        if !languages.isEmpty {
            // if local language is supported, use it
            let preferredLanguages = Locale.preferredLanguages.map { Locale(identifier: $0).languageCode }
            for lang in languages where preferredLanguages.contains(lang.code) {
                defaultLanguages.append(lang.value ?? lang.code)
            }
            // otherwise, fall back to source-defined default
            if defaultLanguages.isEmpty {
                for lang in languages where lang.isDefault ?? false {
                    defaultLanguages.append(lang.value ?? lang.code)
                }
            }
            // if no default, use first
            if defaultLanguages.isEmpty, let lang = languages.first {
                defaultLanguages.append(lang.value ?? lang.code)
            }

            if manifest.languageSelectType == "single", let first = defaultLanguages.first {
                defaultLanguages = [first]
            }
        }

        if let data = try? Data(contentsOf: url.appendingPathComponent("settings.json")),
           let settingsPlist = try? JSONDecoder().decode([SettingItem].self, from: data) {
            settingItems = settingsPlist

            // Load defaults
            var defaults: [String: Any] = [:]

            defaults["\(id).languages"] = defaultLanguages

            for (i, item) in settingItems.enumerated() where item.type == "group" {
                for (j, subItem) in (item.items ?? []).enumerated() {
                    if let itemKey = subItem.key {
                        let key = "\(id).\(itemKey)"
                        settingItems[i].items?[j].key = key
                        if let urlKey = settingItems[i].items?[j].urlKey {
                            settingItems[i].items?[j].urlKey = "\(id).\(urlKey)"
                        }
                        if let requires = subItem.requires {
                            settingItems[i].items?[j].requires = "\(id).\(requires)"
                        } else if let requires = subItem.requiresFalse {
                            settingItems[i].items?[j].requiresFalse = "\(id).\(requires)"
                        }
                        switch subItem.type {
                        case "switch":
                            defaults[key] = subItem.defaultValue?.boolValue
                        case "select", "text":
                            defaults[key] = subItem.defaultValue?.stringValue
                        case "multi-select", "multi-single-select":
                            defaults[key] = subItem.defaultValue?.stringArrayValue
                        case "stepper":
                            defaults[key] = subItem.defaultValue?.doubleValue
                        default:
                            defaults[key] = subItem.defaultValue?.stringValue
                        }
                    }
                }
            }

            UserDefaults.standard.register(defaults: defaults)
        } else {
            UserDefaults.standard.register(defaults: ["\(id).languages": defaultLanguages])
        }
    }
}

// MARK: - Get Functions
extension Source {

    func getDefaultFilters() -> [FilterBase] {
        guard (defaultFilters.isEmpty || needsFilterRefresh) && !filters.isEmpty else { return defaultFilters }

        defaultFilters = []

        for filter in filters {
            if let filter = filter as? GroupFilter {
                for subFilter in filter.filters {
                    if let subFilter = subFilter as? CheckFilter, subFilter.defaultValue != nil {
                        defaultFilters.append(subFilter)
                    }
                }
            } else if !(filter is TitleFilter) && !(filter is AuthorFilter) {
                defaultFilters.append(filter)
            }
        }

        return defaultFilters
    }

    func getDefaultLanguages() -> [String] {
        (UserDefaults.standard.array(forKey: "\(id).languages") as? [String]) ?? []
    }

    func parseFilter(from filter: FilterInfo) -> FilterBase? {
        switch filter.type {
        case "title": return TitleFilter()
        case "author": return AuthorFilter()
        case "select":
            return SelectFilter(
                name: filter.name ?? "",
                options: filter.options ?? [],
                value: filter.defaultValue?.intValue ?? 0
            )
        case "sort":
            let value = filter.defaultValue?.objectValue
            return SortFilter(
                name: filter.name ?? "",
                options: filter.options ?? [],
                canAscend: filter.canAscend ?? false,
                value: value?["index"] != nil ? SortSelection(index: value?["index"]?.intValue ?? 0,
                                                              ascending: value?["ascending"]?.boolValue ?? false)
                                              : SortSelection(index: 0, ascending: false)
            )
        case "check":
            return CheckFilter(name: filter.name ?? "", canExclude: filter.canExclude ?? false, id: filter.id, value: filter.defaultValue?.boolValue)
        case "genre":
            return GenreFilter(name: filter.name ?? "", canExclude: filter.canExclude ?? false, id: filter.id, value: filter.defaultValue?.boolValue)
        case "group":
            return GroupFilter(name: filter.name ?? "", filters: filter.filters?.compactMap { parseFilter(from: $0) } ?? [])
        default: break
        }
        return nil
    }

    func getFilters() async throws -> [FilterBase] {
        guard filters.isEmpty || needsFilterRefresh else { return filters }

        filters = []

        var filterObjects: [FilterInfo] = []

        if let filters = manifest.filters {
            filterObjects = filters
        } else if let data = try? Data(contentsOf: url.appendingPathComponent("filters.json")),
                  let filters = try? JSONDecoder().decode([FilterInfo].self, from: data) {
            filterObjects = filters
        }

        for filter in filterObjects {
            if let result = parseFilter(from: filter) {
                filters.append(result)
            }
        }

        _ = getDefaultFilters()

        needsFilterRefresh = false

        return filters
    }

    func initialize() {
        Task {
            try? await actor.initialize()
        }
    }

    func fetchSearchManga(query: String, filters: [FilterBase] = [], page: Int = 1) async throws -> MangaPageResult {
        var newFilters = filters
        newFilters.append(TitleFilter(value: query))
        return await actor.getMangaList(filters: newFilters, page: page)
    }

    func getMangaList(filters: [FilterBase], page: Int = 1) async throws -> MangaPageResult {
        await actor.getMangaList(filters: filters, page: page)
    }

    func getMangaListing(listing: Listing, page: Int = 1) async throws -> MangaPageResult {
        await actor.getMangaListing(listing: listing, page: page)
    }

    func getMangaDetails(manga: Manga) async throws -> Manga {
        try await actor.getMangaDetails(manga: manga)
    }

    func getChapterList(manga: Manga) async throws -> [Chapter] {
        await actor.getChapterList(manga: manga)
    }

    func getPageList(chapter: Chapter, skipDownloadedCheck: Bool = false) async throws -> [Page] {
        if !skipDownloadedCheck {
            if await DownloadManager.shared.isChapterDownloaded(chapter: chapter) {
                return await DownloadManager.shared.getDownloadedPages(for: chapter)
            }
        }
        return await actor.getPageList(chapter: chapter)
    }

    func getPageListWithoutContents(chapter: Chapter) async throws -> [Page] {
        if await DownloadManager.shared.isChapterDownloaded(chapter: chapter) {
            return await DownloadManager.shared.getDownloadedPagesWithoutContents(for: chapter)
        }

        return await actor.getPageList(chapter: chapter)
    }

    func getImageRequest(url: String) async throws -> WasmRequestObject {
        try await actor.getImageRequest(url: url)
    }

    func modifyUrlRequest(request: URLRequest) -> URLRequest? {
        guard !netModule.isRateLimited() else { return nil }
        return netModule.modifyRequest(request)
    }

    func handleUrl(url: String) async throws -> DeepLink {
        try await actor.handleUrl(url: url)
    }

    func performAction(key: String) {
        Task {
            await actor.handleNotification(notification: key)
        }
    }
}
