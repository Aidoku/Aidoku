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
        try? vm.addImportHandler(named: "push_filter", namespace: "env", block: self.push_filter)
        try? vm.addImportHandler(named: "push_listing", namespace: "env", block: self.push_listing)
        try? vm.addImportHandler(named: "push_manga", namespace: "env", block: self.push_manga)
        try? vm.addImportHandler(named: "push_chapter", namespace: "env", block: self.push_chapter)
        try? vm.addImportHandler(named: "push_page", namespace: "env", block: self.push_page)
        
        try? vm.addImportHandler(named: "array", namespace: "env", block: self.array)
        try? vm.addImportHandler(named: "array_size", namespace: "env", block: self.array_size)
        try? vm.addImportHandler(named: "array_get", namespace: "env", block: self.array_get)
        try? vm.addImportHandler(named: "array_remove", namespace: "env", block: self.array_remove)
        try? vm.addImportHandler(named: "object_getn", namespace: "env", block: self.object_getn)
        try? vm.addImportHandler(named: "string_value", namespace: "env", block: self.string_value)
        try? vm.addImportHandler(named: "integer_value", namespace: "env", block: self.integer_value)
        try? vm.addImportHandler(named: "float_value", namespace: "env", block: self.float_value)
        
        WasmRequest(vm: vm, memory: memory).export()
        WasmJson(vm: vm, memory: memory).export()
    }
    
    var descriptorPointer = -1
    var descriptors: [Any] = []
    
    // MARK: Object Pushing
    
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
                            volumeNum: volume >= 0 ? Int(volume) : nil
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
            } else if let int = Int(self.descriptors[Int(descriptor)] as? String ?? "Error") {
                return Int32(int)
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
    
    func getFilters() async throws -> [Filter] {
        guard filters.isEmpty else { return filters }
        
        let task = Task<[Filter], Error> {
            let descriptor = self.array()
            
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
            let descriptor = self.array()
            
            try self.vm.call("initialize_listings", descriptor)
            
            let listings = self.descriptors[Int(descriptor)] as? [Listing] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return listings;
        }
        
        listings = try await task.value
        
        return listings
    }
    
    func fetchSearchManga(query: String, page: Int = 1) async throws -> MangaPageResult {
        let filter = Filter(name: "Title", value: query)
        return try await getMangaList(filters: [filter], page: page)
    }
    
    func getMangaList(filters: [Filter], page: Int = 1) async throws -> MangaPageResult {
        let task = Task<MangaPageResult, Error> {
            let descriptor = self.array()
            self.descriptorPointer += 1
            self.descriptors.append(filters)
            
            let hasMore: Int32 = try self.vm.call("manga_list_request", descriptor, Int32(self.descriptorPointer), Int32(page))
            
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
            let descriptor = self.array()
            self.descriptorPointer += 1
            self.descriptors.append(manga)
            
            try self.vm.call("chapter_list_request", descriptor, Int32(self.descriptorPointer))
            
            let chapters = self.descriptors[Int(descriptor)] as? [Chapter] ?? []
            
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
