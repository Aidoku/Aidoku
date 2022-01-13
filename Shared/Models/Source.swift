//
//  Source.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import WasmInterpreter

class Source: Identifiable {
    let id = UUID()
    var url: URL
    var info: SourceInfo
    
    var filters: [Filter] = []
    
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
        
        try? vm.addImportHandler(named: "send_filter", namespace: "env", block: self.send_filter)
        try? vm.addImportHandler(named: "alloc_filter_group", namespace: "env", block: self.alloc_filter_group)
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
    
    var alloc_filter_group: () -> Int32 {
        {
            self.descriptorPointer += 1
            self.descriptors.append([Filter]())
            return Int32(self.descriptorPointer)
        }
    }
    
    var send_filter: (Int32, Int32, Int32, Int32, Int32, Int32) -> Void {
        { descriptor, type, name, name_len, value, value_len in
            if var filters = self.descriptors[Int(descriptor)] as? [Filter] {
                if type == 3 {
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
    
    func getFilters() async throws -> [Filter] {
        guard filters.isEmpty else { return filters }
        
        let task = Task<[Filter], Error> {
            
            let descriptor = self.alloc_filter_group()
            
            try self.vm.call("get_filters", descriptor)
            
            self.filters = self.descriptors[Int(descriptor)] as? [Filter] ?? []
            
            self.descriptorPointer = -1
            self.descriptors = []
            
            return self.filters;
        }
        
        filters = try await task.value
        
        return filters
    }
    
    func fetchSearchManga(query: String, page: Int = 1) async throws -> MangaPageResult {
        let filter = Filter(name: "Title", value: query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)
        return try await getMangaList(filters: [filter], page: 1)
    }
    
    func getMangaList(filters: [Filter], page: Int = 1) async throws -> MangaPageResult {
        let task = Task<MangaPageResult, Error> {
            let filterPointers = filters.map { $0.toStructPointer(vm: self.vm, memory: self.memory) }
            let filterArrayPointer = self.vm.write(data: filterPointers, memory: self.memory)
            let filterListPointer = self.vm.write(data: [1, filterArrayPointer], memory: self.memory)
            
            let queryOffset: Int32 = try self.vm.call("getMangaList", filterListPointer, Int32(page))
            
            for pointer in filterPointers {
                let stringsToFree: [Int32] = try self.vm.valuesFromHeap(byteOffset: Int(pointer), length: 3)
                self.memory.free(stringsToFree[1])
                self.memory.free(stringsToFree[2])
                self.memory.free(pointer)
            }
            
            guard queryOffset > 0 else { return MangaPageResult(manga: [], hasNextPage: false) }
            
            let mangaPageStruct = try self.vm.valuesFromHeap(byteOffset: Int(queryOffset), length: 3) as [Int32]
            let mangaStructPointers: [Int32] = try self.vm.valuesFromHeap(byteOffset: Int(mangaPageStruct[2]), length: Int(mangaPageStruct[0]))
            
            var manga = [Manga]()
            
            for i in 0..<mangaStructPointers.count {
                let mangaStruct = try self.vm.valuesFromHeap(byteOffset: Int(mangaStructPointers[i]), length: 7) as [Int32]
                let id = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[0]))
                let title = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[1]))
                var author: String?
                var description: String?
                var categories: [String]?
                var thumbnail: String?
                if mangaStruct[2] > 0 {
                    author = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[2]))
                    self.memory.free(mangaStruct[2])
                }
                if mangaStruct[3] > 0 {
                    description = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[3]))
                    self.memory.free(mangaStruct[3])
                }
                if mangaStruct[4] > 0 {
                    categories = ((try? self.vm.valuesFromHeap(byteOffset: Int(mangaStruct[5]), length: Int(mangaStruct[4])) as [Int32]) ?? []).map { pointer -> String in
                        guard pointer != 0 else { return "" }
                        let str = self.vm.stringFromHeap(byteOffset: Int(pointer))
                        self.memory.free(pointer)
                        return str
                    }
                    self.memory.free(mangaStruct[5])
                }
                if mangaStruct[6] > 0 {
                    thumbnail = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[6]))
                    self.memory.free(mangaStruct[6])
                }
                
                self.memory.free(mangaStruct[0])
                self.memory.free(mangaStruct[1])
                
                let newManga = Manga(
                    provider: self.info.id,
                    id: id,
                    title: title,
                    author: author,
                    description: description,
                    categories: categories,
                    thumbnailURL: thumbnail
                )
                
                manga.append(newManga)
                
                self.memory.free(mangaStructPointers[i])
            }
            
            self.memory.free(filterListPointer)
            self.memory.free(queryOffset)
            if mangaPageStruct[2] > 0 {
                self.memory.free(mangaPageStruct[2])
            }
            
            print(self.memory.allocations.count)
            
            return MangaPageResult(manga: manga, hasNextPage: mangaPageStruct[1] > 0)
        }
        
        return try await task.value
    }
    
    func getMangaDetails(manga: Manga) async throws -> Manga {
        let task = Task<Manga, Error> {
            let idOffset = self.vm.write(string: manga.id, memory: self.memory)
            var titleOffset: Int32 = 0
            var authorOffset: Int32 = 0
            var descriptionOffset: Int32 = 0
            if let title = manga.title { titleOffset = self.vm.write(string: title, memory: self.memory) }
            if let author = manga.author { authorOffset = self.vm.write(string: author, memory: self.memory) }
            if let description = manga.description { descriptionOffset = self.vm.write(string: description, memory: self.memory) }
            let mangaOffset = self.vm.write(data: [idOffset, titleOffset, authorOffset, descriptionOffset, 0, 0, 0], memory: self.memory)
            
            let mangaPointer: Int32 = try self.vm.call("getMangaDetails", mangaOffset)
            guard mangaPointer > 0 else { throw SourceError.mangaDetailsFailed }
            
            self.memory.free(mangaOffset)
            self.memory.free(idOffset)
            if titleOffset > 0 { self.memory.free(titleOffset) }
            if authorOffset > 0 { self.memory.free(authorOffset) }
            if descriptionOffset > 0 { self.memory.free(descriptionOffset) }
            
            let structValues = try self.vm.valuesFromHeap(byteOffset: Int(mangaPointer), length: 7) as [Int32]
            
            let id = self.vm.stringFromHeap(byteOffset: Int(structValues[0]))
            let title = self.vm.stringFromHeap(byteOffset: Int(structValues[1]))
            var author: String?
            var description: String?
            var categories: [String]?
            var thumbnail: String?
            if structValues[2] > 0 {
                author = self.vm.stringFromHeap(byteOffset: Int(structValues[2]))
                self.memory.free(structValues[2])
            }
            if structValues[3] > 0 {
                description = self.vm.stringFromHeap(byteOffset: Int(structValues[3]))
                self.memory.free(structValues[3])
            }
            if structValues[5] > 0 {
                categories = ((try? self.vm.valuesFromHeap(byteOffset: Int(structValues[5]), length: Int(structValues[4])) as [Int32]) ?? []).map { pointer -> String in
                    let str = self.vm.stringFromHeap(byteOffset: Int(pointer))
                    self.memory.free(pointer)
                    return str
                }
                self.memory.free(structValues[5])
            }
            if structValues[6] > 0 {
                thumbnail = self.vm.stringFromHeap(byteOffset: Int(structValues[6]))
                self.memory.free(structValues[6])
            }
            
            self.memory.free(mangaPointer)
            self.memory.free(structValues[0])
            self.memory.free(structValues[1])
            
            return Manga(
                provider: self.info.id,
                id: id,
                title: title,
                author: author,
                description: description,
                categories: categories,
                thumbnailURL: thumbnail
            )
        }
        
        return try await task.value
    }
    
    func getChapterList(manga: Manga) async throws -> [Chapter] {
        let task = Task<[Chapter], Error> {
            let idOffset = self.vm.write(string: manga.id, memory: self.memory)
            var titleOffset: Int32 = 0
            var authorOffset: Int32 = 0
            var descriptionOffset: Int32 = 0
            if let title = manga.title { titleOffset = self.vm.write(string: title, memory: self.memory) }
            if let author = manga.author { authorOffset = self.vm.write(string: author, memory: self.memory) }
            if let description = manga.description { descriptionOffset = self.vm.write(string: description, memory: self.memory) }
            let mangaOffset = self.vm.write(data: [idOffset, titleOffset, authorOffset, descriptionOffset, 0, 0, 0], memory: self.memory)
            
            let chapterListPointer: Int32 = try self.vm.call("getChapterList", mangaOffset)
            guard chapterListPointer > 0 else { return [] }
            
            self.memory.free(mangaOffset)
            self.memory.free(idOffset)
            if titleOffset > 0 { self.memory.free(titleOffset) }
            if authorOffset > 0 { self.memory.free(authorOffset) }
            if descriptionOffset > 0 { self.memory.free(descriptionOffset) }
            
            let chapterListStruct = try self.vm.valuesFromHeap(byteOffset: Int(chapterListPointer), length: 2) as [Int32]
            let chapterPointers: [Int32] = try self.vm.valuesFromHeap(byteOffset: Int(chapterListStruct[1]), length: Int(chapterListStruct[0]))
            
            var chapters: [Chapter] = []
            
            for pointer in chapterPointers {
                let chapterStruct = try self.vm.valuesFromHeap(byteOffset: Int(pointer), length: 4) as [Int32]
                let id = self.vm.stringFromHeap(byteOffset: Int(chapterStruct[0]))
                let chapterNum: Float32 = try self.vm.valueFromHeap(byteOffset: Int(pointer) + 8)
                var title: String?
                if chapterStruct[1] > 0 {
                    title = self.vm.stringFromHeap(byteOffset: Int(chapterStruct[1]))
                    self.memory.free(chapterStruct[1])
                }
                
                self.memory.free(chapterStruct[0])
                
                let newChapter = Chapter(
                    id: id,
                    title: title,
                    chapterNum: chapterNum,
                    volumeNum: Int(chapterStruct[3])
                )
                
                chapters.append(newChapter)
                
                self.memory.free(pointer)
            }
            
            self.memory.free(chapterListPointer)
            self.memory.free(chapterListStruct[1])
            
            return chapters
        }
        
        return try await task.value
    }
    
    func getPageList(chapter: Chapter) async throws -> [Page] {
        let task = Task<[Page], Error> {
            let idOffset = self.vm.write(string: chapter.id, memory: self.memory)
            let chapterStruct = self.vm.write(data: [idOffset, 0, 0, 0], memory: self.memory)
            let pageListPointer: Int32 = try self.vm.call("getPageList", chapterStruct)
            guard pageListPointer > 0 else { return [] }
            
            let pageListStruct = try self.vm.valuesFromHeap(byteOffset: Int(pageListPointer), length: 2) as [Int32]
            let pagePointers: [Int32] = try self.vm.valuesFromHeap(byteOffset: Int(pageListStruct[1]), length: Int(pageListStruct[0]))
            
            var pages: [Page] = []
            
            for pointer in pagePointers {
                let pageStruct = try self.vm.valuesFromHeap(byteOffset: Int(pointer), length: 4) as [Int32]
                var imageUrl: String?
                if pageStruct[1] > 0 {
                    imageUrl = self.vm.stringFromHeap(byteOffset: Int(pageStruct[1]))
                    self.memory.free(pageStruct[1])
                }
                
                let newPage = Page(
                    index: Int(pageStruct[0]),
                    imageURL: imageUrl
                )
                
                pages.append(newPage)
                
                self.memory.free(pointer)
            }
            
            self.memory.free(idOffset)
            self.memory.free(chapterStruct)
            self.memory.free(pageListPointer)
            self.memory.free(pageListStruct[1])
            
            return pages
        }
        
        return try await task.value
    }
}
