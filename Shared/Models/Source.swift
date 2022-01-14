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
    var listings: [Listing] = []
    
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
//        guard self.memory == nil else { return }
        
//        guard let memory = self.memory else { return }
        let wasmRequest = WasmRequest(vm: vm, memory: memory)
        let wasmJson = WasmJson(vm: vm, memory: memory)
        
        try? vm.addImportHandler(named: "strjoin", namespace: "env", block: self.strjoin)
        try? vm.addImportHandler(named: "malloc", namespace: "env", block: memory.malloc)
        try? vm.addImportHandler(named: "free", namespace: "env", block: memory.free)
        try? vm.addImportHandler(named: "request_init", namespace: "env", block: wasmRequest.request_init)
        try? vm.addImportHandler(named: "request_set", namespace: "env", block: wasmRequest.request_set)
        try? vm.addImportHandler(named: "request_data", namespace: "env", block: wasmRequest.request_data)
        try? vm.addImportHandler(named: "json_parse", namespace: "env", block: wasmJson.json_parse)
        try? vm.addImportHandler(named: "json_dictionary_get", namespace: "env", block: wasmJson.json_dictionary_get)
        try? vm.addImportHandler(named: "json_dictionary_get_string", namespace: "env", block: wasmJson.json_dictionary_get_string)
        try? vm.addImportHandler(named: "json_dictionary_get_int", namespace: "env", block: wasmJson.json_dictionary_get_int)
        try? vm.addImportHandler(named: "json_dictionary_get_float", namespace: "env", block: wasmJson.json_dictionary_get_float)
        try? vm.addImportHandler(named: "json_array_get", namespace: "env", block: wasmJson.json_array_get)
        try? vm.addImportHandler(named: "json_array_get_string", namespace: "env", block: wasmJson.json_array_get_string)
        try? vm.addImportHandler(named: "json_array_get_length", namespace: "env", block: wasmJson.json_array_get_length)
        try? vm.addImportHandler(named: "json_array_find_dictionary", namespace: "env", block: wasmJson.json_array_find_dictionary)
        try? vm.addImportHandler(named: "json_free", namespace: "env", block: wasmJson.json_free)
        
        try? vm.addImportHandler(named: "push_filter", namespace: "env", block: self.push_filter)
        try? vm.addImportHandler(named: "push_listing", namespace: "env", block: self.push_listing)
        try? vm.addImportHandler(named: "push_manga", namespace: "env", block: self.push_manga)
        try? vm.addImportHandler(named: "push_chapter", namespace: "env", block: self.push_chapter)
        try? vm.addImportHandler(named: "push_page", namespace: "env", block: self.push_page)
        
        try? vm.addImportHandler(named: "create_array", namespace: "env", block: self.create_array)
        try? vm.addImportHandler(named: "get_array_len", namespace: "env", block: self.get_array_len)
        try? vm.addImportHandler(named: "get_array_value", namespace: "env", block: self.get_array_value)
        try? vm.addImportHandler(named: "array_remove_at", namespace: "env", block: self.array_remove_at)
        try? vm.addImportHandler(named: "get_object_value", namespace: "env", block: self.get_object_value)
    }
    
    var strjoin: (Int32, Int32) -> Int32 {
        { strs, len in
            guard len >= 0, strs >= 0 else { return 0 }
            let strings: [Int32] = (try? self.vm.valuesFromHeap(byteOffset: Int(strs), length: Int(len))) ?? []
            let string = strings.map { self.vm.stringFromHeap(byteOffset: Int($0)) }.joined()
            return self.vm.write(string: string, memory: self.memory)
        }
    }
    
    var descriptorPointer = -1
    var descriptors: [Any] = []
    
    var push_filter: (Int32, Int32, Int32, Int32, Int32, Int32) -> Void {
        { descriptor, type, name, name_len, value, value_len in
            if var filters = self.descriptors[Int(descriptor)] as? [Filter] {
                if type == 2 {
                    filters.append(
                        Filter(
                            type: .group,
                            name: (try? self.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len))) ?? "",
                            value: self.descriptors[Int(value)]
                        )
                    )
                } else {
                    filters.append(
                        Filter(
                            type: FilterType(rawValue: Int(type)) ?? .text,
                            name: (try? self.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len))) ?? "",
                            value: value_len > 0 ? try? self.vm.bytesFromHeap(byteOffset: Int(value), length: Int(value_len)) : nil
                        )
                    )
                }
                self.descriptors[Int(descriptor)] = filters
            }
        }
    }
    
    var push_listing: (Int32, Int32, Int32) -> Void {
        { descriptor, name, name_len in
            if var listings = self.descriptors[Int(descriptor)] as? [Listing],
               let str = try? self.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len)) {
                listings.append(Listing(name: str));
                self.descriptors[Int(descriptor)] = listings
            }
        }
    }
    
    var push_manga: (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Void {
        { descriptor, id, id_len, cover_url, cover_url_len, title, title_len, author, author_len, artist, artist_len, description, description_len, categories, category_str_lens, category_count in
            guard descriptor < self.descriptors.count else { return }
            if let mangaId = try? self.vm.stringFromHeap(byteOffset: Int(id), length: Int(id_len)) {
                var categoryList: [String] = []
                let categoryStrings: [Int32] = (try? self.vm.valuesFromHeap(byteOffset: Int(categories), length: Int(category_count))) ?? []
                let categoryStrLengths: [Int32] = (try? self.vm.valuesFromHeap(byteOffset: Int(category_str_lens), length: Int(category_count))) ?? []
                for i in 0..<Int(category_count) {
                    if let str = try? self.vm.stringFromHeap(byteOffset: Int(categoryStrings[i]), length: Int(categoryStrLengths[i])) {
                        categoryList.append(str)
                    }
                }
                let manga = Manga(
                    provider: self.info.id,
                    id: mangaId,
                    title: title_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(title), length: Int(title_len)) : nil,
                    author: author_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(author), length: Int(author_len)) : nil,
                    description: description_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(description), length: Int(description_len)) : nil,
                    categories: categoryList,
                    thumbnailURL: cover_url_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(cover_url), length: Int(cover_url_len)) : nil
                )
                if var mangaList = self.descriptors[Int(descriptor)] as? [Manga] {
                    mangaList.append(manga)
                    self.descriptors[Int(descriptor)] = mangaList
                } else {
                    self.descriptors[Int(descriptor)] = manga
                }
            }
        }
    }
    
    var push_chapter: (Int32, Int32, Int32, Int32, Int32, Int32, Float32, Int32, Int32, Int32) -> Void {
        { descriptor, id, id_len, name, name_len, volume, chapter, dateUpdated, scanlator, scanlator_len in
            guard descriptor < self.descriptors.count else { return }
            if var chapters = self.descriptors[Int(descriptor)] as? [Chapter] {
                if let chapterId = try? self.vm.stringFromHeap(byteOffset: Int(id), length: Int(id_len)) {
                    chapters.append(
                        Chapter(
                            id: chapterId,
                            title: name_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len)) : nil,
                            chapterNum: Float(chapter),
                            volumeNum: Int(volume)
                        )
                    );
                }
                self.descriptors[Int(descriptor)] = chapters
            }
        }
    }
    
    var push_page: (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Void {
        { descriptor, index, image_url, image_url_len, base64, base64_len, text, text_len in
            guard descriptor < self.descriptors.count else { return }
            if var pages = self.descriptors[Int(descriptor)] as? [Page] {
                pages.append(
                    Page(
                        index: Int(index),
                        imageURL: image_url_len > 0 ? try? self.vm.stringFromHeap(byteOffset: Int(image_url), length: Int(image_url_len)) : nil
                    )
                )
                self.descriptors[Int(descriptor)] = pages
            }
        }
    }
    
    var create_array: () -> Int32 {
        {
            self.descriptorPointer += 1
            self.descriptors.append([Any]())
            return Int32(self.descriptorPointer)
        }
    }
    
    var get_array_len: (Int32) -> Int32 {
        { descriptor in
            if let array = self.descriptors[Int(descriptor)] as? [Any] {
                return Int32(array.count)
            }
            return 0
        }
    }
    
    var get_array_value: (Int32, Int32, Int32) -> Int32 {
        { descriptor, pos, value_len in
            if let array = self.descriptors[Int(descriptor)] as? [Any] {
                guard pos < array.count else { return 0 }
                if let value = array[Int(pos)] as? String {
                    if value_len > 0 { try? self.vm.writeToHeap(value: Int32(value.count), byteOffset: Int(value_len)) }
                    return self.vm.write(string: value, memory: self.memory)
                } else if let value = array[Int(pos)] as? Int {
                    return Int32(value)
                } else {
                    self.descriptorPointer += 1
                    self.descriptors.append(array[Int(pos)])
                    return Int32(self.descriptorPointer)
                }
            }
            return 0
        }
    }
    
    var array_remove_at: (Int32, Int32) -> Void {
        { descriptor, pos in
            if var array = self.descriptors[Int(descriptor)] as? [Any] {
                array.remove(at: Int(pos))
                self.descriptors[Int(descriptor)] = array
            }
        }
    }
    
    var get_object_value: (Int32, Int32, Int32, Int32) -> Int32 {
        { descriptor, key, key_len, value_len in
            if let object = self.descriptors[Int(descriptor)] as? KVCObject,
               let keyString = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               let value = object.valueByPropertyName(name: keyString) {
                if let value = value as? String {
                    if value_len > 0 { try? self.vm.writeToHeap(value: Int32(value.count), byteOffset: Int(value_len)) }
                    return self.vm.write(string: value, memory: self.memory)
                } else if let value = value as? Int {
                    return Int32(value)
                } else {
                    self.descriptorPointer += 1
                    self.descriptors.append(value)
                    return Int32(self.descriptorPointer)
                }
            }
            return 0
        }
    }
    
    func getFilters() async throws -> [Filter] {
        guard filters.isEmpty else { return filters }
        
        let task = Task<[Filter], Error> {
            let descriptor = self.create_array()
            
            try self.vm.call("initialize_filters", descriptor)
            
            let filters = self.descriptors[Int(descriptor)] as? [Filter] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return filters;
        }
        
        filters = try await task.value
        
        return filters
    }
    
    func getListings() async throws -> [Listing] {
        guard listings.isEmpty else { return listings }
        
        let task = Task<[Listing], Error> {
            let descriptor = self.create_array()
            
            try self.vm.call("initialize_listings", descriptor)
            
            let filters = self.descriptors[Int(descriptor)] as? [Listing] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return filters;
        }
        
        listings = try await task.value
        
        return listings
    }
    
    func fetchSearchManga(query: String, page: Int = 1) async throws -> MangaPageResult {
        let filter = Filter(name: "Title", value: query)
        return try await getMangaList(filters: [filter], page: 1)
    }
    
    func getMangaList(filters: [Filter], page: Int = 1) async throws -> MangaPageResult {
        let task = Task<MangaPageResult, Error> {
            let descriptor = self.create_array()
            self.descriptorPointer += 1
            self.descriptors.append(filters)
            
            let hasMore: Int32 = try self.vm.call("manga_list_request", descriptor, Int32(self.descriptorPointer), 1)
            
            let manga = self.descriptors[Int(descriptor)] as? [Manga] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return MangaPageResult(manga: manga, hasNextPage: hasMore > 0)
        }
        
        return try await task.value
    }
    
    func getMangaListing(listing: Listing, page: Int = 1) async throws -> MangaPageResult {
        let task = Task<MangaPageResult, Error> {
            let descriptor = self.create_array()
            let listingName = self.vm.write(string: listing.name, memory: self.memory)
            
            let hasMore: Int32 = try self.vm.call("manga_listing_request", descriptor, listingName, Int32(listing.name.count), 1)
            
            let manga = self.descriptors[Int(descriptor)] as? [Manga] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return MangaPageResult(manga: manga, hasNextPage: hasMore > 0)
        }
        
        return try await task.value
    }
    
    func getMangaDetails(manga: Manga) async throws -> Manga {
        let task = Task<Manga, Error> {
            self.descriptorPointer += 2
            self.descriptors.append(manga)
            self.descriptors.append(0)
            let descriptor = Int32(self.descriptorPointer)
            
            try self.vm.call("manga_details_request", descriptor, Int32(self.descriptorPointer - 1))
            
            let manga = self.descriptors[Int(descriptor)] as? Manga
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            guard let manga = manga else { throw SourceError.mangaDetailsFailed }
            return manga
        }
        
        return try await task.value
    }
    
    func getChapterList(manga: Manga) async throws -> [Chapter] {
        let task = Task<[Chapter], Error> {
            let descriptor = self.create_array()
            
            try self.vm.call("chapter_list_request", descriptor, 0)
            
            let chapters = self.descriptors[Int(descriptor)] as? [Chapter] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return chapters
        }
        
        return try await task.value
    }
    
    func getPageList(chapter: Chapter) async throws -> [Page] {
        let task = Task<[Page], Error> {
            let descriptor = self.create_array()
            
            try self.vm.call("page_list_request", descriptor, 0)
            
            let pages = self.descriptors[Int(descriptor)] as? [Page] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return pages
        }
        
        return try await task.value
    }
}
