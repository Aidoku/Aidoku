//
//  Source.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import WasmInterpreter

class Source: Identifiable {

    struct SourceInfo: Codable {
        let id: String
        let lang: String
        let name: String
        let version: Int
        let nsfw: Int?
    }

    var id: String {
        info.id
    }
    var url: URL
    var info: SourceInfo

    var filters: [Filter] = []
    var defaultFilters: [Filter] = []
    var listings: [Listing] = []

    var languages: [String] = []
    var settingItems: [SettingItem] = []

    var titleSearchable: Bool {
        filters.contains { $0.type == .text && $0.name == "Title" }
    }
    var authorSearchable: Bool {
        filters.contains { $0.type == .text && $0.name == "Author" }
    }
    var filterable: Bool {
        filters.contains { $0.type != .text }
    }

    var needsFilterRefresh = true

    var vm: WasmInterpreter
    var memory: WasmMemory

    var globalStore: WasmGlobalStore

    var chapterCounter = 0
    var currentManga = ""

    var actor: SourceActor!

    init(from url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url.appendingPathComponent("Info.plist"))
        self.info = try PropertyListDecoder().decode(SourceInfo.self, from: data)

        let bytes = try Data(contentsOf: url.appendingPathComponent("main.wasm"))
        self.vm = try WasmInterpreter(stackSize: 512 * 1024, module: [UInt8](bytes))
        self.memory = WasmMemory(vm: vm)
        self.globalStore = WasmGlobalStore(vm: vm)
        self.actor = SourceActor(source: self)

        prepareVirtualMachine()
        loadSettings()
    }

    func prepareVirtualMachine() {
        try? vm.addImportHandler(named: "string", namespace: "env", block: self.create_string)

//        try? vm.addImportHandler(named: "filter", namespace: "env", block: self.create_filter)
//        try? vm.addImportHandler(named: "listing", namespace: "env", block: self.create_listing)
//        try? vm.addImportHandler(named: "manga", namespace: "env", block: self.create_manga)
//        try? vm.addImportHandler(named: "chapter", namespace: "env", block: self.create_chapter)
//        try? vm.addImportHandler(named: "page", namespace: "env", block: self.create_page)

        try? vm.addImportHandler(named: "array", namespace: "env", block: self.array)
        try? vm.addImportHandler(named: "array_size", namespace: "env", block: self.array_size)
        try? vm.addImportHandler(named: "array_get", namespace: "env", block: self.array_get)
        try? vm.addImportHandler(named: "array_append", namespace: "env", block: self.array_append)
        try? vm.addImportHandler(named: "array_remove", namespace: "env", block: self.array_remove)
        try? vm.addImportHandler(named: "object_getn", namespace: "env", block: self.object_getn)
        try? vm.addImportHandler(named: "string", namespace: "env", block: self.string)
        try? vm.addImportHandler(named: "string_value", namespace: "env", block: self.string_value)
        try? vm.addImportHandler(named: "integer_value", namespace: "env", block: self.integer_value)
        try? vm.addImportHandler(named: "float_value", namespace: "env", block: self.float_value)

        try? vm.addImportHandler(named: "setting_get_string", namespace: "env", block: self.setting_get_string)
        try? vm.addImportHandler(named: "setting_get_int", namespace: "env", block: self.setting_get_int)
        try? vm.addImportHandler(named: "setting_get_float", namespace: "env", block: self.setting_get_float)
        try? vm.addImportHandler(named: "setting_get_bool", namespace: "env", block: self.setting_get_bool)
        try? vm.addImportHandler(named: "setting_get_array", namespace: "env", block: self.setting_get_array)

        try? vm.addImportHandler(named: "print", namespace: "env", block: self.printFunction)
        try? vm.addImportHandler(named: "abort", namespace: "env", block: self.abort)

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
        if let data = try? Data(contentsOf: url.appendingPathComponent("Settings.plist")),
           let settingsPlist = try? PropertyListDecoder().decode(SourceSettings.self, from: data) {
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
        { key, key_len in
            guard key_len >= 0 else { return 0 }
            if let key = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               let string = UserDefaults.standard.string(forKey: "\(self.id).\(key)") {
                return self.vm.write(string: string, memory: self.memory)
            }
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
        { key, key_len in
            guard key_len >= 0 else { return -1 }
            if let key = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               let array = UserDefaults.standard.array(forKey: "\(self.id).\(key)") {
                self.globalStore.swiftDescriptorPointer += 1
                self.globalStore.swiftDescriptors.append(array)
                return Int32(self.globalStore.swiftDescriptorPointer)
            }
            return -1
        }
    }

    func performAction(key: String) {
        let string = vm.write(string: key, memory: memory)
        guard string > 0 else { return }
        try? vm.call("perform_action", string, Int32(key.count))
        memory.free(string)
    }
}

// MARK: - Object Pushing
extension Source {

    var create_string: (Int32, Int32) -> Int32 {
        { string, string_len in
            self.globalStore.swiftDescriptorPointer += 1
            self.globalStore.swiftDescriptors.append((try? self.vm.stringFromHeap(byteOffset: Int(string), length: Int(string_len))) ?? "")
            return Int32(self.globalStore.swiftDescriptorPointer)
        }
    }
}

// MARK: - Descriptor Handling
extension Source {

    var array: () -> Int32 {
        {
            self.globalStore.swiftDescriptorPointer += 1
            self.globalStore.swiftDescriptors.append([])
            return Int32(self.globalStore.swiftDescriptorPointer)
        }
    }

    var array_size: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0, descriptor < self.globalStore.swiftDescriptors.count else { return 0 }
            if let array = self.globalStore.swiftDescriptors[Int(descriptor)] as? [Any] {
                return Int32(array.count)
            }
            return 0
        }
    }

    var array_get: (Int32, Int32) -> Int32 {
        { descriptor, index in
            guard descriptor >= 0, descriptor < self.globalStore.swiftDescriptors.count else { return -1 }
            if let array = self.globalStore.swiftDescriptors[Int(descriptor)] as? [Any] {
                guard index < array.count else { return -1 }
                self.globalStore.swiftDescriptorPointer += 1
                self.globalStore.swiftDescriptors.append(array[Int(index)])
                return Int32(self.globalStore.swiftDescriptorPointer)
            }
            return -1
        }
    }

    var array_append: (Int32, Int32) -> Void {
        { descriptor, object in
            guard descriptor >= 0, descriptor < self.globalStore.swiftDescriptors.count else { return }
            guard object >= 0, object < self.globalStore.swiftDescriptors.count else { return }
            if var array = self.globalStore.swiftDescriptors[Int(descriptor)] as? [Any] {
                array.append(self.globalStore.swiftDescriptors[Int(object)])
                self.globalStore.swiftDescriptors[Int(descriptor)] = array
            }
        }
    }

    var array_remove: (Int32, Int32) -> Void {
        { descriptor, index in
            guard descriptor >= 0, descriptor < self.globalStore.swiftDescriptors.count else { return }
            if var array = self.globalStore.swiftDescriptors[Int(descriptor)] as? [Any] {
                array.remove(at: Int(index))
                self.globalStore.swiftDescriptors[Int(descriptor)] = array
            }
        }
    }

    var object_getn: (Int32, Int32, Int32) -> Int32 {
        { descriptor, key, key_len in
            guard descriptor >= 0, key >= 0, descriptor < self.globalStore.swiftDescriptors.count else { return -1 }
            if let keyString = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               let object = self.globalStore.swiftDescriptors[Int(descriptor)] as? KVCObject,
               let value = object.valueByPropertyName(name: keyString) {
                self.globalStore.swiftDescriptorPointer += 1
                self.globalStore.swiftDescriptors.append(value)
                return Int32(self.globalStore.swiftDescriptorPointer)
            }
            return -1
        }
    }

    var string: (Int32, Int32) -> Int32 {
        { str, str_len in
            guard str_len >= 0 else { return -1 }
            if let string = try? self.vm.stringFromHeap(byteOffset: Int(str), length: Int(str_len)) {
                self.globalStore.swiftDescriptorPointer += 1
                self.globalStore.swiftDescriptors.append(string)
                return Int32(self.globalStore.swiftDescriptorPointer)
            }
            return -1
        }
    }

    var string_value: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return 0 }
            if let string = self.globalStore.swiftDescriptors[Int(descriptor)] as? String {
                return self.vm.write(string: string, memory: self.memory)
            }
            return 0
        }
    }

    var integer_value: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let int = self.globalStore.swiftDescriptors[Int(descriptor)] as? Int {
                return Int32(int)
            } else if let bool = self.globalStore.swiftDescriptors[Int(descriptor)] as? Bool {
                return Int32(bool ? 1 : 0)
            } else if let string = self.globalStore.swiftDescriptors[Int(descriptor)] as? String {
                return Int32(string) ?? -1
            }
            return -1
        }
    }

    var float_value: (Int32) -> Float32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let float = self.globalStore.swiftDescriptors[Int(descriptor)] as? Float {
                return Float32(float)
            } else if let float = Float(self.globalStore.swiftDescriptors[Int(descriptor)] as? String ?? "Error") {
                return Float32(float)
            }
            return -1
        }
    }
}

// MARK: - Get Functions
extension Source {

    func getDefaultFilters() -> [Filter] {
        guard (defaultFilters.isEmpty || needsFilterRefresh) && !filters.isEmpty else { return defaultFilters }

        defaultFilters = []

        for filter in filters {
            if filter.type == .group {
                for subFilter in filter.value as? [Filter] ?? [] {
                    if (subFilter.type == .check || subFilter.type == .genre) && subFilter.defaultValue as? Int ?? 0 > 0 {
                        defaultFilters.append(Filter(type: subFilter.type, name: subFilter.name, value: subFilter.defaultValue))
                    }
                }
            } else if filter.type != .text || (filter.name != "Title" && filter.name != "Author") {
                defaultFilters.append(Filter(type: filter.type, name: filter.name, value: filter.defaultValue))
            }
        }

        return defaultFilters
    }

    func getFilters() async throws -> [Filter] {
        guard filters.isEmpty || needsFilterRefresh else { return filters }

        filters = try await actor.getFilters()
        _ = getDefaultFilters()

        needsFilterRefresh = false

        return filters
    }

    func getListings() async throws -> [Listing] {
        guard listings.isEmpty else { return listings }

        listings = try await actor.getListings()

        return listings
    }

    func fetchSearchManga(query: String, filters: [Filter] = [], page: Int = 1) async throws -> MangaPageResult {
        var newFilters = filters
        newFilters.append(Filter(name: "Title", value: query))
        return try await actor.getMangaList(filters: newFilters, page: page)
    }

    func getMangaList(filters: [Filter], page: Int = 1) async throws -> MangaPageResult {
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
