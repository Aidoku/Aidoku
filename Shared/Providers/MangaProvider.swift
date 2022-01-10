//
//  MangaProvider.swift
//  Aidoku
//
//  Created by Skitty on 12/20/21.
//

import Foundation

protocol MangaProvider {
    var id: String { get }
    var name: String { get }
    var lang: String { get }
    var containsNsfw: Bool { get }
    
    func fetchPopularManga(page: Int) async -> MangaPageResult
    func fetchSearchManga(query: String, page: Int, filters: [String]) async -> MangaPageResult
    
    func fetchMangaDetails(manga: Manga) async -> Manga
    
    func getMangaDetails(id: String) async -> Manga
    func getMangaCoverURL(manga: Manga, override: Bool) async -> String
    func getChapterList(id: String) async -> [Chapter]
    func getPageList(chapter: Chapter) async -> [Page]
}

// MARK: - Default implementations
extension MangaProvider {
    
    func fetchMangaDetails(manga: Manga) async -> Manga {
        await getMangaDetails(id: manga.id)
    }
    
    func fetchPopularManga(page: Int) async -> MangaPageResult {
        MangaPageResult(manga: [], hasNextPage: false)
    }
    
    func fetchSearchManga(query: String, page: Int = 0, filters: [String] = []) async -> MangaPageResult {
        await fetchSearchManga(query: query, page: page, filters: filters)
    }
    
    func getMangaCoverURL(manga: Manga, override: Bool = false) async -> String {
        await getMangaCoverURL(manga: manga, override: override)
    }
}
