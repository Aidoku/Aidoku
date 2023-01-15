//
//  TachiJsSource.swift
//  Aidoku
//
//  Created by Skitty on 1/13/23.
//

import JavaScriptCore

protocol AnyTypeOfArray {}
extension Array: AnyTypeOfArray {}

class TachiJsSource: Source {

    let context = JSContext()!

    override init(from url: URL) throws {
        super.init()

        self.url = url

        let jsonData = try Data(contentsOf: url.appendingPathComponent("source.json"))
        manifest = try JSONDecoder().decode(SourceManifest.self, from: jsonData)
        let jsData = try Data(contentsOf: url.appendingPathComponent("main.js"))

        context.exceptionHandler = { _, error in
            if let error = error {
                let message = String(describing: error)
                print(message)
            }
        }

        let consoleLog: @convention(block) (String, Any?) -> Void = { message, two in
            print("console.log:", message, (two as? String) != "undefined" ? two ?? "" : "")
        }
        context.setObject(consoleLog, forKeyedSubscript: "_consoleLog" as NSCopying & NSObjectProtocol)
        _ = context.evaluateScript("var console = { log: function(message, b) { _consoleLog(message, b) } }")

        let promiseBlock: @convention(block) (JSValue) -> Promise = { val in
            Promise(executor: val)
        }
        context.setObject(promiseBlock, forKeyedSubscript: "Promise" as NSCopying & NSObjectProtocol)

        let domBlock: @convention(block) () -> DOMParser = {
            DOMParser()
        }
        context.setObject(domBlock, forKeyedSubscript: "DOMParser" as NSCopying & NSObjectProtocol)

        context.setObject(unsafeBitCast(fetch, to: AnyObject.self), forKeyedSubscript: "_fetch" as NSCopying & NSObjectProtocol)
        _ = context.evaluateScript("var window = { fetch: _fetch }")

        context.setObject(Element.self, forKeyedSubscript: "Element" as NSCopying & NSObjectProtocol)
//        context.setObject(Node.self, forKeyedSubscript: "Node" as NSCopying & NSObjectProtocol)

        context.evaluateScript("var Node = { ELEMENT_NODE: 1 }") // fix kotlin isElement check

        // add stub objects
        context.evaluateScript("""
class JsManga {}
class JsChapter {}
class JsPage {}
class JsMangasPage {}
""")

        // load main.js
        let jsString = String(data: jsData, encoding: .utf8)
        context.evaluateScript(jsString)
    }

    override func getFilters() async throws -> [FilterBase] {
        []
    }

    override func fetchSearchManga(query: String, filters: [FilterBase] = [], page: Int = 1) async throws -> MangaPageResult {
        try await getMangaList(filters: [], page: page)
    }

    enum JSError: Error {
        case jsError(JSValue)
        case parseError
    }

    private func callTachiJs<T>(call: String) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let thenBlock: @convention(block) (JSValue) -> Void = { value in
                let object: T
                if T.self is AnyTypeOfArray.Type {
                    // swiftlint:disable:next force_cast
                    object = (value.toArray() as? T) ?? ([] as! T)
                } else {
                    // swiftlint:disable:next force_cast
                    object = (value.toObject() as? T) ?? ([:] as! T)
                }
                continuation.resume(returning: object)
            }
            let catchBlock: @convention(block) (JSValue) -> Void = { error in
                print("CAUGHT ERROR", error)
                continuation.resume(throwing: JSError.jsError(error))
            }
            let promise = context.evaluateScript("this.\(manifest.info.module ?? "")." + call)
            _ = (promise?.toObject() as? Promise)?
                .then(JSValue(object: thenBlock, in: context))
                .catch(JSValue(object: catchBlock, in: context))
        }
    }

    override func getMangaList(filters: [FilterBase], page: Int = 1) async throws -> MangaPageResult {
        let object: [String: Any?] = try await callTachiJs(call: "fetchPopularManga(\(page))")

        var manga: [Manga] = []
        for mangaObject in (object["mangas"] as? [[String: Any?]]) ?? [] {
            guard let id = mangaObject["url"] as? String else { continue }
            let coverUrl: URL?
            if let thumbnailUrl = mangaObject["thumbnailUrl"] as? String {
                coverUrl = URL(string: thumbnailUrl)
            } else {
                coverUrl = nil
            }
            manga.append(Manga(
                sourceId: self.id,
                id: id,
                title: mangaObject["title"] as? String,
                coverUrl: coverUrl
            ))
        }
        return MangaPageResult(
            manga: manga,
            hasNextPage: (object["hasNextPage"] as? Bool) == true
        )
    }

    override func getMangaListing(listing: Listing, page: Int = 1) async throws -> MangaPageResult {
        MangaPageResult(manga: [], hasNextPage: false)
    }

    override func getMangaDetails(manga: Manga) async throws -> Manga {
        context.evaluateScript("""
var _manga = new JsManga();
_manga.url = "\(manga.id)";
_manga.title = \(manga.title != nil ? "\"\(manga.title!)\"" : "null");
_manga
""")
        // swiftlint:disable:next force_try
        let object: [String: Any?] = try! await callTachiJs(call: "fetchMangaDetails(_manga)")

        let coverUrl: URL?
        if let thumbnailUrl = object["thumbnailUrl"] as? String {
            coverUrl = URL(string: thumbnailUrl)
        } else {
            coverUrl = nil
        }
        let newManga = Manga(
            sourceId: id,
            id: (object["url"] as? String) ?? manga.id,
            title: object["title"] as? String,
            author: object["author"] as? String,
            description: object["description"] as? String,
            coverUrl: coverUrl
        )

        return manga.copy(from: newManga)
    }

    override func getChapterList(manga: Manga) async throws -> [Chapter] {
        context.evaluateScript("""
var _manga2 = new JsManga();
_manga2.url = "\(manga.id)";
_manga2.title = \(manga.title != nil ? "\"\(manga.title!)\"" : "null");
_manga2
""")
        // swiftlint:disable:next force_try
        let object: [[String: Any?]] = try! await callTachiJs(call: "fetchChapterList(_manga2)")

        var chapters: [Chapter] = []
        for (i, chapter) in object.enumerated() {
            guard let url = chapter["url"] as? String else { continue }
            let chapterNum = chapter["chapterNumber"] as? Float
            chapters.append(
                Chapter(
                    sourceId: id,
                    id: url,
                    mangaId: manga.id,
                    title: chapter["name"] as? String,
                    scanlator: chapter["scanlator"] as? String,
                    chapterNum: chapterNum ?? -1 != -1 ? chapterNum : nil,
                    sourceOrder: i
                )
            )
        }

        return chapters
    }

    override func getPageList(chapter: Chapter, skipDownloadedCheck: Bool = false) async throws -> [Page] {
        context.evaluateScript("""
var _chapter = new JsChapter();
_chapter.url = "\(chapter.id)";
_chapter.title = \(chapter.title != nil ? "\"\(chapter.title!)\"" : "null");
""")
        // swiftlint:disable:next force_try
        let object: [[String: Any?]] = try! await callTachiJs(call: "fetchPageList(_chapter)")

        var pages: [Page] = []
        for page in object {
            guard let index = page["index"] as? Int else { continue }
            pages.append(Page(
                chapterId: chapter.id,
                index: index,
                imageURL: page["imageUrl"] as? String
            ))
        }

        return pages
    }
}
