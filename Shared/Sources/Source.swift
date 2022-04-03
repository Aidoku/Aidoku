//
//  Source.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import WasmInterpreter

class Source: Identifiable {

    struct FilterInfo: Codable {
        let type: String

        let name: String?
        let defaultValue: DefaultValue?

        let filters: [FilterInfo]?
        let options: [String]?

        let canExclude: Bool?
        let canAscend: Bool?
    }

    struct SourceInfo: Codable {
        let id: String
        let lang: String
        let name: String
        let version: Int
        let nsfw: Int?
    }

    struct SourceManifest: Codable {
        let info: SourceInfo
        let listings: [String]?
        let filters: [FilterInfo]?
    }

    var id: String {
        manifest.info.id
    }
    var url: URL
    var manifest: SourceManifest

    var filters: [FilterBase] = []
    var defaultFilters: [FilterBase] = []
    var listings: [Listing] = []

    var languages: [String] = []
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

    var needsFilterRefresh = true

    var vm: WasmInterpreter

    var globalStore: WasmGlobalStore

    var chapterCounter = 0
    var currentManga = ""

    var actor: SourceActor!

    init(from url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url.appendingPathComponent("source.json"))
        manifest = try JSONDecoder().decode(SourceManifest.self, from: data)

        let bytes = try Data(contentsOf: url.appendingPathComponent("main.wasm"))
        vm = try WasmInterpreter(stackSize: 512 * 1024, module: [UInt8](bytes))
        globalStore = WasmGlobalStore(vm: vm)
        actor = SourceActor(source: self)

        listings = manifest.listings?.map { Listing(name: $0, flags: 0) } ?? []

        prepareVirtualMachine()
        loadSettings()
    }

    func prepareVirtualMachine() {
//        try? vm.addImportHandler(named: "filter", namespace: "env", block: self.create_filter)
//        try? vm.addImportHandler(named: "listing", namespace: "env", block: self.create_listing)
//        try? vm.addImportHandler(named: "manga", namespace: "env", block: self.create_manga)
//        try? vm.addImportHandler(named: "chapter", namespace: "env", block: self.create_chapter)
//        try? vm.addImportHandler(named: "page", namespace: "env", block: self.create_page)

        try? vm.addImportHandler(named: "setting_get_string", namespace: "env", block: self.setting_get_string)
        try? vm.addImportHandler(named: "setting_get_int", namespace: "env", block: self.setting_get_int)
        try? vm.addImportHandler(named: "setting_get_float", namespace: "env", block: self.setting_get_float)
        try? vm.addImportHandler(named: "setting_get_bool", namespace: "env", block: self.setting_get_bool)
        try? vm.addImportHandler(named: "setting_get_array", namespace: "env", block: self.setting_get_array)

        try? vm.addImportHandler(named: "print", namespace: "env", block: self.printFunction)
        try? vm.addImportHandler(named: "abort", namespace: "env", block: self.abort)

        WasmStd(globalStore: globalStore).export()
        WasmAidoku(globalStore: globalStore, sourceId: id).export()
        WasmNet(globalStore: globalStore).export()
        WasmJson(globalStore: globalStore).export()
        WasmHtml(globalStore: globalStore).export()
    }

    var printFunction: (Int32, Int32) -> Void {
        { string, length in
            print((try? self.vm.stringFromHeap(byteOffset: Int(string), length: Int(length))) ?? "")
        }
    }

    var abort: (Int32, Int32, Int32, Int32) -> Void {
        { msg, fileName, line, column in
            let messageLength = (try? self.vm.bytesFromHeap(byteOffset: Int(msg - 4), length: 1).first) ?? 0
            let fileLength = (try? self.vm.bytesFromHeap(byteOffset: Int(fileName - 4), length: 1).first) ?? 0

            let message = try? self.vm.stringFromHeap(byteOffset: Int(msg), length: Int(messageLength))
            let file = try? self.vm.stringFromHeap(byteOffset: Int(fileName), length: Int(fileLength))

            print("[Abort] \(message ?? "") \(file ?? ""):\(line):\(column)")
        }
    }
}

// MARK: - Settings
extension Source {

    func loadSettings() {
        if let data = try? Data(contentsOf: url.appendingPathComponent("settings.json")),
           let settingsPlist = try? JSONDecoder().decode(SourceSettings.self, from: data) {
            settingItems = settingsPlist.settings ?? []
            languages = settingsPlist.languages ?? []

            // Load defaults
            var defaults: [String: Any] = [:]

            if let defaultLang = languages.first {
                defaults["\(id)._language"] = defaultLang
            }

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

    var setting_get_string: (Int32, Int32) -> Int32 {
        { _, key_len in
            guard key_len >= 0 else { return 0 }
//            if let key = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
//               let string = UserDefaults.standard.string(forKey: "\(self.id).\(key)") {
//                return self.vm.write(string: string, memory: self.memory)
//            }
            return 0
        }
    }

    var setting_get_int: (Int32, Int32) -> Int32 {
        { key, key_len in
            guard key_len >= 0 else { return -1 }
            if let key = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)) {
                return Int32(UserDefaults.standard.integer(forKey: "\(self.id).\(key)"))
            }
            return -1
        }
    }

    var setting_get_float: (Int32, Int32) -> Float32 {
        { key, key_len in
            guard key_len >= 0 else { return -1 }
            if let key = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)) {
                return Float32(UserDefaults.standard.float(forKey: "\(self.id).\(key)"))
            }
            return -1
        }
    }

    var setting_get_bool: (Int32, Int32) -> Int32 {
        { key, key_len in
            guard key_len >= 0 else { return 0 }
            if let key = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)) {
                return UserDefaults.standard.bool(forKey: "\(self.id).\(key)") ? 1 : 0
            }
            return 0
        }
    }

    var setting_get_array: (Int32, Int32) -> Int32 {
        { _, key_len in
            guard key_len >= 0 else { return -1 }
//            if let key = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
//               let array = UserDefaults.standard.array(forKey: "\(self.id).\(key)") {
//                self.globalStore.swiftDescriptorPointer += 1
//                self.globalStore.swiftDescriptors.append(array)
//                return Int32(self.globalStore.swiftDescriptorPointer)
//            }
            return -1
        }
    }

    func performAction(key: String) {
//        let string = vm.write(string: key, memory: memory)
//        guard string > 0 else { return }
//        try? vm.call("perform_action", string, Int32(key.count))
//        memory.free(string)
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
                value: value?["index"] != nil ? SortSelection(index: value?["index"]?.intValue ?? 0,
                                                              ascending: value?["ascending"]?.boolValue ?? false) : nil
            )
        case "check":
            filters.append(CheckFilter(name: filter.name ?? "", canExclude: filter.canExclude ?? false, value: filter.defaultValue?.boolValue))
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

        for filter in manifest.filters ?? [] {
            print("x \(filter)")
            if let result = parseFilter(from: filter) {
                filters.append(result)
            }
        }

        print("filters: \(filters)")

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
}
