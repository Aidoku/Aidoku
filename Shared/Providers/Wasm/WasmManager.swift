//
//  WasmManager.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WebAssembly

class WasmManager {
    static let shared = WasmManager()
    
    var vm: Interpreter
    let queue = DispatchQueue(label: "wasmQueue", attributes: .concurrent)
    
    let memory: WasmMemory
    
    init() {
        let bytes = [UInt8](try! Data(contentsOf: Bundle.main.url(forResource: "main", withExtension: "wasm")!))
        self.vm = try! Interpreter(stackSize: 512 * 1024 * 4, module: bytes)
        
        self.memory = WasmMemory(vm: self.vm)
        let wasmRequest = WasmRequest(vm: self.vm, memory: memory)
        let wasmJson = WasmJson(vm: self.vm, memory: memory)
        
        try? self.vm.addImportHandler(
            name: "request_init",
            namespace: "env",
            block: wasmRequest.request_init
        )
        
        try? self.vm.addImportHandler(
            name: "request_set",
            namespace: "env",
            block: wasmRequest.request_set
        )
        
        try? self.vm.addImportHandler(
            name: "request_data",
            namespace: "env",
            block: wasmRequest.request_data
        )
        
        try? self.vm.addImportHandler(
            name: "json_parse",
            namespace: "env",
            block: wasmJson.json_parse
        )
        
        try? self.vm.addImportHandler(
            name: "json_dictionary_get",
            namespace: "env",
            block: wasmJson.json_dictionary_get
        )
        
        try? self.vm.addImportHandler(
            name: "json_dictionary_get_string",
            namespace: "env",
            block: wasmJson.json_dictionary_get_string
        )
        
        try? self.vm.addImportHandler(
            name: "json_array_get",
            namespace: "env",
            block: wasmJson.json_array_get
        )
        
        try? self.vm.addImportHandler(
            name: "json_array_get_length",
            namespace: "env",
            block: wasmJson.json_array_get_length
        )
        
        try? self.vm.addImportHandler(
            name: "json_array_find_dictionary",
            namespace: "env",
            block: wasmJson.json_array_find_dictionary
        )
        
        try? self.vm.addImportHandler(
            name: "json_free",
            namespace: "env",
            block: wasmJson.json_free
        )
        
        try? self.vm.addImportHandler(
            name: "strjoin",
            namespace: "env",
            block: self.strjoin
        )
        
        try? self.vm.addImportHandler(
            name: "malloc",
            namespace: "env",
            block: self.memory.malloc
        )
        
        try? self.vm.addImportHandler(
            name: "free",
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
    
//    var activeTasks = [String: Task<String, Error>]()
    
    func getCoverURL(id: String) async throws -> String {
        let task = Task<String, Error> {
            let idPointer = self.vm.write(string: id)
            let urlPointer: Int32 = try self.vm.call("getCoverURL", idPointer)
            let url = self.vm.stringFromHeap(byteOffset: Int(urlPointer))
            self.memory.free(idPointer)
            self.memory.free(urlPointer)
            
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
            let mangaListPointer: Int32 = try self.vm.valueFromHeap(byteOffset: Int(mangaPageStruct[2]))
            
            var manga = [Manga]()
            
            for i in 0..<Int(mangaPageStruct[0]) {
                let mangaStruct = try self.vm.valuesFromHeap(byteOffset: Int(mangaListPointer) + 6 * 4 * i, length: 6) as [Int32]
                let id = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[0]))
                let title = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[1]))
                var author: String?
                var description: String?
                var thumbnail: String?
                if mangaStruct[2] != 0 {
                    author = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[2]))
                    self.memory.free(mangaStruct[2])
                }
                if mangaStruct[3] != 0 {
                    description = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[3]))
                    self.memory.free(mangaStruct[3])
                }
                if mangaStruct[5] != 0 {
                    thumbnail = self.vm.stringFromHeap(byteOffset: Int(mangaStruct[5]))
                    self.memory.free(mangaStruct[5])
                }
                
                self.memory.free(mangaStruct[0])
                self.memory.free(mangaStruct[1])
                
                var newManga = Manga(
                    provider: "xyz.skitty.wasmtest",
                    id: id,
                    title: title
                )
                if let author = author, author != "" { newManga.author = author }
                if let description = description, description != "" { newManga.description = description }
                if let thumbnail = thumbnail, thumbnail != "" { newManga.thumbnailURL = thumbnail }
                manga.append(newManga)
            }
            
            self.memory.free(queryPointer)
            self.memory.free(queryOffset)
            self.memory.free(mangaListPointer)
            
            return MangaPageResult(manga: manga, hasNextPage: mangaPageStruct[1] > 0)
        }
        
        return try await task.value
    }
    
    func getManga(id: String) async throws -> Manga {
        let task = Task<Manga, Error> {
            let idOffset = self.vm.write(string: id)
            let mangaOffset = self.vm.write(data: [idOffset, 0, 0, 0, 0, 0])
            
            try self.vm.call("getMangaDetails", mangaOffset)
            
            let structValues = try self.vm.valuesFromHeap(byteOffset: Int(mangaOffset), length: 6) as [Int32]
            
            let id = self.vm.stringFromHeap(byteOffset: Int(structValues[0]))
            let title = self.vm.stringFromHeap(byteOffset: Int(structValues[1]))
            let author = self.vm.stringFromHeap(byteOffset: Int(structValues[2]))
            let description = self.vm.stringFromHeap(byteOffset: Int(structValues[3]))
//            let categories = ((try? self.vm.valuesFromHeap(byteOffset: Int(structValues[4]), length: 3) as [Int32]) ?? []).map {
//                self.vm.stringFromHeap(byteOffset: Int($0))
//            }
            let thumbnail = self.vm.stringFromHeap(byteOffset: Int(structValues[5]))
            
            self.memory.free(idOffset)
            self.memory.free(mangaOffset)
            self.memory.free(structValues[1])
            self.memory.free(structValues[2])
            self.memory.free(structValues[3])
            self.memory.free(structValues[4])
            self.memory.free(structValues[5])
            
            return Manga(
                provider: "xyz.skitty.wasmtest",
                id: id,
                title: title,
                author: author,
                description: description,
//                categories: categories,
                thumbnailURL: thumbnail
            )
        }
        
        return try await task.value
    }
}
