//
//  Source.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import WasmInterpreter

class Source: Identifiable {
    var id: String {
        info.id
    }
    var url: URL
    var info: SourceInfo
    
    var filters: [Filter] = []
    var defaultFilters: [Filter] = []
    var listings: [Listing] = []
    
    var titleSearchable: Bool {
        filters.firstIndex { $0.type == .text && $0.name == "Title" } != nil
    }
    var authorSearchable: Bool {
        filters.firstIndex { $0.type == .text && $0.name == "Author" } != nil
    }
    var filterable: Bool {
        !filters.filter { $0.type != .text || ($0.name != "Title" && $0.name != "Author") }.isEmpty
    }
    
    struct SourceInfo: Codable {
        let id: String
        let lang: String
        let name: String
        let version: Int
    }
    
    enum SourceError: Error {
        case vmNotLoaded
        case mangaDetailsFailed
    }
    
    var vm: WasmInterpreter
    var memory: WasmMemory
    
    init(from url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url.appendingPathComponent("Info.plist"))
        self.info = try PropertyListDecoder().decode(SourceInfo.self, from: data)
        
        let bytes = try Data(contentsOf: url.appendingPathComponent("main.wasm"))
        self.vm = try WasmInterpreter(stackSize: 512 * 1024, module: [UInt8](bytes))
        self.memory = WasmMemory(vm: vm)
        
        prepareVirtualMachine()
    }
    
    func prepareVirtualMachine() {
        try? vm.addImportHandler(named: "string", namespace: "env", block: self.create_string)
        try? vm.addImportHandler(named: "filter", namespace: "env", block: self.create_filter)
        try? vm.addImportHandler(named: "listing", namespace: "env", block: self.create_listing)
        try? vm.addImportHandler(named: "manga", namespace: "env", block: self.create_manga)
        try? vm.addImportHandler(named: "chapter", namespace: "env", block: self.create_chapter)
        try? vm.addImportHandler(named: "page", namespace: "env", block: self.create_page)
        
        try? vm.addImportHandler(named: "array", namespace: "env", block: self.array)
        try? vm.addImportHandler(named: "array_size", namespace: "env", block: self.array_size)
        try? vm.addImportHandler(named: "array_get", namespace: "env", block: self.array_get)
        try? vm.addImportHandler(named: "array_append", namespace: "env", block: self.array_append)
        try? vm.addImportHandler(named: "array_remove", namespace: "env", block: self.array_remove)
        try? vm.addImportHandler(named: "object_getn", namespace: "env", block: self.object_getn)
        try? vm.addImportHandler(named: "string_value", namespace: "env", block: self.string_value)
        try? vm.addImportHandler(named: "integer_value", namespace: "env", block: self.integer_value)
        try? vm.addImportHandler(named: "float_value", namespace: "env", block: self.float_value)
        
        WasmRequest(vm: vm, memory: memory).export()
        WasmJson(vm: vm, memory: memory).export()
        WasmScraper(vm: vm, memory: memory).export()
    }
    
    var descriptorPointer = -1
    var descriptors: [Any] = []
    
    // MARK: Object Pushing
    
    var create_string: (Int32, Int32) -> Int32 {
        { string, string_len in
            self.descriptorPointer += 1
            self.descriptors.append((try? self.vm.stringFromHeap(byteOffset: Int(string), length: Int(string_len))) ?? "")
            return Int32(self.descriptorPointer)
        }
    }
    
    var create_filter: (Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { type, name, name_len, value, default_value in
            let filter: Filter
            let name = (try? self.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len))) ?? ""
            if type == FilterType.note.rawValue {
                filter = Filter(text: name)
            } else if type == FilterType.text.rawValue {
                filter = Filter(name: name)
            } else if type == FilterType.check.rawValue || type == FilterType.genre.rawValue {
                filter = Filter(
                    type: FilterType(rawValue: Int(type)) ?? .check,
                    name: name,
                    canExclude: value > 0,
                    default: Int(default_value)
                )
            } else if type == FilterType.select.rawValue {
                filter = Filter(
                    name: name,
                    options: value > 0 ? self.descriptors[Int(value)] as? [String] ?? [] : [],
                    default: Int(default_value)
                )
            } else if type == FilterType.sort.rawValue {
                let options = self.descriptors[Int(value)] as? [Filter] ?? []
                filter = Filter(
                    name: name,
                    options: options,
                    value: value > 0 ? (self.descriptors[Int(value)] as? Filter)?.value as? SortOption : nil,
                    default: default_value > 0 ? (self.descriptors[Int(default_value)] as? Filter)?.value as? SortOption : nil
                )
            } else if type == FilterType.sortOption.rawValue {
                filter = Filter(
                    name: name,
                    canReverse: value > 0
                )
            } else if type == FilterType.group.rawValue {
                filter = Filter(
                    name: name,
                    filters: value > 0 ? self.descriptors[Int(value)] as? [Filter] ?? [] : []
                )
            } else {
                filter = Filter(
                    type: FilterType(rawValue: Int(type)) ?? .text,
                    name: name
                )
            }
            self.descriptorPointer += 1
            self.descriptors.append(filter)
            return Int32(self.descriptorPointer)
        }
    }
    
    var create_listing: (Int32, Int32, Int32) -> Int32 {
        { name, name_len, can_filter in
            if let str = try? self.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len)) {
                self.descriptorPointer += 1
                self.descriptors.append(Listing(name: str, canFilter: can_filter > 0))
                return Int32(self.descriptorPointer)
            }
            return -1
        }
    }
    
    var create_manga: (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { id, id_len, cover_url, cover_url_len, title, title_len, author, author_len, artist, artist_len, description, description_len, status, tags, tag_str_lens, tag_count, url, url_len, nsfw, viewer in
            if let mangaId = try? self.vm.stringFromHeap(byteOffset: Int(id), length: Int(id_len)) {
                var tagList: [String] = []
                let tagStrings: [Int32] = (try? self.vm.valuesFromHeap(byteOffset: Int(tags), length: Int(tag_count))) ?? []
                let tagStringLengths: [Int32] = (try? self.vm.valuesFromHeap(byteOffset: Int(tag_str_lens), length: Int(tag_count))) ?? []
                for i in 0..<Int(tag_count) {
                    if let str = try? self.vm.stringFromHeap(byteOffset: Int(tagStrings[i]), length: Int(tagStringLengths[i])) {
                        tagList.append(str)
                    }
                }
                let manga = Manga(
                    sourceId: self.info.id,
                    id: mangaId,
                    title: title_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(title), length: Int(title_len)) : nil,
                    author: author_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(author), length: Int(author_len)) : nil,
                    description: description_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(description), length: Int(description_len)) : nil,
                    tags: tagList,
                    cover: cover_url_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(cover_url), length: Int(cover_url_len)) : nil,
                    url: url_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(url), length: Int(url_len)) : nil,
                    status: MangaStatus(rawValue: Int(status)) ?? .unknown,
                    nsfw: MangaContentRating(rawValue: Int(nsfw)) ?? .safe,
                    viewer: MangaViewer(rawValue: Int(viewer)) ?? .rtl
                )
                self.descriptorPointer += 1
                self.descriptors.append(manga)
                return Int32(self.descriptorPointer)
            }
            return -1
        }
    }
    
    var chapterCounter = 0
    var currentManga = ""
    
    var create_chapter: (Int32, Int32, Int32, Int32, Float32, Float32, Int64, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { id, id_len, name, name_len, volume, chapter, dateUploaded, scanlator, scanlator_len, url, url_len, lang, lang_len in
            if let chapterId = try? self.vm.stringFromHeap(byteOffset: Int(id), length: Int(id_len)) {
                self.descriptorPointer += 1
                self.descriptors.append(
                    Chapter(
                        sourceId: self.info.id,
                        id: chapterId,
                        mangaId: self.currentManga,
                        title: name_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len)) : nil,
                        scanlator: scanlator_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(scanlator), length: Int(scanlator_len)) : nil,
                        lang: lang_len > 0 ? (try? self.vm.stringFromHeap(byteOffset: Int(lang), length: Int(lang_len))) ?? "en" : "en",
                        chapterNum: chapter >= 0 ? Float(chapter) : nil,
                        volumeNum: volume >= 0 ? Float(volume) : nil,
                        dateUploaded: dateUploaded > 0 ? Date(timeIntervalSince1970: TimeInterval(dateUploaded)) : nil,
                        sourceOrder: self.chapterCounter
                    )
                )
                self.chapterCounter += 1
                return Int32(self.descriptorPointer)
            }
            return -1
        }
    }
    
    var create_page: (Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { index, image_url, image_url_len, base64, base64_len, text, text_len in
            self.descriptorPointer += 1
            self.descriptors.append(
                Page(
                    index: Int(index),
                    imageURL: image_url_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(image_url), length: Int(image_url_len)) : nil
                )
            )
            return Int32(self.descriptorPointer)
        }
    }
    
    // MARK: Descriptor Handling
    
    var array: () -> Int32 {
        {
            self.descriptorPointer += 1
            self.descriptors.append([])
            return Int32(self.descriptorPointer)
        }
    }
    
    var array_size: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0, descriptor < self.descriptors.count else { return 0 }
            if let array = self.descriptors[Int(descriptor)] as? [Any] {
                return Int32(array.count)
            }
            return 0
        }
    }
    
    var array_get: (Int32, Int32) -> Int32 {
        { descriptor, index in
            guard descriptor >= 0, descriptor < self.descriptors.count else { return -1 }
            if let array = self.descriptors[Int(descriptor)] as? [Any] {
                guard index < array.count else { return -1 }
                self.descriptorPointer += 1
                self.descriptors.append(array[Int(index)])
                return Int32(self.descriptorPointer)
            }
            return -1
        }
    }
    
    var array_append: (Int32, Int32) -> Void {
        { descriptor, object in
            guard descriptor >= 0, descriptor < self.descriptors.count else { return }
            guard object >= 0, object < self.descriptors.count else { return }
            if var array = self.descriptors[Int(descriptor)] as? [Any] {
                array.append(self.descriptors[Int(object)])
                self.descriptors[Int(descriptor)] = array
            }
        }
    }
    
    var array_remove: (Int32, Int32) -> Void {
        { descriptor, index in
            guard descriptor >= 0, descriptor < self.descriptors.count else { return }
            if var array = self.descriptors[Int(descriptor)] as? [Any] {
                array.remove(at: Int(index))
                self.descriptors[Int(descriptor)] = array
            }
        }
    }
    
    var object_getn: (Int32, Int32, Int32) -> Int32 {
        { descriptor, key, key_len in
            guard descriptor >= 0, key >= 0, descriptor < self.descriptors.count else { return -1 }
            if let keyString = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               let object = self.descriptors[Int(descriptor)] as? KVCObject,
               let value = object.valueByPropertyName(name: keyString) {
                self.descriptorPointer += 1
                self.descriptors.append(value)
                return Int32(self.descriptorPointer)
            }
            return -1
        }
    }
    
    var string_value: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return 0 }
            if let string = self.descriptors[Int(descriptor)]  as? String {
                return self.vm.write(string: string, memory: self.memory)
            }
            return 0
        }
    }
    
    var integer_value: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let int = self.descriptors[Int(descriptor)] as? Int {
                return Int32(int)
            } else if let bool = self.descriptors[Int(descriptor)] as? Bool {
                return Int32(bool ? 1 : 0)
            } else if let string = self.descriptors[Int(descriptor)] as? String {
                return Int32(string) ?? -1
            }
            return -1
        }
    }
    
    var float_value: (Int32) -> Float32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let float = self.descriptors[Int(descriptor)] as? Float {
                return Float32(float)
            } else if let float = Float(self.descriptors[Int(descriptor)] as? String ?? "Error") {
                return Float32(float)
            }
            return -1
        }
    }
    
    // MARK: Get Functions
    
    func getDefaultFilters() -> [Filter] {
        guard defaultFilters.isEmpty && !filters.isEmpty else { return defaultFilters }
        
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
        guard filters.isEmpty else { return filters }
        
        let task = Task<[Filter], Error> {
            let descriptor = self.array()
            
            try self.vm.call("initialize_filters", descriptor)
            
            let filters = self.descriptors[Int(descriptor)] as? [Filter] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return filters
        }
        
        filters = try await task.value
        _ = getDefaultFilters()
        
        return filters
    }
    
    func getListings() async throws -> [Listing] {
        guard listings.isEmpty else { return listings }
        
        let task = Task<[Listing], Error> {
            let descriptor = self.array()
            
            try self.vm.call("initialize_listings", descriptor)
            
            let listings = self.descriptors[Int(descriptor)] as? [Listing] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return listings
        }
        
        listings = try await task.value
        
        return listings
    }
    
    func fetchSearchManga(query: String, filters: [Filter] = [], page: Int = 1) async throws -> MangaPageResult {
        var newFilters = filters
        newFilters.append(Filter(name: "Title", value: query))
        return try await getMangaList(filters: newFilters, page: page)
    }
    
    func getMangaList(filters: [Filter], page: Int = 1) async throws -> MangaPageResult {
        let task = Task<MangaPageResult, Error> {
            let descriptor = self.array()
            var filterPointer = -1
            if !filters.isEmpty {
                self.descriptorPointer += 1
                self.descriptors.append(filters)
                filterPointer = self.descriptorPointer
            }
            
            let hasMore: Int32 = try self.vm.call("manga_list_request", descriptor, Int32(filterPointer), Int32(page))
            
            let manga = self.descriptors[Int(descriptor)] as? [Manga] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return MangaPageResult(manga: manga, hasNextPage: hasMore > 0)
        }
        
        return try await task.value
    }
    
    func getMangaListing(listing: Listing, page: Int = 1) async throws -> MangaPageResult {
        let task = Task<MangaPageResult, Error> {
            let descriptor = self.array()
            let listingName = self.vm.write(string: listing.name, memory: self.memory)
            
            let hasMore: Int32 = try self.vm.call("manga_listing_request", descriptor, listingName, Int32(listing.name.count), Int32(page))
            
            let manga = self.descriptors[Int(descriptor)] as? [Manga] ?? []
            
            self.memory.free(listingName)
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return MangaPageResult(manga: manga, hasNextPage: hasMore > 0)
        }
        
        return try await task.value
    }
    
    func getMangaDetails(manga: Manga) async throws -> Manga {
        let task = Task<Manga, Error> {
            self.descriptorPointer += 1
            self.descriptors.append(manga)
            
            let result: Int32 = try self.vm.call("manga_details_request", Int32(self.descriptorPointer))
            
            guard result >= 0, result < self.descriptors.count else { throw SourceError.mangaDetailsFailed }
            let manga = self.descriptors[Int(result)] as? Manga
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            guard let manga = manga else { throw SourceError.mangaDetailsFailed }
            return manga
        }
        
        return try await task.value
    }
    
    func getChapterList(manga: Manga) async throws -> [Chapter] {
        let task = Task<[Chapter], Error> {
            let descriptor = self.array()
            self.descriptorPointer += 1
            self.descriptors.append(manga)
            
            self.chapterCounter = 0
            self.currentManga = manga.id
            
            try self.vm.call("chapter_list_request", descriptor, Int32(self.descriptorPointer))
            
            let chapters = self.descriptors[Int(descriptor)] as? [Chapter] ?? []
            
            self.chapterCounter = 0
            self.descriptorPointer = -1
            self.descriptors = []
            
            return chapters
        }
        
        return try await task.value
    }
    
    func getPageList(chapter: Chapter) async throws -> [Page] {
        let task = Task<[Page], Error> {
            let descriptor = self.array()
            self.descriptorPointer += 1
            self.descriptors.append(chapter)
            
            try self.vm.call("page_list_request", descriptor, Int32(self.descriptorPointer))
            
            let pages = self.descriptors[Int(descriptor)] as? [Page] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return pages
        }
        
        return try await task.value
    }
}
