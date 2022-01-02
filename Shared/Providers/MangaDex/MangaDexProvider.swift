//
//  MangaDexProvider.swift
//  Aidoku
//
//  Created by Skitty on 12/20/21.
//

import Foundation

class MangaDexProvider: MangaProvider {
    enum MDError: Error {
        case missingData
        case errorResponse
    }
    
    let id = "xyz.skitty.mangadex"
    let name = "Manga Dex"
    let lang = "en"
    let containsNsfw = false
    
    func fetchSearchManga(query: String, page: Int = 0, filters: [String] = []) async -> MangaPageResult {
        do {
            let url = URL(string: "https://api.mangadex.org/manga/?title=\(query)&offset=\(10*page)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")!
            let search: MDLimitedResponse<MDObject<MDManga>> = try await URLSession.shared.object(from: url)
            var manga = [Manga]()
            for mangaObj in search.data ?? [] {
                manga.append(
                    try await Manga(
                        provider: id,
                        id: mangaObj.id,
                        title: mangaObj.attributes.title.translations["en"] ?? "Error",
                        author: getAuthor(for: mangaObj),
                        description: mangaObj.attributes.description?.translations["en"] ?? "No Description",
                        categories: mangaObj.attributes.tags.map {
                            $0.attributes.name.translations["en"] ?? ""
                        }
                    )
                )
            }
            return MangaPageResult(manga: manga, hasNextPage: search.offset + search.limit < search.total)
        } catch {
            print("[fetchSearchManga] error: \(error)")
            return MangaPageResult(manga: [], hasNextPage: false)
        }
    }
    
    func getAuthor(for manga: MDObject<MDManga>) async throws -> String {
        var author = "Unknown Author"
        if let mangaAuthor = manga.relationships.first(where: { $0.type == "author" }) {
            let authorRes: MDResponse<MDObject<MDAuthor>> = try await URLSession.shared.object(from: URL(string: "https://api.mangadex.org/author/\(mangaAuthor.id)")!)
            author = authorRes.data?.attributes.name ?? "Unknown Author"
        }
        return author
    }
    
    func loadMangaData(id: String) async throws -> (MDResponse<MDObject<MDManga>>, String) {
        let manga: MDResponse<MDObject<MDManga>> = try await URLSession.shared.object(from: URL(string: "https://api.mangadex.org/manga/\(id)")!)
        if let data = manga.data {
            let author = try await getAuthor(for: data)
            return (manga, author)
        } else {
            throw MDError.missingData
        }
    }
    
    func getMangaDetails(id: String) async -> Manga {
        do {
            async let (manga, author) = loadMangaData(id: id)
            return try await Manga(
                provider: self.id,
                id: id,
                title: manga.data?.attributes.title.translations["en"] ?? "Error",
                author: author,
                description: manga.data?.attributes.description?.translations["en"] ?? "No Description",
                categories: manga.data?.attributes.tags.map {
                    $0.attributes.name.translations["en"] ?? ""
                }
            )
        } catch {
            print("[getMangaDetails] error: \(error)")
            return Manga(provider: self.id, id: id, title: "Error", thumbnailURL: "")
        }
    }
    
    func getMangaCoverURL(manga: Manga, override: Bool = false) async -> String {
        if !override {
            if let url = manga.thumbnailURL {
                return url
            }
        }
        do {
            let cover: MDLimitedResponse<MDObject<MDCover>> = try await URLSession.shared.object(from: URL(string: "https://api.mangadex.org/cover/?manga[]=\(manga.id)")!)
            guard let fileName = cover.data?.first?.attributes.fileName else { throw MDError.errorResponse }
            return "https://uploads.mangadex.org/covers/\(manga.id)/\(fileName).256.jpg"
        } catch {
            print("[getMangaCoverURL] error: \(error)")
            return ""
        }
    }
    
    func getChapterList(id: String) async -> [Chapter] {
        do {
            let chapters: MDLimitedResponse<MDObject<MDChapter>> = try await URLSession.shared.object(from: URL(string: "https://api.mangadex.org/manga/\(id)/feed?order[volume]=asc&order[chapter]=asc&translatedLanguage[]=en&limit=500")!)
            var soFar = [MDObject<MDChapter>]()
            guard let chapterObjcets = chapters.data else { throw MDError.errorResponse }
            let data: [Chapter] = chapterObjcets.compactMap { chapter in
                // remove duplicate chapters
                guard !soFar.contains(where: { $0.attributes.chapter == chapter.attributes.chapter && $0.attributes.volume == chapter.attributes.volume }) else { return nil }
                soFar.append(chapter)
                return Chapter(
                    id: chapter.id,
                    title: chapter.attributes.title ?? "Unknown",
                    chapterNum: Float(chapter.attributes.chapter ?? "0") ?? 0,
                    volumeNum: Int(chapter.attributes.volume ?? "0")
                )
            }
            return data
        } catch {
            print("[getChapterList] error: \(error)")
            return []
        }
    }
    
    func getPageList(chapter: Chapter) async -> [Page] {
        do {
            let atHome: MDAtHomeResponse = try await URLSession.shared.object(from: URL(string: "https://api.mangadex.org/at-home/server/\(chapter.id)")!)
            guard let baseUrl = atHome.baseUrl else { throw MDError.errorResponse }
            if let chapter = atHome.chapter {
                return chapter.data.enumerated().map { index, dataString in
                    Page(index: index, imageURL: "\(baseUrl)/data/\(chapter.hash)/\(dataString)")
                }
            }
            let chapter: MDResponse<MDObject<MDChapter>> = try await URLSession.shared.object(from: URL(string: "https://api.mangadex.org/chapter/\(chapter.id)")!)
            guard let chapterObject = chapter.data?.attributes else { throw MDError.errorResponse }
            return chapterObject.data.enumerated().map { index, dataString in
                Page(index: index, imageURL: "\(baseUrl)/data/\(chapterObject.hash)/\(dataString)")
            }
        } catch {
            print("[getPageList] error: \(error), chapter: \(chapter)")
            return []
        }
    }
}
