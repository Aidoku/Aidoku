//
//  Source.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation

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
    let defaultValue: DefaultValue?

    let filters: [FilterInfo]?
    let options: [String]?

    let canExclude: Bool?
    let canAscend: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case defaultValue = "default"
        case filters
        case options
        case canExclude
        case canAscend
    }
}

class Source: Identifiable {

    struct SourceManifest: Codable {
        let info: SourceInfo
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

    var actor: SourceActor!

    init(from url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url.appendingPathComponent("source.json"))
        manifest = try JSONDecoder().decode(SourceManifest.self, from: data)

        let bytes = try Data(contentsOf: url.appendingPathComponent("main.wasm"))
        globalStore = WasmGlobalStore(id: manifest.info.id,
                                      wrapper: WasmWrapper(module: [UInt8](bytes)),
                                      module: WasmWebKitManager.shared.createModule([UInt8](bytes)))
        actor = SourceActor(source: self)

        exportFunctions()
        loadSettings()

//        handlesImageRequests = (try? vm.function(named: "modify_image_request")) != nil
    }

    func exportFunctions() {
        globalStore.export(named: "print", namespace: "env", block: self.printFunction)
        globalStore.export(named: "abort", namespace: "env", block: self.abort)

        WasmAidoku(globalStore: globalStore).export()
        WasmStd(globalStore: globalStore).export()
        WasmDefaults(globalStore: globalStore).export()
        WasmNet(globalStore: globalStore).export()
        WasmJson(globalStore: globalStore).export()
        WasmHtml(globalStore: globalStore).export()
    }

    var printFunction: @convention(block) (Int32, Int32) -> Void {
        { string, length in
            print(self.globalStore.readString(offset: string, length: length) ?? "")
        }
    }

    var abort: (Int32, Int32, Int32, Int32) -> Void {
        { msg, fileName, line, column in
            let messageLength = self.globalStore.readBytes(offset: msg - 4, length: 1)?.first ?? 0
            let fileLength = self.globalStore.readBytes(offset: fileName - 4, length: 1)?.first ?? 0

            let message = self.globalStore.readString(offset: msg, length: Int32(messageLength))
            let file = self.globalStore.readString(offset: fileName, length: Int32(fileLength))

            print("[Abort] \(message ?? "") \(file ?? ""):\(line):\(column)")
        }
    }
}

// MARK: - Settings
extension Source {

    func loadSettings() {
        if let data = try? Data(contentsOf: url.appendingPathComponent("settings.json")),
           let settingsPlist = try? JSONDecoder().decode([SettingItem].self, from: data) {
            settingItems = settingsPlist

            // Load defaults
            var defaults: [String: Any] = [:]
            var defaultLanguages: [String] = []

            // if local language is supported, use it
            for lang in languages where lang.code == Locale.current.languageCode {
                defaultLanguages.append(lang.value ?? lang.code)
            }
            // otherwise, fall back to source-defined default
            if defaultLanguages.isEmpty {
                for lang in languages where lang.isDefault ?? false {
                    defaultLanguages.append(lang.value ?? lang.code)
                }
            }

            defaults["\(id).languages"] = defaultLanguages

            for (i, item) in settingItems.enumerated() where item.type == "group" {
                for (j, subItem) in (item.items ?? []).enumerated() {
                    if let itemKey = subItem.key {
                        let key = "\(id).\(itemKey)"
                        settingItems[i].items?[j].key = key
                        if let requires = subItem.requires {
                            settingItems[i].items?[j].requires = "\(id).\(requires)"
                        } else if let requires = subItem.requiresFalse {
                            settingItems[i].items?[j].requiresFalse = "\(id).\(requires)"
                        }
                        switch subItem.type {
                        case "switch":
                            defaults[key] = subItem.defaultValue?.boolValue
//                        case "select", "text":
//                            defaults[key] = subItem.defaultValue?.stringValue
                        case "multi-select":
                            defaults[key] = subItem.defaultValue?.stringArrayValue
                        default:
                            defaults[key] = subItem.defaultValue?.stringValue
                        }
                    }
                }
            }

            UserDefaults.standard.register(defaults: defaults)
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
            return CheckFilter(name: filter.name ?? "", canExclude: filter.canExclude ?? false, value: filter.defaultValue?.boolValue)
        case "genre":
            return GenreFilter(name: filter.name ?? "", canExclude: filter.canExclude ?? false, value: filter.defaultValue?.boolValue)
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

    func fetchSearchManga(query: String, filters: [FilterBase] = [], page: Int = 1) async throws -> MangaPageResult {
        var newFilters = filters
        newFilters.append(TitleFilter(value: query))
        return try await actor.getMangaList(filters: newFilters, page: page)
    }

    func getMangaList(filters: [FilterBase], page: Int = 1) async throws -> MangaPageResult {
        try await actor.getMangaList(filters: filters, page: page)
    }

    func getMangaListing(listing: Listing, page: Int = 1) async throws -> MangaPageResult {
        try await actor.getMangaListing(listing: listing, page: page)
    }

    func getMangaDetails(manga: Manga) async throws -> Manga {
        try await actor.getMangaDetails(manga: manga)
    }

    func getChapterList(manga: Manga) async throws -> [Chapter] {
        try await actor.getChapterList(manga: manga)
    }

    func getPageList(chapter: Chapter) async throws -> [Page] {
        try await actor.getPageList(chapter: chapter)
    }

    func getImageRequest(url: String) async throws -> WasmRequestObject {
        try await actor.getImageRequest(url: url)
    }

    func handleUrl(url: String) async throws -> DeepLink {
        try await actor.handleUrl(url: url)
    }

    func performAction(key: String) {
        Task {
            try? await actor.handleNotification(notification: key)
        }
    }
}
