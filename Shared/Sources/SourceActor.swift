//
//  SourceActor.swift
//  Aidoku
//
//  Created by Skitty on 2/21/22.
//

import Foundation

actor SourceActor {

    var source: Source

    enum SourceError: Error {
        case vmNotLoaded
        case missingValue
    }

    init(source: Source) {
        self.source = source
    }

    func initialize() throws {
        try source.globalStore.vm.call("initialize")
    }

    func getMangaList(filters: [FilterBase], page: Int = 1) -> MangaPageResult {
        let filterDescriptor = source.globalStore.storeStdValue(filters)

        let pageResultDescriptor: Int32 = (try? source.globalStore.vm.call("get_manga_list", filterDescriptor, Int32(page))) ?? -1

        let result = source.globalStore.readStdValue(pageResultDescriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(pageResultDescriptor)
        source.globalStore.removeStdValue(filterDescriptor)

        return result
    }

    func getMangaListing(listing: Listing, page: Int = 1) -> MangaPageResult {
        let listingDescriptor = source.globalStore.storeStdValue(listing)

        let pageResultDescriptor: Int32 = (try? source.globalStore.vm.call("get_manga_listing", listingDescriptor, Int32(page))) ?? -1

        let result = source.globalStore.readStdValue(pageResultDescriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(pageResultDescriptor)
        source.globalStore.removeStdValue(listingDescriptor)

        return result
    }

    func getMangaDetails(manga: Manga) throws -> Manga {
        let mangaDescriptor = source.globalStore.storeStdValue(manga)

        let resultMangaDescriptor: Int32 = (try? source.globalStore.vm.call("get_manga_details", mangaDescriptor)) ?? -1

        let manga = source.globalStore.readStdValue(resultMangaDescriptor) as? Manga
        source.globalStore.removeStdValue(resultMangaDescriptor)
        source.globalStore.removeStdValue(mangaDescriptor)

        guard let manga = manga else { throw SourceError.missingValue }

        return manga
    }

    func getChapterList(manga: Manga) -> [Chapter] {
        let mangaDescriptor = source.globalStore.storeStdValue(manga)

        source.globalStore.chapterCounter = 0
        source.globalStore.currentManga = manga.id

        let chapterListDescriptor: Int32 = (try? source.globalStore.vm.call("get_chapter_list", mangaDescriptor)) ?? -1

        source.globalStore.chapterCounter = 0

        let chapters = source.globalStore.readStdValue(chapterListDescriptor) as? [Chapter] ?? []
        source.globalStore.removeStdValue(chapterListDescriptor)
        source.globalStore.removeStdValue(mangaDescriptor)

        for i in 0..<chapters.count {
            chapters[i].mangaId = manga.id
        }

        return chapters
    }

    func getPageList(chapter: Chapter) -> [Page] {
        let chapterDescriptor = source.globalStore.storeStdValue(chapter)

        let pageListDescriptor: Int32 = (try? source.globalStore.vm.call("get_page_list", chapterDescriptor)) ?? -1

        var pages = source.globalStore.readStdValue(pageListDescriptor) as? [Page] ?? []
        source.globalStore.removeStdValue(pageListDescriptor)
        source.globalStore.removeStdValue(chapterDescriptor)

        for i in 0..<pages.count {
            pages[i].chapterId = chapter.id
        }

        return pages
    }

    func getImageRequest(url: String) throws -> WasmRequestObject {
        source.globalStore.requestsPointer += 1
        var request = WasmRequestObject(id: source.globalStore.requestsPointer)
        guard !url.isEmpty else { return request }

        request.URL = url

        // add cloudflare headers
        request.headers["User-Agent"] = WasmNet.defaultUserAgent
        if let url = URL(string: url),
           let cookies = HTTPCookie.requestHeaderFields(with: HTTPCookieStorage.shared.cookies(for: url) ?? [])["Cookie"] {
            request.headers["Cookie"] = cookies
        }
        source.globalStore.requests[source.globalStore.requestsPointer] = request

        try? source.globalStore.vm.call("modify_image_request", Int32(request.id))

        guard let request = source.globalStore.requests[request.id] else { throw SourceError.missingValue }

        source.globalStore.requests.removeValue(forKey: request.id)

        return request
    }

    func handleUrl(url: String) throws -> DeepLink {
        let urlDescriptor = source.globalStore.storeStdValue(url)

        let deepLinkDescriptor: Int32 = (try? source.globalStore.vm.call("handle_url", urlDescriptor)) ?? -1

        let deepLink = source.globalStore.readStdValue(deepLinkDescriptor) as? DeepLink
        source.globalStore.removeStdValue(deepLinkDescriptor)
        source.globalStore.removeStdValue(urlDescriptor)

        guard let deepLink = deepLink else { throw SourceError.missingValue }

        if let manga = deepLink.manga {
            deepLink.chapter?.mangaId = manga.id
        }

        return deepLink
    }

    func handleNotification(notification: String) {
        let notificationDescriptor = source.globalStore.storeStdValue(notification)

        try? source.globalStore.vm.call("handle_notification", notificationDescriptor)

        source.globalStore.removeStdValue(notificationDescriptor)
    }
}
