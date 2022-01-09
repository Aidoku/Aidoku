//
//  WasmProvider.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation

class WasmProvider: MangaProvider {
    let id = "xyz.skitty.wasmtest"
    let name = "Wasm Test Source"
    let lang = "en"
    let containsNsfw = false
    
    func fetchSearchManga(query: String, page: Int = 0, filters: [String] = []) async -> MangaPageResult {
        do {
            return try await WasmManager.shared.searchManga(query: query)
        } catch {
            print("error: \(error)")
            return MangaPageResult(manga: [], hasNextPage: false)
        }
    }
    
    func getMangaDetails(id: String) async -> Manga {
        do {
            return try await WasmManager.shared.getManga(id: id)
        } catch {
            print("error: \(error)")
            return Manga(provider: self.id, id: "error", title: "Error")
        }
    }
    
    func getChapterList(id: String) async -> [Chapter] {
        []
    }
    
    func getPageList(chapter: Chapter) async -> [Page] {
        []
    }
    
    func getMangaCoverURL(manga: Manga, override: Bool = false) async -> String {
        if !override {
            if let url = manga.thumbnailURL {
                return url
            }
        }
        do {
            return try await WasmManager.shared.getCoverURL(id: manga.id)
        } catch {
            print("error: \(error)")
            return manga.thumbnailURL ?? ""
        }
    }
}
