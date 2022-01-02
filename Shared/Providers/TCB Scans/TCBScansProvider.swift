//
//  TCBScansProvider.swift
//  Aidoku
//
//  Created by Skitty on 1/2/22.
//

import Foundation
import SwiftSoup

class TCBScansProvider: MangaProvider {
    let id = "xyz.skitty.tcbscans"
    let name = "TCB Scans"
    let lang = "en"
    let containsNsfw = false
    
    let baseUrl = "https://onepiecechapters.com"
    
    func manga(from element: SwiftSoup.Element) -> Manga? {
        let titleElement = try? element.select("a.mb-3.text-white.text-lg.font-bold")
        let thumbnailElement = try? element.select(".w-24.h-24.object-cover.rounded-lg")
        if let title = try? titleElement?.text(), let id = try? titleElement?.attr("href") {
            return Manga(
                provider: self.id,
                id: id,
                title: title,
                author: "TCB Scans",
                thumbnailURL: try? thumbnailElement?.attr("src")
            )
        }
        return nil
    }
    
    func chapter(from element: SwiftSoup.Element) -> Chapter? {
        let name = try? element.select(".text-lg.font-bold:not(.flex)").text()
        let description = try? element.select(".text-gray-500").text()
        let url = try? element.attr("href")
        if let id = url, let chapterNum = name?.split(separator: " ").last, let chapterNum = Float(chapterNum) {
            return Chapter(
                id: id,
                title: description,
                chapterNum: chapterNum
            )
        }
        return nil
    }
    
    func getAllManga() -> MangaPageResult {
        do {
            let content = try String(contentsOf: URL(string: "\(baseUrl)/projects")!)
            let doc: Document = try SwiftSoup.parse(content)
            let elements = try doc.select(".bg-card.border.border-border.rounded.p-3.mb-3")
            let mangaList = elements.compactMap { element -> Manga? in
                manga(from: element)
            }
            return MangaPageResult(manga: mangaList, hasNextPage: false)
        } catch {
            print("error: \(error)")
            return MangaPageResult(manga: [], hasNextPage: false)
        }
    }
    
    func fetchSearchManga(query: String, page: Int = 0, filters: [String] = []) async -> MangaPageResult {
        let mangaList = getAllManga().manga
        return MangaPageResult(manga: mangaList.filter { $0.title.contains(query) }, hasNextPage: false)
    }
    
    func getMangaDetails(id: String) async -> Manga {
        do {
            let content = try String(contentsOf: URL(string: baseUrl + id)!)
            let doc: Document = try SwiftSoup.parse(content)
            let descElement = try doc.select(".order-1.bg-card.border.border-border.rounded.py-3")
            let title = try descElement.select(".my-3.font-bold.text-3xl").text()
            let desc = try? descElement.select(".leading-6.my-3").text()
            let url = try? descElement.select(".flex.items-center.justify-center img").attr("src")
            return Manga(
                provider: self.id,
                id: id,
                title: title,
                author: "TCB Scans",
                description: desc,
                thumbnailURL: url
            )
        } catch {
            print("error: \(error)")
            return Manga(provider: self.id, id: id, title: "Error")
        }
    }
    
    func getChapterList(id: String) async -> [Chapter] {
        do {
            let content = try String(contentsOf: URL(string: baseUrl + id)!)
            let doc: Document = try SwiftSoup.parse(content)
            let elements = try doc.select(".block.border.border-border.bg-card.mb-3.p-3.rounded")
            let chapterList = elements.compactMap { element -> Chapter? in
                chapter(from: element)
            }
            return chapterList.reversed()
        } catch {
            print("error: \(error)")
            return []
        }
    }
    
    func getPageList(chapter: Chapter) async -> [Page] {
        do {
            let content = try String(contentsOf: URL(string: baseUrl + chapter.id)!)
            let doc: Document = try SwiftSoup.parse(content)
            let elements = try doc.select(".flex.flex-col.items-center.justify-center picture img")
            var i = -1
            let pageList = elements.compactMap { element -> Page? in
                i += 1
                return Page(index: i, imageURL: try? element.attr("src"))
            }
            return pageList
        } catch {
            print("error: \(error)")
            return []
        }
    }
    
    func getMangaCoverURL(manga: Manga, override: Bool = false) async -> String {
        if let url = manga.thumbnailURL {
            return url
        }
        return ""
    }
}
