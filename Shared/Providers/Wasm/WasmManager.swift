//
//  WasmManager.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WasmInterpreter

class WasmManager {
    enum WasmError: Error {
        case getMangaDetailsError
    }
    
    static let shared = WasmManager()
    
    var vm: WasmInterpreter
    let queue = DispatchQueue(label: "wasmQueue", attributes: .concurrent)
    
    let memory: WasmMemory
    
    init() {
        let bytes = [UInt8](try! Data(contentsOf: Bundle.main.url(forResource: "main", withExtension: "wasm")!))
        self.vm = try! WasmInterpreter(stackSize: 512 * 1024, module: bytes)
        
        self.memory = WasmMemory(vm: self.vm)
        let wasmRequest = WasmRequest(vm: self.vm, memory: memory)
        let wasmJson = WasmJson(vm: self.vm, memory: memory)
        
        try? self.vm.addImportHandler(
            named: "request_init",
            namespace: "env",
            block: wasmRequest.request_init
        )
        
        try? self.vm.addImportHandler(
            named: "request_set",
            namespace: "env",
            block: wasmRequest.request_set
        )
        
        try? self.vm.addImportHandler(
            named: "request_data",
            namespace: "env",
            block: wasmRequest.request_data
        )
        
        try? self.vm.addImportHandler(
            named: "json_parse",
            namespace: "env",
            block: wasmJson.json_parse
        )
        
        try? self.vm.addImportHandler(
            named: "json_dictionary_get",
            namespace: "env",
            block: wasmJson.json_dictionary_get
        )
        
        try? self.vm.addImportHandler(
            named: "json_dictionary_get_string",
            namespace: "env",
            block: wasmJson.json_dictionary_get_string
        )
        
        try? self.vm.addImportHandler(
            named: "json_dictionary_get_int",
            namespace: "env",
            block: wasmJson.json_dictionary_get_int
        )
        
        try? self.vm.addImportHandler(
            named: "json_dictionary_get_float",
            namespace: "env",
            block: wasmJson.json_dictionary_get_float
        )
        
        try? self.vm.addImportHandler(
            named: "json_array_get",
            namespace: "env",
            block: wasmJson.json_array_get
        )
        
        try? self.vm.addImportHandler(
            named: "json_array_get_string",
            namespace: "env",
            block: wasmJson.json_array_get_string
        )
        
        try? self.vm.addImportHandler(
            named: "json_array_get_length",
            namespace: "env",
            block: wasmJson.json_array_get_length
        )
        
        try? self.vm.addImportHandler(
            named: "json_array_find_dictionary",
            namespace: "env",
            block: wasmJson.json_array_find_dictionary
        )
        
        try? self.vm.addImportHandler(
            named: "json_free",
            namespace: "env",
            block: wasmJson.json_free
        )
        
        try? self.vm.addImportHandler(
            named: "strjoin",
            namespace: "env",
            block: self.strjoin
        )
        
        try? self.vm.addImportHandler(
            named: "malloc",
            namespace: "env",
            block: self.memory.malloc
        )
        
        try? self.vm.addImportHandler(
            named: "free",
            namespace: "env",
            block: self.memory.free
        )
    }
    
    var strjoin: (Int32, Int32) -> Int32 {
        { strs, len in
            guard len >= 0, strs >= 0 else { return 0 }
            let strings: [Int32] = (try? self.vm.valuesFromHeap(byteOffset: Int(strs), length: Int(len))) ?? []
            let string = strings.map { self.vm.stringFromHeap(byteOffset: Int($0)) }.joined()
            return self.vm.write(string: string)
        }
    }
    
    func getCoverURL(id: String) async throws -> String {
        let task = Task<String, Error> {
            var url = ""
            let idPointer = self.vm.write(string: id)
            let urlPointer: Int32 = try self.vm.call("getCoverURL", idPointer)
            if urlPointer > 0 {
                url = self.vm.stringFromHeap(byteOffset: Int(urlPointer))
                self.memory.free(urlPointer)
            }
            self.memory.free(idPointer)
            
            return url
        }

        return try await task.value
    }
    
    func searchManga(query: String) async throws -> MangaPageResult {
        let task = Task<MangaPageResult, Error> {
            let queryPointer = self.vm.write(string: query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)
            let queryOffset = self.vm.write(data: [0, 0, 0])
            try self.vm.call("fetchSearchManga", queryOffset, queryPointer, 0)
            
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
                    provider: "xyz.skitty.wasmtest",
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
            
            self.memory.free(queryPointer)
            self.memory.free(queryOffset)
            self.memory.free(mangaPageStruct[2])
            
            return MangaPageResult(manga: manga, hasNextPage: mangaPageStruct[1] > 0)
        }
        
        return try await task.value
    }
    
    func getManga(manga: Manga) async throws -> Manga {
        let task = Task<Manga, Error> {
            let idOffset = self.vm.write(string: manga.id)
            var titleOffset: Int32 = 0
            var authorOffset: Int32 = 0
            var descriptionOffset: Int32 = 0
            if let title = manga.title { titleOffset = self.vm.write(string: title) }
            if let author = manga.author { authorOffset = self.vm.write(string: author) }
            if let description = manga.description { descriptionOffset = self.vm.write(string: description) }
            let mangaOffset = self.vm.write(data: [idOffset, titleOffset, authorOffset, descriptionOffset, 0, 0, 0])
            
            let success: Int32 = try self.vm.call("getMangaDetails", mangaOffset)
            guard success > 0 else { throw WasmError.getMangaDetailsError }
            
            let structValues = try self.vm.valuesFromHeap(byteOffset: Int(mangaOffset), length: 7) as [Int32]
            
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
            
            self.memory.free(idOffset)
            if structValues[0] != idOffset {
                self.memory.free(structValues[0])
            }
            self.memory.free(mangaOffset)
            self.memory.free(structValues[1])
            
            return Manga(
                provider: "xyz.skitty.wasmtest",
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
    
    func getChapters(id: String) async throws -> [Chapter] {
        let task = Task<[Chapter], Error> {
            let idOffset = self.vm.write(string: id)
            let chapterListPointer = self.vm.write(data: [0, 0])
            try self.vm.call("getChapterList", chapterListPointer, idOffset)
            
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
            
            self.memory.free(idOffset)
            self.memory.free(chapterListPointer)
            self.memory.free(chapterListStruct[1])
            
            return chapters
        }
        
        return try await task.value
    }
    
    func getPages(chapter: Chapter) async throws -> [Page] {
        let task = Task<[Page], Error> {
            let idOffset = self.vm.write(string: chapter.id)
            let chapterStruct = self.vm.write(data: [idOffset, 0, 0, 0])
            let pageListPointer = self.vm.write(data: [0, 0])
            let success: Int32 = try self.vm.call("getPageList", pageListPointer, chapterStruct)
            guard success > 0 else { return [] }
            
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
